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

// text text import — kIsWeb guard translated text text
import 'package:flutter_dropzone/flutter_dropzone.dart'
    if (dart.library.io) '../../utils/dropzone_stub.dart';
import '../../utils/web_directory_drop.dart'
    if (dart.library.io) '../../utils/web_directory_drop_stub.dart';

/// file/folder text screen — Phase 3+4 text translated text
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
  // text translated text translated text (kIsWeb + file translated text text text)
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

  // ── file text translated text ──────────────────────────────────────────────────────

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

  /// translated text text
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

  /// file text → previewType branch: unsupportedtext download, text text translated text (T038)
  /// foldertext text folder text keep (text guard)
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

  /// translated text screen text — Navigator.push text (D006 §12)
  /// pop result bool text → truetext FileProvider.loadChildren() refresh
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

  /// Create a shared link BottomSheet text
  Future<void> _handleShare(Node node) async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShareLinkBottomSheet(node: node),
    );
  }

  /// download — text file/folder
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

  /// name change
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
        // translated text translated text
        if (mounted) _handleRename(node);
      } else {
        if (mounted) AppToast.error(context, 'Failed to rename');
      }
    }
  }

  /// delete
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

  /// note file text → translated text text (T045)
  Future<void> _onFileTap(Node node) async {
    await _handlePreview(node);
  }

  /// note create translated text → empty .md upload → FilePreviewScreen text text (T046)
  Future<void> _handleNoteCreate() async {
    final nameController = TextEditingController(text: 'New Note');
    bool isUploading = false;

    /// filetranslated text translated text text text text text text text (T046 §3)
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
                  // 409: translated text keep — poptext text
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

  /// note rename — translated text translated text text, server text text text translated text translated text (T047)
  Future<void> _handleNoteRename(Node node) async {
    if (node.isFolder) {
      // foldertext text rename path as-is text
      await _handleRename(node);
      return;
    }

    // text translated text text — translated text text filetext empty string
    final dotIndex = node.name.lastIndexOf('.');
    final ext = dotIndex > 0 ? node.name.substring(dotIndex) : '';
    final titleDefault = dotIndex > 0 ? node.name.substring(0, dotIndex) : node.name;

    final nameController = TextEditingController(text: titleDefault);

    /// filetranslated text translated text text text text text text text (T047 §3)
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
              // text translated text text: translated text text text translated text translated text translated text text (T047 §2)
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
                  // 409: translated text keep
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

  // ── text translated text (kIsWeb + file text text) ────────────────────────────

  /// DropzoneViewtext file text text text text (T056)
  /// flutter_dropzone onDropMultiple translated text file translated text text
  /// bytes + relativePath(filetext)text UploadProvider.addFiles()text translated text.
  void _handleWebDrop(List<dynamic>? files) {
    debugPrint('[DnD] _handleWebDrop called, files=${files?.length}');
    if (!kIsWeb) return;
    if (_dropController == null || files == null || files.isEmpty) return;
    // translated text translated text text translated text minutestranslated text ValueChanged translated text text
    _processWebDropFiles(files);
  }

  Future<void> _processWebDropFiles(List<dynamic> files) async {
    setState(() => _isDragging = false);

    final List<MapEntry<String, List<int>>> fileEntries = [];
    final Map<String, String> relativePathMap = {};

    for (final file in files) {
      if (file == null) continue; // directory text text flutter_dropzonetext translated text null text
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

  /// directory text text text complete text text (T057)
  /// [registerDirectoryCaptureDrop]text onFilesReady text.
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

  /// text text text/text translated text (P004 §12)
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

  // ── build ──────────────────────────────────────────────────────────────────

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

    // file text translated text text
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
                      // file text → ListTile.onTap text text (T039, NR018 update)
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

    // kIsWeb + file translated text text: DropzoneView + translated text translated text Stacktext text
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
                // DropzoneView — Positioned.filltext text text text, text translated text text (T063)
                // IgnorePointer: Flutter hit-testtext translated text text contentArea text/translated text keep.
                // browser translated text drag translated text DOM translated text translated text onDropFilestext text text.
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
                // translated text text text translated text translated text
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
          // upload translated text text
          const UploadPanel(),
        ],
      );
    }

    // text text note text: text translated text as-is
    return Column(
      children: [
        contentArea,
        // upload translated text text
        const UploadPanel(),
      ],
    );
  }
}
