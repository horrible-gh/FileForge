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
import '../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/download_progress_overlay.dart';
import '../../widgets/error_retry.dart';
import 'preview_web_interop.dart'
    if (dart.library.io) 'preview_web_interop_stub.dart';

// ──────────────────────────────────────────────────────────────────────────────

/// translated text textsave change translated text selection result — P007 §4
enum _UnsavedAction { save, discard, cancel }

/// Phase 6 file translated text — image/text/unsupported text, pdf/video/audio placeholder — D006 §4, §6, §12, L006 §3~§5
///
/// text: Navigator.push (GoRouter translated text textadd — D006 §12)
/// return: Navigator.pop(bool) — truetext FileProvider.loadChildren() text text
///
/// screen state (L006 ST-L6-01):
///   _isLoading == true                    → loading translated text
///   _error != null                        → ErrorRetry text
///   _isLoading == false && _error == null  → previewTypetext branch
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
  // ── screen text state (L006 §3 ST-L6-01) ──────────────────────────────────────
  bool _isLoading = false;
  String? _error;
  Uint8List? _fileBytes;

  /// _fileSizeChanged: translated text text save success text true.
  /// pop resulttext text → FileListScreentext text refresh translated text text (L006 §7 ST-L6-07).
  bool _fileSizeChanged = false;

  late final PreviewType _previewType;

  // ── PDF state (T033) ────────────────────────────────────────────────────────
  PdfControllerPinch? _pdfController;
  File? _pdfTempFile;

  // ── translated text state (T040) ────────────────────────────────────────────────────────
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  File? _videoTempFile;
  /// text text: Blob URL — dispose text _previewRevokeObjectUrl text text.
  String? _videoBlobUrl;

  // ── translated text state (T041) ────────────────────────────────────────────────────────
  AudioPlayer? _audioPlayer;
  File? _audioTempFile;
  /// text text: Blob URL — dispose text _previewRevokeObjectUrl text text.
  String? _audioBlobUrl;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  bool _audioIsPlaying = false;
  StreamSubscription<Duration>? _audioDurationSub;
  StreamSubscription<Duration>? _audioPositionSub;
  StreamSubscription<void>? _audioCompleteSub;
  StreamSubscription<PlayerState>? _audioStateSub;

  // ── translated text text state (L006 §3 ST-L6-02) ────────────────────────────────────
  String? _textContent;
  String? _editedContent;
  bool _isEditMode = false;
  bool _isSaving = false;
  late final TextEditingController _textController;
  final FocusNode _textFocusNode = FocusNode();

  // ── translated text ─────────────────────────────────────────────────────────────────
  StorageService get _storageService =>
      StorageService(context.read<AuthProvider>().dio);

  /// StorageServicetext updateFileContenttext textaddtext statetranslated text Dio text text.
  Dio get _dio => context.read<AuthProvider>().dio;

  // ── lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _previewType = FileTypeHelper.getPreviewType(widget.node.name);
    // unsupported: download API text text prohibited (L006 ST-L6-01 #3)
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

  // ── file text ───────────────────────────────────────────────────────────────

  /// GET /storages/download → _fileBytes text.
  /// error text translated text branch (P007 §2 text):
  ///   404 → "filetext text text translated text"
  ///   403 → "text permissiontext translated text"
  ///   translated text → "filetext translated text text translated text"
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
        // text text: UTF-8 translated text → text/text state initialize (L006 §4, P007 §4)
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
          'FilePreviewScreen', 'file text complete: ${widget.node.name}');
    } on DioException catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      final statusCode = e.response?.statusCode;
      final message = statusCode == 404
          ? t.previewFileNotFound
          : statusCode == 403
              ? t.previewAccessDenied
              : t.previewLoadFailed;
      AppLogger.error(
          'FilePreviewScreen', 'file text failed: $statusCode ${e.message}');
      setState(() {
        _isLoading = false;
        _error = message;
      });
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      AppLogger.error('FilePreviewScreen', 'file text failed(text): $e');
      setState(() {
        _isLoading = false;
        _error = t.previewLoadFailed;
      });
    }
  }

  // ── download ───────────────────────────────────────────────────────────────

  /// AppBar download text translated text.
  /// text translated text _fileBytestext translated text translated text, translated text API translated text (unsupported text text).
  Future<void> _handleDownload() async {
    final t = AppLocalizations.of(context);
    // fileforge.ui.0002 ("고스트 다운로드"): in-flight indicator so the
    // download is never a silent no-feedback wait.
    final progress = DownloadProgressOverlay.show(
      context,
      label: t.fileDownloading,
      percentLabel: t.fileDownloadingPercent,
    );
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
          onReceiveProgress: progress.onProgress,
        );
        final data = response.data;
        if (data == null || data.isEmpty) {
          if (mounted) AppToast.error(context, t.fileDownloadFailed);
          return;
        }
        bytes = data;
        final cdHeader = response.headers.value('content-disposition');
        filename =
            DownloadSaveService.extractFilename(cdHeader) ?? widget.node.name;
      }

      await DownloadSaveService.saveBytes(bytes: bytes, filename: filename);
      AppLogger.info('FilePreviewScreen', 'download complete: $filename');
      if (mounted) AppToast.success(context, t.fileDownloadComplete);
    } on DioException catch (e) {
      AppLogger.error(
          'FilePreviewScreen', 'download failed: ${e.response?.statusCode}');
      if (mounted) AppToast.error(context, t.fileDownloadFailed);
    } finally {
      progress.hide();
    }
  }

  // ── translated text text ────────────────────────────────────────────────────────────

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
    // cancel: text text, change text text text text (L006 ST-L6-02 #2)
    setState(() {
      _editedContent = _textContent;
      _textController.text = _textContent ?? '';
      _isEditMode = false;
    });
  }

  /// PUT /storages/update_file_content — translated text save (P007 §5)
  /// success: text text + success toast + _fileSizeChanged = true
  /// failed: error toast + text text keep (update content preserved)
  Future<void> _saveFile() async {
    if (_editedContent == null) return;
    final t = AppLocalizations.of(context);
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
      AppLogger.info('FilePreviewScreen', 'translated text save complete: ${widget.node.name}');
      AppToast.success(context, t.commonSaved);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final statusCode = e.response?.statusCode;
      final message = statusCode == 404
          ? t.previewFileNotFound
          : statusCode == 403
              ? t.previewSaveNoPermission
              : t.previewSaveFailed;
      AppLogger.error('FilePreviewScreen', 'translated text save failed: $statusCode');
      AppToast.error(context, message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppLogger.error('FilePreviewScreen', 'translated text save failed(text): $e');
      AppToast.error(context, t.previewSaveFailed);
    }
  }

  /// textsave changetext text translated text — P007 §4, L006 §5
  /// choices: save / save text text / cancel
  Future<void> _showUnsavedChangesDialog() async {
    final t = AppLocalizations.of(context);
    final result = await showDialog<_UnsavedAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Text(t.previewUnsavedChanges),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsavedAction.cancel),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsavedAction.discard),
            child: Text(t.previewDontSave),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_UnsavedAction.save),
            child: Text(t.commonSave),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (result) {
      case _UnsavedAction.save:
        await _saveFile();
        if (!mounted) return;
        // save success text _isEditMode==false → pop(true), failed text text keep
        if (!_isEditMode) Navigator.of(context).pop(true);
      case _UnsavedAction.discard:
        // save text text: text save text(_fileSizeChanged) keeptext text
        Navigator.of(context).pop(_fileSizeChanged);
      case _UnsavedAction.cancel:
      case null:
        break; // text screen keep
    }
  }

  // ── translated text ───────────────────────────────────────────────────────────────

  /// translated text branch — L006 §5 ST-L6-05 text text
  void _onBack() {
    // saving text: pop text
    if (_isSaving) return;
    if (_isEditMode) {
      if (_editedContent != _textContent) {
        // change text: 3selection translated text
        _showUnsavedChangesDialog();
        return;
      }
      // change None: text text text text text pop
      setState(() => _isEditMode = false);
    }
    Navigator.of(context).pop(_fileSizeChanged);
  }

  // ── AppBar text text ────────────────────────────────────────────────────────

  /// state/previewTypetext text AppBar actionstext returntext (D006 §4, L006 ST-L6-02).
  List<Widget> _buildAppBarActions() {
    final t = AppLocalizations.of(context);
    // loading translated text error statetranslated text text textdisplay (L006 ST-L6-01 #4)
    if (_isLoading || _error != null) return const [];

    if (_previewType == PreviewType.text) {
      if (_isEditMode) {
        // text text: [save] [cancel] — saving text translated text
        return [
          TextButton(
            onPressed: _isSaving ? null : _saveFile,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t.commonSave),
          ),
          TextButton(
            onPressed: _isSaving ? null : _cancelEdit,
            child: Text(t.cancel),
          ),
        ];
      }
      // text text: [text] [download]
      return [
        IconButton(
          icon: const Icon(Icons.edit_rounded),
          tooltip: t.commonEdit,
          onPressed: _enterEditMode,
        ),
        IconButton(
          icon: const Icon(Icons.download_rounded),
          tooltip: t.commonDownload,
          onPressed: _handleDownload,
        ),
      ];
    }

    // image / unsupported / pdf(placeholder) / video(placeholder) / audio(placeholder)
    return [
      IconButton(
        icon: const Icon(Icons.download_rounded),
        tooltip: t.commonDownload,
        onPressed: _handleDownload,
      ),
    ];
  }

  // ── build ──────────────────────────────────────────────────────────────────

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

  /// error text — PDF/video translated text ErrorRetry + download text, translated text ErrorRetrytext.
  Widget _buildErrorView() {
    final t = AppLocalizations.of(context);
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
                label: Text(t.commonDownload),
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

  /// previewTypetext branch — image/text/unsupported/pdf text, video/audio T034~T035 text.
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

  // ── translated text text (P007 §3, D006 FP05) ────────────────────────────────────────

  /// `InteractiveViewer` + `Image.memory` — text text/text text.
  /// translated text failed text post-frame callbacktext `_error` text → ErrorRetry text.
  Widget _buildImagePreview() {
    final t = AppLocalizations.of(context);
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: Image.memory(
          _fileBytes!,
          errorBuilder: (context, error, stackTrace) {
            // Image.memorytext errorBuildertext build text translated text,
            // setStatetext post-frame callbacktext exampletranslated text.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _error = t.previewImageFailed);
              }
            });
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  // ── translated text text/text (P007 §4, D006 FP06~FP10) ──────────────────────────────

  /// text text: `SingleChildScrollView + SelectableText` translated text.
  /// text text: `TextField(maxLines: null)` — `_textController` translated text.
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

  // ── PDF text (T033, P007 §6, §12, L006 §3 ST-L6-05) ──────────────────────────

  /// bytestext PdfControllerPinchtext text.
  /// kIsWeb: PdfDocument.openData(bytes) text (dart:io / getTemporaryDirectory text).
  /// text: text filetext save text PdfDocument.openFile() text.
  /// failed text _error = "PDFtext displaytext text translated text" text text.
  Future<void> _initPdfController(Uint8List bytes) async {
    final t = AppLocalizations.of(context);
    try {
      if (kIsWeb) {
        // text: dart:io File / getTemporaryDirectory() translated text → openDatatext text (T035)
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
      AppLogger.error('FilePreviewScreen', 'PDF initialize failed: $e');
      if (mounted) {
        setState(() => _error = t.previewPdfFailed);
      }
    }
  }

  /// PdfControllerPinchtext translated text PdfViewPinch translated text.
  /// text translated text loading translated text, initialize failed text error+download text.
  Widget _buildPdfPreview() {
    final t = AppLocalizations.of(context);
    if (_pdfController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PdfViewPinch(
      controller: _pdfController!,
      onDocumentError: (error) {
        AppLogger.error('FilePreviewScreen', 'PDF translated text Error: $error');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _error = t.previewPdfFailed);
          }
        });
      },
    );
  }

  // ── translated text translated text (T040, P007 §7, §12, L006 §3 ST-L6-06) ───────────────────

  /// bytes → VideoPlayerController initialize.
  /// text(kIsWeb): bytes → Blob URL → VideoPlayerController.networkUrl() path (NR019).
  /// text: text file save text VideoPlayerController.file() path.
  /// failed text _error = "translated text translated text text translated text"text text.
  Future<void> _initVideoController(Uint8List bytes) async {
    final t = AppLocalizations.of(context);
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
          'translated text text initialize text: name=${widget.node.name}, '
              'bytes=${bytes.length}, copiedBytes=${uint8.length}, '
              'ext=$ext, mime=$mimeType',
        );
        blobUrl = previewCreateBlobUrl(uint8, mimeType);
        final parsedUri = Uri.parse(blobUrl);
        final roundTripUrl = parsedUri.toString();
        AppLogger.info(
          'FilePreviewScreen',
          'translated text text Blob URL create: scheme=${parsedUri.scheme}, '
              'roundTripEqual=${roundTripUrl == blobUrl}, url=$blobUrl',
        );
        final videoController = VideoPlayerController.networkUrl(parsedUri);
        AppLogger.info(
          'FilePreviewScreen',
          'translated text text controller.initialize() text',
        );
        await videoController.initialize();
        AppLogger.info(
          'FilePreviewScreen',
          'translated text text initialize success: '
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
          'translated text initialize failed(text): type=${e.runtimeType}, '
              'error=$e, blobUrl=$blobUrl',
        );
        AppLogger.error(
          'FilePreviewScreen',
          'translated text initialize failed(text) stack: $st',
        );
        if (mounted) setState(() => _error = t.previewVideoFailed);
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
      AppLogger.error('FilePreviewScreen', 'translated text initialize failed: $e');
      if (mounted) {
        setState(() => _error = t.previewVideoFailed);
      }
    }
  }

  /// ChewieControllertext translated text Chewie text translated text.
  /// text translated text loading translated text.
  Widget _buildVideoPreview() {
    if (_chewieController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Chewie(controller: _chewieController!);
  }

  // ── translated text translated text (T041, P007 §8, §10, §12, L006 §3 ST-L6-06) ───────────────

  /// bytes → text file save → AudioPlayer initialize → text.
  /// failed text _error = "translated text translated text text translated text"text text.
  Future<void> _initAudioController(Uint8List bytes) async {
    final t = AppLocalizations.of(context);
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
        if (mounted) setState(() => _error = t.previewAudioFailed);
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
      if (mounted) setState(() => _error = t.previewAudioFailed);
    }
  }

  /// AudioPlayertext translated text translated text translated text UI translated text.
  /// text translated text loading translated text.
  Widget _buildAudioPreview() {
    final t = AppLocalizations.of(context);
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
                  tooltip: t.previewRewind10,
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
                  tooltip: _audioIsPlaying ? t.previewPause : t.previewPlay,
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
                  tooltip: t.previewForward10,
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

  // ── translated text text (D006 §4-7, FP14) ──────────────────────────────────────────

  /// file translated text + text message + download text.
  /// `_loadFile()` translated text state (L006 ST-L6-01 #3).
  Widget _buildUnsupportedPreview() {
    final t = AppLocalizations.of(context);
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
              t.previewUnsupported,
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
              label: Text(t.commonDownload),
            ),
          ],
        ),
      ),
    );
  }
}
