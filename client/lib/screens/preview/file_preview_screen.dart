import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/node.dart';
import '../../providers/auth_provider.dart';
import '../../services/download_save_service.dart';
import '../../services/logger.dart';
import '../../services/storage_service.dart';
import '../../utils/file_type_helper.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/error_retry.dart';
import 'preview_web_interop.dart'
    if (dart.library.io) 'preview_web_interop_stub.dart';

// ──────────────────────────────────────────────────────────────────────────────

/// 텍스트 미저장 변경 다이얼로그 선택 결과 — P007 §4
enum _UnsavedAction { save, discard, cancel }

/// Phase 6 파일 미리보기 — image/text/unsupported 구현, pdf/video/audio placeholder — D006 §4, §6, §12, L006 §3~§5
///
/// 진입: Navigator.push (GoRouter 라우트 미추가 — D006 §12)
/// 반환: Navigator.pop(bool) — true이면 FileProvider.loadChildren() 호출 필요
///
/// 화면 상태 (L006 ST-L6-01):
///   _isLoading == true                    → 로딩 인디케이터
///   _error != null                        → ErrorRetry 위젯
///   _isLoading == false && _error == null  → previewType별 분기
class FilePreviewScreen extends StatefulWidget {
  final Node node;
  final String storageUuid;
  final String userUuid;
  final String groupUuid;
  final bool autoEdit;

  const FilePreviewScreen({
    super.key,
    required this.node,
    required this.storageUuid,
    required this.userUuid,
    required this.groupUuid,
    this.autoEdit = false,
  });

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  // ── 화면 수준 상태 (L006 §3 ST-L6-01) ──────────────────────────────────────
  bool _isLoading = false;
  String? _error;
  Uint8List? _fileBytes;

  /// _fileSizeChanged: 텍스트 편집 저장 성공 시 true.
  /// pop 결과로 전달 → FileListScreen이 목록 갱신 여부를 판단 (L006 §7 ST-L6-07).
  bool _fileSizeChanged = false;

  late final PreviewType _previewType;

  // ── PDF 상태 (T033) ────────────────────────────────────────────────────────
  PdfControllerPinch? _pdfController;
  File? _pdfTempFile;

  // ── 비디오 상태 (T040) ────────────────────────────────────────────────────────
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  File? _videoTempFile;
  /// 웹 전용: Blob URL — dispose 시 _previewRevokeObjectUrl 호출 대상.
  String? _videoBlobUrl;

  // ── 오디오 상태 (T041) ────────────────────────────────────────────────────────
  AudioPlayer? _audioPlayer;
  File? _audioTempFile;
  /// 웹 전용: Blob URL — dispose 시 _previewRevokeObjectUrl 호출 대상.
  String? _audioBlobUrl;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  bool _audioIsPlaying = false;
  StreamSubscription<Duration>? _audioDurationSub;
  StreamSubscription<Duration>? _audioPositionSub;
  StreamSubscription<void>? _audioCompleteSub;
  StreamSubscription<PlayerState>? _audioStateSub;

  // ── 텍스트 편집 상태 (L006 §3 ST-L6-02) ────────────────────────────────────
  String? _textContent;
  String? _editedContent;
  bool _isEditMode = false;
  bool _isSaving = false;
  late final TextEditingController _textController;
  final FocusNode _textFocusNode = FocusNode();

  // ── 서비스 ─────────────────────────────────────────────────────────────────
  StorageService get _storageService =>
      StorageService(context.read<AuthProvider>().dio);

  /// StorageService에 updateFileContent가 미추가된 상태이므로 Dio 직접 사용.
  Dio get _dio => context.read<AuthProvider>().dio;

