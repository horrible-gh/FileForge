import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/storage_provider.dart';
import '../../providers/file_provider.dart';
import '../../providers/selection_provider.dart';
import '../../providers/upload_provider.dart';
import '../../models/node.dart';
import '../../services/logger.dart';
import '../../services/download_save_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/breadcrumb_nav.dart';
import '../../widgets/file_list_item.dart';
import '../../widgets/file_grid_item.dart';
import '../../widgets/file_action_sheet.dart';
import '../../widgets/file_operation_dialogs.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/note_card_grid.dart';
import '../../widgets/upload_panel.dart';
import '../../widgets/share_link_bottom_sheet.dart';
import '../../utils/file_type_helper.dart';
import '../preview/file_preview_screen.dart';

// 웹 전용 import — kIsWeb 가드 하에서만 사용
import 'package:flutter_dropzone/flutter_dropzone.dart'
    if (dart.library.io) '../../utils/dropzone_stub.dart';
import '../../utils/web_directory_drop.dart'
    if (dart.library.io) '../../utils/web_directory_drop_stub.dart';

/// 파일/폴더 목록 화면 — Phase 3+4 메인 콘텐츠
class FileListScreen extends StatefulWidget {
  final String? storageUuid;
  final String? nodeUuid;

  const FileListScreen({
    super.key,
    this.storageUuid,
    this.nodeUuid,
  });

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  // 웹 드롭존 컨트롤러 (kIsWeb + file 타입일 때만 사용)
  DropzoneViewController? _dropController;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(FileListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storageUuid != widget.storageUuid ||
        oldWidget.nodeUuid != widget.nodeUuid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    AppLogger.debug('FileListScreen', '_load storageUuid=${widget.storageUuid} nodeUuid=${widget.nodeUuid}');
    final authProvider = context.read<AuthProvider>();
    final storageProvider = context.read<StorageProvider>();
    final fileProvider = context.read<FileProvider>();

    final userUuid = authProvider.user?.userUuid ?? '';

    if (storageProvider.storages.isEmpty && !storageProvider.isLoading) {
      await storageProvider.loadStorages(userUuid);
    }

    final effectiveStorageUuid =
        widget.storageUuid ?? storageProvider.currentStorage?.storageUuid;

    if (effectiveStorageUuid == null || effectiveStorageUuid.isEmpty) return;

    if (widget.storageUuid != null &&
        storageProvider.currentStorage?.storageUuid != widget.storageUuid) {
      final target = storageProvider.storages
          .where((s) => s.storageUuid == widget.storageUuid)
          .firstOrNull;
      if (target != null) storageProvider.selectStorage(target);
    }

    await fileProvider.loadChildren(
      effectiveStorageUuid,
      userUuid,
      nodeUuid: widget.nodeUuid,
    );

    if (mounted) {
      fileProvider.loadFolderTree(effectiveStorageUuid, userUuid);
    }
  }

  Future<void> _refresh() async {
    final authProvider = context.read<AuthProvider>();
    final storageProvider = context.read<StorageProvider>();
    final fileProvider = context.read<FileProvider>();
    final userUuid = authProvider.user?.userUuid ?? '';
    final effectiveStorageUuid =
        widget.storageUuid ?? storageProvider.currentStorage?.storageUuid;
    if (effectiveStorageUuid == null) return;
    await fileProvider.loadChildren(
      effectiveStorageUuid,
      userUuid,
      nodeUuid: widget.nodeUuid,
      search: fileProvider.isSearchMode ? fileProvider.searchQuery : null,
    );
  }