  // ── 라이프사이클 ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _previewType = FileTypeHelper.getPreviewType(widget.node.name);
    // unsupported: 다운로드 API 자동 호출 금지 (L006 ST-L6-01 #3)
    if (_previewType != PreviewType.unsupported) {
      _loadFile();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    _pdfController?.dispose();
    try {
      _pdfTempFile?.deleteSync();
    } catch (_) {}
    _chewieController?.dispose();
    _videoController?.dispose();
    if (kIsWeb && _videoBlobUrl != null) {
      previewRevokeBlobUrl(_videoBlobUrl!);
    }
    try {
      _videoTempFile?.deleteSync();
    } catch (_) {}
    _audioDurationSub?.cancel();
    _audioPositionSub?.cancel();
    _audioCompleteSub?.cancel();
    _audioStateSub?.cancel();
    _audioPlayer?.dispose();
    if (kIsWeb && _audioBlobUrl != null) {
      previewRevokeBlobUrl(_audioBlobUrl!);
    }
    try {
      _audioTempFile?.deleteSync();
    } catch (_) {}
    super.dispose();
  }

  // ── 파일 로드 ───────────────────────────────────────────────────────────────

  /// GET /storages/download → _fileBytes 수신.
  /// 에러 시 메시지 분기 (P007 §2 기준):
  ///   404 → "파일을 찾을 수 없습니다"
  ///   403 → "접근 권한이 없습니다"
  ///   나머지 → "파일을 불러올 수 없습니다"
  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await _storageService.download(
        storageUuid: widget.storageUuid,
        userUuid: widget.userUuid,
        groupUuid: widget.groupUuid,
        nodeUuid: widget.node.nodeUuid!,
      );
      if (!mounted) return;
      final data = response.data;
      final bytes = data != null ? Uint8List.fromList(data) : null;
      setState(() {
        _fileBytes = bytes;
        _isLoading = false;
        // text 타입: UTF-8 디코딩 → 뷰어/편집 상태 초기화 (L006 §4, P007 §4)
        if (_previewType == PreviewType.text && bytes != null) {
          _textContent = utf8.decode(bytes, allowMalformed: true);
          _editedContent = _textContent;
          _textController.text = _textContent ?? '';
          if (widget.autoEdit) _isEditMode = true;
        }
        if (_previewType == PreviewType.pdf && bytes != null) {
          _initPdfController(bytes);
        }
        if (_previewType == PreviewType.video && bytes != null) {
          _initVideoController(bytes);
        }
        if (_previewType == PreviewType.audio && bytes != null) {
          _initAudioController(bytes);
        }
      });
      if (widget.autoEdit && _previewType == PreviewType.text) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _textFocusNode.requestFocus();
        });
      }
      AppLogger.info(
          'FilePreviewScreen', '파일 로드 완료: ${widget.node.name}');
    } on DioException catch (e) {
      if (!mounted) return;
      final statusCode = e.response?.statusCode;
      final message = statusCode == 404
          ? 'File not found'
          : statusCode == 403
              ? 'Access denied'
              : 'Unable to load file';
      AppLogger.error(
          'FilePreviewScreen', '파일 로드 실패: $statusCode ${e.message}');
      setState(() {
        _isLoading = false;
        _error = message;
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.error('FilePreviewScreen', '파일 로드 실패(기타): $e');
      setState(() {
        _isLoading = false;
        _error = 'Unable to load file';
      });
    }
  }

  // ── 다운로드 ───────────────────────────────────────────────────────────────

  /// AppBar 다운로드 버튼 핸들러.
  /// 이미 로드된 _fileBytes가 있으면 재사용, 없으면 API 재호출 (unsupported 타입 등).
  Future<void> _handleDownload() async {
    try {
      List<int> bytes;
      String filename;

      if (_fileBytes != null) {
        bytes = _fileBytes!;
        filename = widget.node.name;
      } else {
        final response = await _storageService.download(
          storageUuid: widget.storageUuid,
          userUuid: widget.userUuid,
          groupUuid: widget.groupUuid,
          nodeUuid: widget.node.nodeUuid!,
        );
        final data = response.data;
        if (data == null || data.isEmpty) {
          if (mounted) AppToast.error(context, 'Download failed');
          return;
        }
        bytes = data;
        final cdHeader = response.headers.value('content-disposition');
        filename =
            DownloadSaveService.extractFilename(cdHeader) ?? widget.node.name;
      }

      await DownloadSaveService.saveBytes(bytes: bytes, filename: filename);
      AppLogger.info('FilePreviewScreen', '다운로드 완료: $filename');
      if (mounted) AppToast.success(context, 'Download complete');
    } on DioException catch (e) {
      AppLogger.error(
          'FilePreviewScreen', '다운로드 실패: ${e.response?.statusCode}');
      if (mounted) AppToast.error(context, 'Download failed');
    }
  }

  // ── 텍스트 편집 ────────────────────────────────────────────────────────────

  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
      _textController.text = _editedContent ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocusNode.requestFocus();
    });
  }

  void _cancelEdit() {
    // 취소: 원본 복원, 변경 감지 없이 즉시 폐기 (L006 ST-L6-02 #2)
    setState(() {
      _editedContent = _textContent;
      _textController.text = _textContent ?? '';
      _isEditMode = false;
    });
  }

  /// PUT /storages/update_file_content — 텍스트 저장 (P007 §5)
  /// 성공: 뷰어 복귀 + 성공 토스트 + _fileSizeChanged = true
  /// 실패: 에러 토스트 + 편집 모드 유지 (수정 내용 보존)
  Future<void> _saveFile() async {
    if (_editedContent == null) return;
    setState(() => _isSaving = true);
    try {
      await _dio.put(
        '/storages/update_file_content',
        data: {
          'storage_uuid': widget.storageUuid,
          'user_uuid': widget.userUuid,
          'node_uuid': widget.node.nodeUuid,
          'content': _editedContent,
        },
      );
      if (!mounted) return;
      setState(() {
        _textContent = _editedContent;
        _isEditMode = false;
        _isSaving = false;
        _fileSizeChanged = true;
      });
      AppLogger.info('FilePreviewScreen', '텍스트 저장 완료: ${widget.node.name}');
      AppToast.success(context, 'Saved');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final statusCode = e.response?.statusCode;
      final message = statusCode == 404
          ? 'File not found'
          : statusCode == 403
              ? 'No permission to save'
              : 'Save failed';
      AppLogger.error('FilePreviewScreen', '텍스트 저장 실패: $statusCode');
      AppToast.error(context, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppLogger.error('FilePreviewScreen', '텍스트 저장 실패(기타): $e');
      AppToast.error(context, 'Save failed');
    }
  }

  /// 미저장 변경사항 확인 다이얼로그 — P007 §4, L006 §5
  /// 선택지: 저장 / 저장 안 함 / 취소
  Future<void> _showUnsavedChangesDialog() async {
    final result = await showDialog<_UnsavedAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: const Text('You have unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsavedAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsavedAction.discard),
            child: const Text('Don\'t Save'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsavedAction.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (result) {
      case _UnsavedAction.save:
        await _saveFile();
        if (!mounted) return;
        // 저장 성공 시 _isEditMode==false → pop(true), 실패 시 편집 유지
        if (!_isEditMode) Navigator.of(context).pop(true);
      case _UnsavedAction.discard:
        // 저장 안 함: 이전 저장 이력(_fileSizeChanged) 유지하여 전달
        Navigator.of(context).pop(_fileSizeChanged);
      case _UnsavedAction.cancel:
      case null:
        break; // 편집 화면 유지
    }
  }

  // ── 뒤로가기 ───────────────────────────────────────────────────────────────

  /// 뒤로가기 분기 — L006 §5 ST-L6-05 결정 트리
  void _onBack() {
    // saving 중: pop 차단
    if (_isSaving) return;
    if (_isEditMode) {
      if (_editedContent != _textContent) {
        // 변경 있음: 3선택 다이얼로그
        _showUnsavedChangesDialog();
        return;
      }
      // 변경 없음: 편집 모드 해제 후 즉시 pop
      setState(() => _isEditMode = false);
    }
    Navigator.of(context).pop(_fileSizeChanged);
  }

  // ── AppBar 액션 빌더 ────────────────────────────────────────────────────────

  /// 상태/previewType에 따라 AppBar actions를 반환한다 (D006 §4, L006 ST-L6-02).
  List<Widget> _buildAppBarActions() {
    // loading 중이거나 에러 상태에서는 버튼 미표시 (L006 ST-L6-01 #4)
    if (_isLoading || _error != null) return const [];

    if (_previewType == PreviewType.text) {
      if (_isEditMode) {
        // 편집 모드: [저장] [취소] — saving 중 비활성화
        return [
          TextButton(
            onPressed: _isSaving ? null : _saveFile,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
          TextButton(
            onPressed: _isSaving ? null : _cancelEdit,
            child: const Text('Cancel'),
          ),
        ];
      }
      // 뷰어 모드: [편집] [다운로드]
      return [
        IconButton(
          icon: const Icon(Icons.edit_rounded),
          tooltip: 'Edit',
          onPressed: _enterEditMode,
        ),
        IconButton(
          icon: const Icon(Icons.download_rounded),
          tooltip: 'Download',
          onPressed: _handleDownload,
        ),
      ];
    }

    // image / unsupported / pdf(placeholder) / video(placeholder) / audio(placeholder)
    return [
      IconButton(
        icon: const Icon(Icons.download_rounded),
        tooltip: 'Download',
        onPressed: _handleDownload,
      ),
    ];
  }

  // ── 빌드 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _onBack),
          title: Text(
            (_previewType == PreviewType.text &&
                    widget.node.name.toLowerCase().endsWith('.md'))
                ? widget.node.name.substring(0, widget.node.name.length - 3)
                : widget.node.name,
            style: const TextStyle(fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
          actions: _buildAppBarActions(),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorView();
    }
    return _buildPreview();
  }

  /// 에러 뷰 — PDF/video 타입은 ErrorRetry + 다운로드 버튼, 나머지는 ErrorRetry만.
  Widget _buildErrorView() {
    if (_previewType == PreviewType.pdf || _previewType == PreviewType.video || _previewType == PreviewType.audio) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ErrorRetry(
                message: _error!,
                onRetry: _loadFile,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _handleDownload,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download'),
              ),
            ],
          ),
        ),
      );
    }
    return ErrorRetry(
      message: _error!,
      onRetry: _loadFile,
    );
  }

  /// previewType별 분기 — image/text/unsupported/pdf 구현, video/audio T034~T035 범위.
  Widget _buildPreview() {
    switch (_previewType) {
      case PreviewType.image:
        return _buildImagePreview();
      case PreviewType.text:
        return _buildTextPreview();
      case PreviewType.unsupported:
        return _buildUnsupportedPreview();
      case PreviewType.pdf:
        return _buildPdfPreview();
      case PreviewType.video:
        return _buildVideoPreview();
      case PreviewType.audio:
        return _buildAudioPreview();
    }
  }

  // ── 이미지 뷰어 (P007 §3, D006 FP05) ────────────────────────────────────────

  /// `InteractiveViewer` + `Image.memory` — 핀치 줌/패닝 지원.
  /// 디코딩 실패 시 post-frame callback으로 `_error` 설정 → ErrorRetry 전환.
  Widget _buildImagePreview() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: Image.memory(
          _fileBytes!,
          errorBuilder: (context, error, stackTrace) {
            // Image.memory는 errorBuilder를 build 중에 호출하므로,
            // setState는 post-frame callback으로 예약한다.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _error = 'Unable to display image');
              }
            });
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  // ── 텍스트 뷰어/편집 (P007 §4, D006 FP06~FP10) ──────────────────────────────

  /// 뷰어 모드: `SingleChildScrollView + SelectableText` 모노스페이스.
  /// 편집 모드: `TextField(maxLines: null)` — `_textController` 바인딩.
  Widget _buildTextPreview() {
    if (_isEditMode) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _textController,
          focusNode: _textFocusNode,
          maxLines: null,
          onChanged: (value) => _editedContent = value,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(border: InputBorder.none),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        _textContent ?? '',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }

  // ── PDF 뷰어 (T033, P007 §6, §12, L006 §3 ST-L6-05) ──────────────────────────

  /// bytes를 PdfControllerPinch에 연결.
  /// kIsWeb: PdfDocument.openData(bytes) 사용 (dart:io / getTemporaryDirectory 우회).
  /// 비웹: 임시 파일로 저장 후 PdfDocument.openFile() 사용.
  /// 실패 시 _error = "PDF를 표시할 수 없습니다" 로 전환.
  Future<void> _initPdfController(Uint8List bytes) async {
    try {
      if (kIsWeb) {
        // 웹: dart:io File / getTemporaryDirectory() 미지원 → openData로 우회 (T035)
        final controller = PdfControllerPinch(
          document: PdfDocument.openData(bytes),
        );
        if (!mounted) {
          controller.dispose();
          return;
        }
        setState(() {
          _pdfController = controller;
        });
      } else {
        final tempDir = await getTemporaryDirectory();
        final nodeUuid = widget.node.nodeUuid ?? 'unknown';
        final tempFile = File('${tempDir.path}/preview_$nodeUuid.pdf');
        await tempFile.writeAsBytes(bytes);
        final controller = PdfControllerPinch(
          document: PdfDocument.openFile(tempFile.path),
        );
        if (!mounted) {
          controller.dispose();
          try { tempFile.deleteSync(); } catch (_) {}
          return;
        }
        setState(() {
          _pdfTempFile = tempFile;
          _pdfController = controller;
        });
      }
    } catch (e) {
      AppLogger.error('FilePreviewScreen', 'PDF 초기화 실패: $e');
      if (mounted) {
        setState(() => _error = 'Cannot display PDF');
      }
    }
  }

  /// PdfControllerPinch가 준비되면 PdfViewPinch 렌더링.
  /// 준비 전이면 로딩 인디케이터, 초기화 실패 시 에러+다운로드 버튼.
  Widget _buildPdfPreview() {
    if (_pdfController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PdfViewPinch(
      controller: _pdfController!,
      onDocumentError: (error) {
        AppLogger.error('FilePreviewScreen', 'PDF 렌더링 오류: $error');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _error = 'Unable to display PDF');
          }
        });
      },
    );
  }

  // ── 비디오 플레이어 (T040, P007 §7, §12, L006 §3 ST-L6-06) ───────────────────

  /// bytes → VideoPlayerController 초기화.
  /// 웹(kIsWeb): bytes → Blob URL → VideoPlayerController.networkUrl() 경로 (NR019).
  /// 비웹: 임시 파일 저장 후 VideoPlayerController.file() 경로.
  /// 실패 시 _error = "비디오를 재생할 수 없습니다"로 전환.
  Future<void> _initVideoController(Uint8List bytes) async {
    if (kIsWeb) {
      String? blobUrl;
      try {
        final uint8 = Uint8List.fromList(bytes.toList());
        final ext = widget.node.name.contains('.')
            ? widget.node.name.split('.').last.toLowerCase()
            : '';
        final mimeType = const {
          'mp4': 'video/mp4',
          'webm': 'video/webm',
          'ogg': 'video/ogg',
          'mov': 'video/quicktime',
        }[ext] ?? 'video/mp4';
        AppLogger.info(
          'FilePreviewScreen',
          '비디오 웹 초기화 시작: name=${widget.node.name}, '
              'bytes=${bytes.length}, copiedBytes=${uint8.length}, '
              'ext=$ext, mime=$mimeType',
        );
        blobUrl = previewCreateBlobUrl(uint8, mimeType);
        final parsedUri = Uri.parse(blobUrl);
        final roundTripUrl = parsedUri.toString();
        AppLogger.info(
          'FilePreviewScreen',
          '비디오 웹 Blob URL 생성: scheme=${parsedUri.scheme}, '
              'roundTripEqual=${roundTripUrl == blobUrl}, url=$blobUrl',
        );
        final videoController = VideoPlayerController.networkUrl(parsedUri);
        AppLogger.info(
          'FilePreviewScreen',
          '비디오 웹 controller.initialize() 호출',
        );
        await videoController.initialize();
        AppLogger.info(
          'FilePreviewScreen',
          '비디오 웹 초기화 성공: '
              'initialized=${videoController.value.isInitialized}, '
              'durationMs=${videoController.value.duration.inMilliseconds}, '
              'size=${videoController.value.size}',
        );
        final chewieController = ChewieController(
          videoPlayerController: videoController,
          autoPlay: false,
          looping: false,
        );
        if (!mounted) {
          chewieController.dispose();
          videoController.dispose();
          previewRevokeBlobUrl(blobUrl);
          return;
        }
        setState(() {
          _videoBlobUrl = blobUrl;
          _videoController = videoController;
          _chewieController = chewieController;
        });
      } catch (e, st) {
        AppLogger.error(
          'FilePreviewScreen',
          '비디오 초기화 실패(웹): type=${e.runtimeType}, '
              'error=$e, blobUrl=$blobUrl',
        );
        AppLogger.error(
          'FilePreviewScreen',
          '비디오 초기화 실패(웹) stack: $st',
        );
        if (mounted) setState(() => _error = 'Unable to play video');
      }
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final nodeUuid = widget.node.nodeUuid ?? 'unknown';
      final name = widget.node.name;
      final ext = name.contains('.') ? name.split('.').last : '';
      final suffix = ext.isNotEmpty ? '.$ext' : '';
      final tempFile = File('${tempDir.path}/preview_$nodeUuid$suffix');
      await tempFile.writeAsBytes(bytes);
      final videoController = VideoPlayerController.file(tempFile);
      await videoController.initialize();
      final chewieController = ChewieController(
        videoPlayerController: videoController,
        autoPlay: false,
        looping: false,
      );
      if (!mounted) {
        chewieController.dispose();
        videoController.dispose();
        try {
          tempFile.deleteSync();
        } catch (_) {}
        return;
      }
      setState(() {
        _videoTempFile = tempFile;
        _videoController = videoController;
        _chewieController = chewieController;
      });
    } catch (e) {
      AppLogger.error('FilePreviewScreen', '비디오 초기화 실패: $e');
      if (mounted) {
        setState(() => _error = 'Cannot play video');
      }
    }
  }

  /// ChewieController가 준비되면 Chewie 위젯 렌더링.
  /// 준비 전이면 로딩 인디케이터.
  Widget _buildVideoPreview() {
    if (_chewieController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Chewie(controller: _chewieController!);
  }

  // ── 오디오 플레이어 (T041, P007 §8, §10, §12, L006 §3 ST-L6-06) ───────────────

  /// bytes → 임시 파일 저장 → AudioPlayer 초기화 → 재생.
  /// 실패 시 _error = "오디오를 재생할 수 없습니다"로 전환.
  Future<void> _initAudioController(Uint8List bytes) async {
    if (kIsWeb) {
      try {
        final ext = widget.node.name.contains('.')
            ? widget.node.name.split('.').last.toLowerCase()
            : '';
        final mimeType = const {
          'mp3': 'audio/mpeg',
          'wav': 'audio/wav',
          'flac': 'audio/flac',
          'm4a': 'audio/mp4',
        }[ext] ?? 'audio/mpeg';
        final uint8 = Uint8List.fromList(bytes.toList());
        final blobUrl = previewCreateBlobUrl(uint8, mimeType);
        final player = AudioPlayer();
        _audioDurationSub = player.onDurationChanged.listen((d) {
          if (mounted) setState(() => _audioDuration = d);
        });
        _audioPositionSub = player.onPositionChanged.listen((p) {
          if (mounted) setState(() => _audioPosition = p);
        });
        _audioCompleteSub = player.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _audioIsPlaying = false);
        });
        _audioStateSub = player.onPlayerStateChanged.listen((state) {
          if (mounted) {
            setState(() => _audioIsPlaying = state == PlayerState.playing);
          }
        });
        await player.play(UrlSource(blobUrl));
        if (!mounted) {
          _audioDurationSub?.cancel();
          _audioPositionSub?.cancel();
          _audioCompleteSub?.cancel();
          _audioStateSub?.cancel();
          await player.dispose();
          previewRevokeBlobUrl(blobUrl);
          return;
        }
        setState(() {
          _audioBlobUrl = blobUrl;
          _audioPlayer = player;
          _audioIsPlaying = true;
        });
      } catch (e) {
        AppLogger.error('FilePreviewScreen', 'Audio init failed (web): $e');
        if (mounted) setState(() => _error = 'Unable to play audio');
      }
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final nodeUuid = widget.node.nodeUuid ?? 'unknown';
      final name = widget.node.name;
      final ext = name.contains('.') ? name.split('.').last : '';
      final suffix = ext.isNotEmpty ? '.$ext' : '';
      final tempFile = File('${tempDir.path}/preview_$nodeUuid$suffix');
      await tempFile.writeAsBytes(bytes);
      final player = AudioPlayer();
      _audioDurationSub = player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _audioDuration = d);
      });
      _audioPositionSub = player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _audioPosition = p);
      });
      _audioCompleteSub = player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _audioIsPlaying = false);
      });
      _audioStateSub = player.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() => _audioIsPlaying = state == PlayerState.playing);
        }
      });
      await player.play(DeviceFileSource(tempFile.path));
      if (!mounted) {
        _audioDurationSub?.cancel();
        _audioPositionSub?.cancel();
        _audioCompleteSub?.cancel();
        _audioStateSub?.cancel();
        await player.dispose();
        try {
          tempFile.deleteSync();
        } catch (_) {}
        return;
      }
      setState(() {
        _audioTempFile = tempFile;
        _audioPlayer = player;
        _audioIsPlaying = true;
      });
    } catch (e) {
      AppLogger.error('FilePreviewScreen', 'Audio init failed: $e');
      if (mounted) setState(() => _error = 'Unable to play audio');
    }
  }

  /// AudioPlayer가 준비되면 오디오 플레이어 UI 렌더링.
  /// 준비 전이면 로딩 인디케이터.
  Widget _buildAudioPreview() {
    if (_audioPlayer == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final totalSec = _audioDuration.inSeconds.toDouble();
    final currentSec = totalSec > 0
        ? _audioPosition.inSeconds.toDouble().clamp(0.0, totalSec)
        : 0.0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.audio_file_rounded,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              widget.node.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            Slider(
              value: currentSec,
              min: 0,
              max: totalSec > 0 ? totalSec : 1,
              onChanged: (value) {
                _audioPlayer?.seek(Duration(seconds: value.toInt()));
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(_audioPosition),
                      style: const TextStyle(fontSize: 12)),
                  Text(_formatDuration(_audioDuration),
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.replay_10_rounded),
                  tooltip: 'Rewind 10s',
                  onPressed: () {
                    final pos = _audioPosition - const Duration(seconds: 10);
                    _audioPlayer?.seek(
                        pos < Duration.zero ? Duration.zero : pos);
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  iconSize: 48,
                  icon: Icon(_audioIsPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  tooltip: _audioIsPlaying ? 'Pause' : 'Play',
                  onPressed: () {
                    if (_audioIsPlaying) {
                      _audioPlayer?.pause();
                    } else {
                      _audioPlayer?.resume();
                    }
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.forward_10_rounded),
                  tooltip: 'Forward 10s',
                  onPressed: () {
                    final pos = _audioPosition + const Duration(seconds: 10);
                    _audioPlayer?.seek(
                        pos > _audioDuration ? _audioDuration : pos);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes =
        d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // ── 미지원 안내 (D006 §4-7, FP14) ──────────────────────────────────────────

  /// 파일 아이콘 + 안내 문구 + 다운로드 버튼.
  /// `_loadFile()` 미호출 상태 (L006 ST-L6-01 #3).
  Widget _buildUnsupportedPreview() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'This file type is not supported for preview',
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _handleDownload,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }
}