  void _navigateToFolder(BuildContext context, String? nodeUuid) {
    final storageProvider = context.read<StorageProvider>();
    final storageUuid =
        widget.storageUuid ?? storageProvider.currentStorage?.storageUuid;
    if (storageUuid == null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Storage not found.')),
      );
      return;
    }
    if (nodeUuid == null) {
      context.go('/$storageUuid');
    } else {
      context.go('/$storageUuid/$nodeUuid');
    }
  }

  // ── 파일 조작 핸들러 ──────────────────────────────────────────────────────

  String get _storageType =>
      context.read<StorageProvider>().currentStorage?.storageType ?? 'file';

  String get _storageUuid =>
      widget.storageUuid ??
      context.read<StorageProvider>().currentStorage?.storageUuid ??
      '';

  String get _userUuid =>
      context.read<AuthProvider>().user?.userUuid ?? '';

  String get _groupUuid => '';

  StorageService get _storageService =>
      StorageService(context.read<AuthProvider>().dio);

  /// 케밥메뉴 오픈
  void _onKebabTap(Node node) async {
    final action = await FileActionSheet.show(
      context,
      node: node,
      storageType: _storageType,
    );
    if (action == null || !mounted) return;

    switch (action) {
      case FileAction.download:
        await _handleDownload(node);
      case FileAction.rename:
        await _handleRename(node);
      case FileAction.delete:
        await _handleDelete(node);
      case FileAction.share:
        await _handleShare(node);
      case FileAction.preview:
        await _handlePreview(node);
    }
  }

  /// 파일 탭 → previewType 분기: unsupported이면 다운로드, 그 외는 미리보기 (T038)
  /// 폴더인 경우 폴더 진입 유지 (방어 가드)
  void _onItemTap(Node node) async {
    if (node.isFolder) {
      _navigateToFolder(context, node.nodeUuid);
      return;
    }
    final previewType = FileTypeHelper.getPreviewType(node.name);
    if (previewType == PreviewType.unsupported) {
      await _handleDownload(node);
    } else {
      await _handlePreview(node);
    }
  }

  /// 미리보기 화면 진입 — Navigator.push 방식 (D006 §12)
  /// pop 결과 bool 수신 → true이면 FileProvider.loadChildren() 갱신
  Future<void> _handlePreview(Node node, {bool autoEdit = false}) async {
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FilePreviewScreen(
          node: node,
          storageUuid: _storageUuid,
          userUuid: _userUuid,
          groupUuid: _groupUuid,
          autoEdit: autoEdit,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      context.read<FileProvider>().loadChildren(
            _storageUuid,
            _userUuid,
            nodeUuid: widget.nodeUuid,
          );
    }
  }

  /// 공유 링크 생성 BottomSheet 오픈
  Future<void> _handleShare(Node node) async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShareLinkBottomSheet(node: node),
    );
  }

  /// 다운로드 — 단일 파일/폴더
  Future<void> _handleDownload(Node node) async {
    try {
      final response = await _storageService.download(
        storageUuid: _storageUuid,
        userUuid: _userUuid,
        groupUuid: _groupUuid,
        nodeUuid: node.nodeUuid!,
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) AppToast.error(context, 'Download failed');
        return;
      }

      final cdHeader = response.headers.value('content-disposition');
      final filename = DownloadSaveService.extractFilename(cdHeader)
          ?? (node.isFolder ? '${node.name}.zip' : node.name);
      await DownloadSaveService.saveBytes(bytes: bytes, filename: filename);

      if (mounted) AppToast.success(context, 'Download complete');
      AppLogger.info('FileListScreen', 'Download complete: $filename');
    } on DioException catch (e) {
      AppLogger.error('FileListScreen', 'Download failed: ${e.response?.statusCode}');
      if (mounted) AppToast.error(context, 'Download failed');
    }
  }

  /// 이름 변경
  Future<void> _handleRename(Node node) async {
    final newName = await FileOperationDialogs.showRenameDialog(
      context,
      currentName: node.name,
    );
    if (newName == null || newName == node.name || !mounted) return;

    try {
      await _storageService.renameNode(
        storageUuid: _storageUuid,
        userUuid: _userUuid,
        groupUuid: _groupUuid,
        nodeUuid: node.nodeUuid!,
        newName: newName,
      );
      if (mounted) AppToast.success(context, 'Renamed');
      _refreshAfterOperation(node.isFolder);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        if (mounted) AppToast.error(context, 'A file with this name already exists');
        // 다이얼로그 재호출
        if (mounted) _handleRename(node);
      } else {
        if (mounted) AppToast.error(context, 'Failed to rename');
      }
    }
  }

  /// 삭제
  Future<void> _handleDelete(Node node) async {
    final confirmed = await FileOperationDialogs.showDeleteConfirmDialog(
      context,
      name: node.name,
    );
    if (!confirmed || !mounted) return;

    try {
      await _storageService.deleteNode(
        storageUuid: _storageUuid,
        userUuid: _userUuid,
        groupUuid: _groupUuid,
        nodeUuid: node.nodeUuid!,
      );
      if (mounted) AppToast.success(context, 'Deleted');
      _refreshAfterOperation(node.isFolder);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        if (mounted) AppToast.error(context, 'Item not found');
        _refreshAfterOperation(true);
      } else {
        if (mounted) AppToast.error(context, 'Failed to delete');
      }
    }
  }

  /// note 파일 탭 → 미리보기 진입 (T045)
  Future<void> _onFileTap(Node node) async {
    await _handlePreview(node);
  }

  /// note 생성 다이얼로그 → 빈 .md 업로드 → FilePreviewScreen 자동 진입 (T046)
  Future<void> _handleNoteCreate() async {
    final nameController = TextEditingController(text: 'New Note');
    bool isUploading = false;

    /// 파일명으로 사용할 수 없는 문자 포함 여부 검사 (T046 §3)
    bool hasInvalidChars(String value) {
      const invalid = r'/\:*?"<>|';
      return value.runes.any((c) => invalid.codeUnits.contains(c));
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            final trimmed = nameController.text.trim();
            final isEmpty = trimmed.isEmpty;
            final isInvalid = !isEmpty && hasInvalidChars(trimmed);
            final canConfirm = !isEmpty && !isInvalid && !isUploading;

            Future<void> onConfirm() async {
              if (!canConfirm) return;

              final input = trimmed;
              final finalName =
                  (input.endsWith('.md') || input.endsWith('.txt'))
                      ? input
                      : '$input.md';

              setDialogState(() => isUploading = true);

              try {
                final response = await _storageService.upload(
                  storageUuid: _storageUuid,
                  parentUuid: widget.nodeUuid ?? '',
                  userUuid: _userUuid,
                  groupUuid: _groupUuid,
                  filename: finalName,
                  fileBytes: [],
                );

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                if (!mounted) return;

                context.read<FileProvider>().loadChildren(
                      _storageUuid,
                      _userUuid,
                      nodeUuid: widget.nodeUuid,
                    );

                final newNode = Node(
                  nodeUuid: response['node_uuid'] as String?,
                  name: finalName,
                  type: 'file',
                );
                await _handlePreview(newNode, autoEdit: true);
              } on DioException catch (e) {
                if (!dialogContext.mounted) return;
                setDialogState(() => isUploading = false);
                if (e.response?.statusCode == 409) {
                  if (mounted) {
                    AppToast.error(context, 'A note with this name already exists');
                  }
                  // 409: 다이얼로그 유지 — pop하지 않음
                } else {
                  if (mounted) {
                    AppToast.error(context, 'Failed to create note');
                  }
                  Navigator.pop(dialogContext);
                }
              }
            }

            return AlertDialog(
              title: const Text('New Note'),
              content: TextField(
                controller: nameController,
                autofocus: true,
                enabled: !isUploading,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  hintText: 'Note name',
                  errorText: isInvalid
                      ? r'File names cannot contain these characters: (/ \ : * ? " < > |)'
                      : null,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: canConfirm ? onConfirm : null,
                  child: isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
  }

  /// note rename — 다이얼로그에서 확장자 숨김, 서버 전송 직전 원본 확장자 재결합 (T047)
  Future<void> _handleNoteRename(Node node) async {
    if (node.isFolder) {
      // 폴더는 기존 rename 경로 그대로 위임
      await _handleRename(node);
      return;
    }

    // 원본 확장자 추출 — 확장자 없는 파일은 빈 문자열
    final dotIndex = node.name.lastIndexOf('.');
    final ext = dotIndex > 0 ? node.name.substring(dotIndex) : '';
    final titleDefault = dotIndex > 0 ? node.name.substring(0, dotIndex) : node.name;

    final nameController = TextEditingController(text: titleDefault);

    /// 파일명으로 사용할 수 없는 문자 포함 여부 검사 (T047 §3)
    bool hasInvalidChars(String value) {
      const invalid = r'/\:*?"<>|';
      return value.runes.any((c) => invalid.codeUnits.contains(c));
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            final trimmed = nameController.text.trim();
            final isEmpty = trimmed.isEmpty;
            final isInvalid = !isEmpty && hasInvalidChars(trimmed);
            final canConfirm = !isEmpty && !isInvalid;

            Future<void> onConfirm() async {
              if (!canConfirm) return;
              // 중복 확장자 방지: 입력값이 이미 원본 확장자로 끝나면 재결합 생략 (T047 §2)
              final newName = (ext.isNotEmpty && trimmed.endsWith(ext))
                  ? trimmed
                  : '$trimmed$ext';
              if (newName == node.name) {
                Navigator.pop(dialogContext);
                return;
              }

              try {
                await _storageService.renameNode(
                  storageUuid: _storageUuid,
                  userUuid: _userUuid,
                  groupUuid: _groupUuid,
                  nodeUuid: node.nodeUuid!,
                  newName: newName,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (mounted) AppToast.success(context, 'Renamed');
                _refreshAfterOperation(false);
              } on DioException catch (e) {
                if (!dialogContext.mounted) return;
                if (e.response?.statusCode == 409) {
                  if (mounted) AppToast.error(context, 'A note with this name already exists');
                  // 409: 다이얼로그 유지
                } else {
                  if (mounted) AppToast.error(context, 'Failed to rename');
                  Navigator.pop(dialogContext);
                }
              }
            }

            return AlertDialog(
              title: const Text('Rename'),
              content: TextField(
                controller: nameController,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  hintText: 'Note name',
                  errorText: isInvalid
                      ? r'File names cannot contain these characters: (/ \ : * ? " < > |)'
                      : null,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: canConfirm ? onConfirm : null,
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
  }

  // ── 웹 드래그앤드롭 (kIsWeb + file 타입 전용) ────────────────────────────

  /// DropzoneView에서 파일 목록 드롭 시 처리 (T056)
  /// flutter_dropzone onDropMultiple 콜백으로 파일 목록을 받아
  /// bytes + relativePath(파일명)를 UploadProvider.addFiles()로 전달한다.
  void _handleWebDrop(List<dynamic>? files) {
    debugPrint('[DnD] _handleWebDrop called, files=${files?.length}');
    if (!kIsWeb) return;
    if (_dropController == null || files == null || files.isEmpty) return;
    // 비동기 처리를 별도 메서드로 분리하여 ValueChanged 시그니처 준수
    _processWebDropFiles(files);
  }

  Future<void> _processWebDropFiles(List<dynamic> files) async {
    setState(() => _isDragging = false);

    final List<MapEntry<String, List<int>>> fileEntries = [];
    final Map<String, String> relativePathMap = {};

    for (final file in files) {
      if (file == null) continue; // 디렉터리 드롭 시 flutter_dropzone이 전달하는 null 방어
      try {
        final name = await _dropController!.getFilename(file);
        final bytes = await _dropController!.getFileData(file);
        fileEntries.add(MapEntry(name, bytes));
        relativePathMap[name] = name;
      } catch (e) {
        AppLogger.warn('FileListScreen', 'Drop file read failed: $e');
      }
    }

    if (fileEntries.isEmpty || !mounted) return;

    final uploadProvider = context.read<UploadProvider>();
    final fileProvider = context.read<FileProvider>();
    final storageUuid = _storageUuid;
    final userUuid = _userUuid;

    uploadProvider.onUploadComplete = () {
      fileProvider.loadChildren(
        storageUuid,
        userUuid,
        nodeUuid: fileProvider.currentNode.nodeUuid ?? widget.nodeUuid,
      );
    };

    uploadProvider.addFiles(
          files: fileEntries,
          storageUuid: storageUuid,
          parentUuid: widget.nodeUuid ?? '',
          userUuid: userUuid,
          groupUuid: _groupUuid,
          relativePathMap: relativePathMap,
        );
  }

  /// 디렉터리 드롭 재귀 순회 완료 후 호출 (T057)
  /// [registerDirectoryCaptureDrop]의 onFilesReady 콜백.
  void _handleDirectoryDrop(List<WebDropFileInfo> files) {
    if (!mounted) return;
    setState(() => _isDragging = false);
    if (files.isEmpty) return;

    final fileEntries = files
        .map((f) => MapEntry<String, List<int>>(f.name, f.bytes))
        .toList();
    final relativePathMap = {for (final f in files) f.name: f.relativePath};

    final uploadProvider = context.read<UploadProvider>();
    final fileProvider = context.read<FileProvider>();
    final storageUuid = _storageUuid;
    final userUuid = _userUuid;

    uploadProvider.onUploadComplete = () {
      fileProvider.loadChildren(
        storageUuid,
        userUuid,
        nodeUuid: fileProvider.currentNode.nodeUuid ?? widget.nodeUuid,
      );
    };

    uploadProvider.addFiles(
      files: fileEntries,
      storageUuid: storageUuid,
      parentUuid: widget.nodeUuid ?? '',
      userUuid: userUuid,
      groupUuid: _groupUuid,
      relativePathMap: relativePathMap,
    );
  }

  /// 조작 후 목록/트리 새로고침 (P004 §12)
  void _refreshAfterOperation(bool refreshTree) {
    final fileProvider = context.read<FileProvider>();
    fileProvider.loadChildren(
      _storageUuid,
      _userUuid,
      nodeUuid: widget.nodeUuid,
    );
    if (refreshTree) {
      fileProvider.loadFolderTree(_storageUuid, _userUuid);
    }
  }

  // ── 빌드 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fileProvider = context.watch<FileProvider>();
    final storageProvider = context.watch<StorageProvider>();
    final selectionProvider = context.watch<SelectionProvider>();

    if (storageProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (storageProvider.storages.isEmpty) {
      return const EmptyState(
        message: 'No storages',
        icon: Icons.storage_rounded,
      );
    }

    if (fileProvider.error != null && !fileProvider.isLoading) {
      return ErrorRetry(
        message: 'Failed to load list',
        onRetry: _refresh,
      );
    }

    final bool isFileStorage =
        storageProvider.currentStorage?.storageType == 'file';
    final bool useDropzone = kIsWeb && isFileStorage;

    // 파일 목록 콘텐츠 영역
    final Widget contentArea = Expanded(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: BreadcrumbNav(
                breadcrumbs: fileProvider.breadcrumbs,
                storageLabel: storageProvider.storages
                        .where((s) => s.storageUuid == widget.storageUuid)
                        .firstOrNull
                        ?.storageName ??
                    storageProvider.currentStorage?.storageName ??
                    '',
                onBreadcrumbTapped: (nodeUuid) =>
                    _navigateToFolder(context, nodeUuid),
              ),
            ),

            if (fileProvider.isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (storageProvider.currentStorage?.storageType == 'note')
              SliverFillRemaining(
                child: NoteCardGrid(
                  children: fileProvider.children,
                  onNoteTap: _onFileTap,
                  onFolderTap: (node) =>
                      _navigateToFolder(context, node.nodeUuid),
                  onAddNote: _handleNoteCreate,
                  onRename: _handleNoteRename,
                  onDelete: _handleDelete,
                ),
              )
            else if (fileProvider.children.isEmpty)
              SliverFillRemaining(
                child: EmptyState(
                  message: fileProvider.isSearchMode
                      ? 'No search results'
                      : 'No files',
                ),
              )
            else
              if (storageProvider.currentStorage?.storageType == 'file' &&
                  fileProvider.fileViewMode == FileViewMode.grid)
                SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.95,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final node = fileProvider.children[index];
                      return FileGridItem(
                        node: node,
                        isSelectionMode: selectionProvider.isSelectionMode,
                        isSelected: node.nodeUuid != null &&
                            selectionProvider.isSelected(node.nodeUuid!),
                        onFolderTap: node.isFolder
                            ? () =>
                                _navigateToFolder(context, node.nodeUuid)
                            : null,
                        onFileTap: node.isFile && node.nodeUuid != null
                            ? () => _onItemTap(node)
                            : null,
                        onKebabTap: node.nodeUuid != null
                            ? () => _onKebabTap(node)
                            : null,
                        onLongPress: node.nodeUuid != null
                            ? () => selectionProvider
                                .enterSelectionMode(node.nodeUuid!)
                            : null,
                        onSelectionTap: node.nodeUuid != null
                            ? () => selectionProvider.toggle(node.nodeUuid!)
                            : null,
                      );
                    },
                    childCount: fileProvider.children.length,
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final node = fileProvider.children[index];
                      // 파일 탭 → ListTile.onTap 직접 연결 (T039, NR018 수정)
                      return FileListItem(
                        node: node,
                        isSelectionMode: selectionProvider.isSelectionMode,
                        isSelected: node.nodeUuid != null &&
                            selectionProvider.isSelected(node.nodeUuid!),
                        onFolderTap: node.isFolder
                            ? () => _navigateToFolder(context, node.nodeUuid)
                            : null,
                        onFileTap: node.isFile && node.nodeUuid != null
                            ? () => _onItemTap(node)
                            : null,
                        onKebabTap: node.nodeUuid != null
                            ? () => _onKebabTap(node)
                            : null,
                        onLongPress: node.nodeUuid != null
                            ? () => selectionProvider
                                .enterSelectionMode(node.nodeUuid!)
                            : null,
                        onSelectionTap: node.nodeUuid != null
                            ? () =>
                                selectionProvider.toggle(node.nodeUuid!)
                            : null,
                      );
                    },
                    childCount: fileProvider.children.length,
                  ),
                ),
          ],
        ),
      ),
    );

    // kIsWeb + file 타입일 때: DropzoneView + 드래그 오버레이를 Stack으로 부착
    if (useDropzone) {
      return Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    contentArea,
                  ],
                ),
                // DropzoneView — Positioned.fill로 전체 영역 점유, 드롭 이벤트 수신 (T063)
                // IgnorePointer: Flutter hit-test를 통과시켜 하단 contentArea 클릭/스크롤 유지.
                // 브라우저 네이티브 drag 이벤트는 DOM 레이어에서 처리되므로 onDropFiles는 계속 작동.
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_isDragging,
                    child: DropzoneView(
                      operation: DragOperation.copy,
                      cursor: CursorType.Default,
                        onCreated: (ctrl) {
                          _dropController = ctrl;
                          if (kIsWeb) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              registerDirectoryCaptureDrop(
                                viewId: ctrl.viewId,
                                onFilesReady: _handleDirectoryDrop,
                              );
                            });
                          }
                        },
                      onHover: () {
                        if (!_isDragging) setState(() => _isDragging = true);
                      },
                      onLeave: () {
                        if (_isDragging) setState(() => _isDragging = false);
                      },
                      onDropFiles: _handleWebDrop,
                    ),
                  ),
                ),
                // 드래그 오버 시 반투명 오버레이
                if (_isDragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.15),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.upload_file_rounded,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Drop files here',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 업로드 진행률 패널
          const UploadPanel(),
        ],
      );
    }

    // 비웹 또는 note 타입: 기존 레이아웃 그대로
    return Column(
      children: [
        contentArea,
        // 업로드 진행률 패널
        const UploadPanel(),
      ],
    );
  }
}
