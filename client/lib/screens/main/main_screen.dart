import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/storage_provider.dart';
import '../../providers/file_provider.dart';
import '../../providers/selection_provider.dart';
import '../../providers/upload_provider.dart';
import '../../models/storage.dart';
import '../../models/node.dart';
import '../../services/logger.dart';
import '../../config/routes.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/storage_selector.dart';
import '../../widgets/folder_tree_view.dart';
import '../../widgets/file_operation_dialogs.dart';
import '../../widgets/server_settings_dialog.dart';
import '../../services/download_save_service.dart';
import '../../services/storage_service.dart';
import '../preview/file_preview_screen.dart';

/// authentication text translated text text Scaffold — Drawer + AppBar + Body(child)
/// GoRouter ShellRoutetext shell translated text text.
class MainScreen extends StatefulWidget {
  final Widget child;

  const MainScreen({super.key, required this.child});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onStorageSelected(Storage storage) {
    final authProvider = context.read<AuthProvider>();
    final storageProvider = context.read<StorageProvider>();
    final fileProvider = context.read<FileProvider>();
    storageProvider.selectStorage(storage);
    fileProvider.reset();
    Navigator.of(context).pop(); // Drawer text
    context.go('/${storage.storageUuid}');
    fileProvider.loadChildren(
      storage.storageUuid,
      authProvider.user?.userUuid ?? '',
    );
  }

  void _onFolderTapped(Node node) {
    final storageProvider = context.read<StorageProvider>();
    final storageUuid = storageProvider.currentStorage?.storageUuid;
    if (storageUuid == null) return;
    Navigator.of(context).pop(); // Drawer text
    if (node.nodeUuid != null) {
      context.go('/$storageUuid/${node.nodeUuid}');
    } else {
      context.go('/$storageUuid');
    }
  }

  void _onSearchSubmitted(String query, BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final storageProvider = context.read<StorageProvider>();
    final fileProvider = context.read<FileProvider>();
    final storageUuid = storageProvider.currentStorage?.storageUuid;
    final userUuid = authProvider.user?.userUuid ?? '';
    if (storageUuid == null) return;
    fileProvider.setSearchQuery(query, storageUuid, userUuid);
  }

  void _exitSearchMode(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final storageProvider = context.read<StorageProvider>();
    final fileProvider = context.read<FileProvider>();
    final storageUuid = storageProvider.currentStorage?.storageUuid;
    final userUuid = authProvider.user?.userUuid ?? '';
    _searchController.clear();
    if (storageUuid != null) {
      fileProvider.exitSearchMode(storageUuid, userUuid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileProvider = context.watch<FileProvider>();
    final authProvider = context.watch<AuthProvider>();
    final storageProvider = context.watch<StorageProvider>();
    final selectionProvider = context.watch<SelectionProvider>();

    final currentFolderName =
        fileProvider.currentNode.name == 'Root' &&
                !fileProvider.isSearchMode
            ? (storageProvider.currentStorage?.storageName ?? 'FileForge')
            : fileProvider.isSearchMode
                ? 'Search'
                : fileProvider.currentNode.name;

    final storageType = storageProvider.currentStorage?.storageType ?? 'file';

    final location = GoRouterState.of(context).matchedLocation;
    final isShareLinks = location == '/share-links';
    final isSettings = location == AppRoutes.settings;
    if (selectionProvider.isSelectionMode) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) selectionProvider.exitSelectionMode();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => selectionProvider.exitSelectionMode(),
            ),
            title: Text('${selectionProvider.selectedCount} selected'),
            actions: [
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Select all',
                onPressed: () {
                  final allUuids = fileProvider.children
                      .where((n) => n.nodeUuid != null)
                      .map((n) => n.nodeUuid!)
                      .toList();
                  selectionProvider.selectAll(allUuids);
                },
              ),
              if (storageType == 'file')
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  tooltip: 'Download',
                  onPressed: selectionProvider.hasSelection
                      ? () => _triggerBulkDownload(context)
                      : null,
                ),
              IconButton(
                icon: const Icon(Icons.delete_rounded),
                tooltip: 'Delete',
                onPressed: selectionProvider.hasSelection
                    ? () => _triggerBulkDelete(context)
                    : null,
              ),
            ],
          ),
          body: widget.child,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: isShareLinks
            ? const Text('Manage Share Links')
          : isSettings
            ? const Text('Security Settings')
            : fileProvider.isSearchMode
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (q) => _onSearchSubmitted(q, context),
                    textInputAction: TextInputAction.search,
                  )
                : Text(currentFolderName),
        actions: [
          if (!isShareLinks && !isSettings) ...[
            if (fileProvider.isSearchMode)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Exit search',
                onPressed: () => _exitSearchMode(context),
              )
            else ...[
              if (storageType != 'password')
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add',
                  onPressed: () => _showFabMenu(context, storageType),
                ),
              if (storageType == 'file')
                IconButton(
                  icon: Icon(
                    fileProvider.fileViewMode == FileViewMode.list
                        ? Icons.grid_view_rounded
                        : Icons.view_list_rounded,
                  ),
                  tooltip: fileProvider.fileViewMode == FileViewMode.list
                      ? 'Grid view'
                      : 'List view',
                  onPressed: () => fileProvider.toggleFileViewMode(),
                ),
              IconButton(
                icon: const Icon(Icons.checklist_rounded),
                tooltip: 'Selection mode',
                onPressed: () => selectionProvider.enterSelectionMode(),
              ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Search',
                onPressed: () {
                  fileProvider.enterSearchMode();
                },
              ),
            ],
          ],
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'vault') {
                context.push(AppRoutes.vault);
              } else if (value == 'share_links') {
                context.push('/share-links');
              } else if (value == 'server_settings') {
                showDialog(
                  context: context,
                  builder: (_) => const ServerSettingsDialog(),
                );
              } else if (value == 'settings') {
                context.push(AppRoutes.settings);
              } else if (value == 'logout') {
                await authProvider.logout();
                if (context.mounted) context.go(AppRoutes.login);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'vault', child: Text('SecureBolt Vault')),
              PopupMenuItem(value: 'share_links', child: Text('Manage Share Links')),
              PopupMenuItem(value: 'server_settings', child: Text('Server Settings')),
              PopupMenuItem(value: 'settings', child: Text('Security Settings')),
              PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
        ],
      ),
      drawer: _buildDrawer(context, authProvider, storageProvider, fileProvider),
      body: widget.child,
    );
  }

  void _showFabMenu(BuildContext context, String storageType) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // text text — note storagetext (T048)
            if (storageType == 'note')
              ListTile(
                leading: const Icon(Icons.note_add_rounded),
                title: const Text('New Note'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _createNote(context);
                },
              ),
            // upload — file storagetext
            if (storageType == 'file')
              ListTile(
                leading: const Icon(Icons.upload_file_rounded),
                title: const Text('Upload File'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickAndUploadFiles(context);
                },
              ),
            // text folder — file, note storage
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded),
              title: const Text('New Folder'),
              onTap: () {
                Navigator.of(ctx).pop();
                _createFolder(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// note create — _createFolder text text
  /// dialog close text upload: _handleNoteCreate Body translated text text text text text (T048 §3 priority-3)
  Future<void> _createNote(BuildContext context) async {
    final input = await FileOperationDialogs.showRenameDialog(
      context,
      currentName: 'New Note',
    );
    if (input == null || input.trim().isEmpty || !context.mounted) return;

    final trimmed = input.trim();
    final finalName =
        (trimmed.endsWith('.md') || trimmed.endsWith('.txt'))
            ? trimmed
            : '$trimmed.md';

    final storageProvider = context.read<StorageProvider>();
    final fileProvider = context.read<FileProvider>();
    final authProvider = context.read<AuthProvider>();
    final storageUuid = storageProvider.currentStorage?.storageUuid ?? '';
    final userUuid = authProvider.user?.userUuid ?? '';
    final parentUuid = fileProvider.currentNode.nodeUuid ?? '';

    try {
      final service = StorageService(authProvider.dio);
      final response = await service.upload(
        storageUuid: storageUuid,
        parentUuid: parentUuid,
        userUuid: userUuid,
        groupUuid: '',
        filename: finalName,
        fileBytes: [],
      );

      if (!context.mounted) return;
      fileProvider.loadChildren(storageUuid, userUuid,
          nodeUuid: fileProvider.currentNode.nodeUuid);

      final newNode = Node(
        nodeUuid: response['node_uuid'] as String?,
        name: finalName,
        type: 'file',
      );
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => FilePreviewScreen(
            node: newNode,
            storageUuid: storageUuid,
            userUuid: userUuid,
            groupUuid: '',
          ),
        ),
      );
      if (context.mounted && result == true) {
        fileProvider.loadChildren(storageUuid, userUuid,
            nodeUuid: fileProvider.currentNode.nodeUuid);
      }
    } on DioException catch (e) {
      AppLogger.error('MainScreen', 'Failed to create note: ${e.response?.statusCode}');
      if (!context.mounted) return;
      if (e.response?.statusCode == 409) {
        AppToast.error(context, 'A note with this name already exists');
      } else {
        AppToast.error(context, 'Failed to create note');
      }
    }
  }

  Future<void> _pickAndUploadFiles(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;

    final uploadProvider = context.read<UploadProvider>();
    final storageProvider = context.read<StorageProvider>();
    final fileProvider = context.read<FileProvider>();
    final authProvider = context.read<AuthProvider>();

    final storageUuid = storageProvider.currentStorage?.storageUuid ?? '';
    final userUuid = authProvider.user?.userUuid ?? '';
    final parentUuid = fileProvider.currentNode.nodeUuid ?? '';

    final files = result.files
        .where((f) => f.bytes != null && f.name.isNotEmpty)
        .map((f) => MapEntry(f.name, f.bytes!))
        .toList();

    if (files.isEmpty) return;

    // upload complete text text translated text text text
    uploadProvider.onUploadComplete = () {
      fileProvider.loadChildren(storageUuid, userUuid,
          nodeUuid: fileProvider.currentNode.nodeUuid);
    };

    uploadProvider.addFiles(
      files: files,
      storageUuid: storageUuid,
      parentUuid: parentUuid,
      userUuid: userUuid,
      groupUuid: '',
    );
  }

  Future<void> _createFolder(BuildContext context) async {
    final folderName =
        await FileOperationDialogs.showCreateFolderDialog(context);
    if (folderName == null || !context.mounted) return;

    final storageProvider = context.read<StorageProvider>();
    final fileProvider = context.read<FileProvider>();
    final authProvider = context.read<AuthProvider>();
    final storageUuid = storageProvider.currentStorage?.storageUuid ?? '';
    final userUuid = authProvider.user?.userUuid ?? '';
    final parentUuid = fileProvider.currentNode.nodeUuid;

    try {
      final service = StorageService(authProvider.dio);
      await service.createFolder(
        storageUuid: storageUuid,
        userUuid: userUuid,
        nodeUuid: parentUuid,
        folderName: folderName,
      );
      if (context.mounted) AppToast.success(context, 'Folder created');
      fileProvider.loadChildren(storageUuid, userUuid,
          nodeUuid: fileProvider.currentNode.nodeUuid);
      fileProvider.loadFolderTree(storageUuid, userUuid);
    } catch (e) {
      AppLogger.error('MainScreen', 'Failed to create folder: $e');
      if (context.mounted) AppToast.error(context, 'Failed to create folder');
    }
  }

  // ── text text (selection text) ────────────────────────────────────────────────

  void _triggerBulkDownload(BuildContext context) {
    // FileListScreentext translated text text text text text
    // SelectionProvidertext selectedUuidstext translated text FileListScreen text text
    // translated text text text
    final selectionProvider = context.read<SelectionProvider>();
    final selectedUuids = selectionProvider.selectedUuids;
    if (selectedUuids.isEmpty) return;

    // FileListScreentext _handleBulkDownloadtext translated text translated text,
    // MainScreentranslated text StorageServicetext text text
    _doBulkDownload(context, selectedUuids);
  }

  Future<void> _doBulkDownload(BuildContext ctx, Set<String> nodeUuids) async {
    try {
      final authProvider = ctx.read<AuthProvider>();
      final service = StorageService(authProvider.dio);
      final response = await service.bulkDownload(
        nodeUuids: nodeUuids.toList(),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        if (ctx.mounted) AppToast.error(ctx, 'Download failed');
        return;
      }
      final cdHeader = response.headers.value('content-disposition');
      final filename = DownloadSaveService.extractFilename(cdHeader)
          ?? 'download_${nodeUuids.length}_items.zip';
      await DownloadSaveService.saveBytes(bytes: bytes, filename: filename);
      if (ctx.mounted) AppToast.success(ctx, '${nodeUuids.length} items downloaded');
      if (ctx.mounted) ctx.read<SelectionProvider>().exitSelectionMode();
    } catch (e) {
      AppLogger.error('MainScreen', 'Bulk download failed: $e');
      if (ctx.mounted) AppToast.error(ctx, 'Download failed');
    }
  }

  void _triggerBulkDelete(BuildContext context) {
    final selectionProvider = context.read<SelectionProvider>();
    final selectedUuids = selectionProvider.selectedUuids;
    if (selectedUuids.isEmpty) return;
    _doBulkDelete(context, selectedUuids);
  }

  Future<void> _doBulkDelete(BuildContext ctx, Set<String> nodeUuids) async {
    final confirmed = await FileOperationDialogs.showBulkDeleteConfirmDialog(
      ctx,
      count: nodeUuids.length,
    );
    if (!confirmed || !ctx.mounted) return;

    try {
      final authProvider = ctx.read<AuthProvider>();
      final service = StorageService(authProvider.dio);
      final result = await service.bulkDelete(
        nodeUuids: nodeUuids.toList(),
      );
      final deletedCount = result['deleted_count'] ?? 0;
      final totalCount = result['total_count'] ?? nodeUuids.length;
      final errors = result['errors'];

      if (errors != null && (errors as List).isNotEmpty) {
        if (ctx.mounted) {
          AppToast.warning(ctx, 'Some items failed to delete ($deletedCount/$totalCount)');
        }
      } else {
        if (ctx.mounted) AppToast.success(ctx, '$deletedCount items deleted');
      }
      if (!ctx.mounted) return;
      ctx.read<SelectionProvider>().exitSelectionMode();

      final storageProvider = ctx.read<StorageProvider>();
      final fileProvider = ctx.read<FileProvider>();
      final storageUuid = storageProvider.currentStorage?.storageUuid ?? '';
      final userUuid = authProvider.user?.userUuid ?? '';
      fileProvider.loadChildren(storageUuid, userUuid,
          nodeUuid: fileProvider.currentNode.nodeUuid);
      fileProvider.loadFolderTree(storageUuid, userUuid);
    } catch (e) {
      AppLogger.error('MainScreen', 'Bulk delete failed: $e');
      if (ctx.mounted) AppToast.error(ctx, 'Delete failed');
    }
  }

  Widget _buildDrawer(
    BuildContext context,
    AuthProvider auth,
    StorageProvider storageProvider,
    FileProvider fileProvider,
  ) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // translated text text
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const CircleAvatar(
                    radius: 24,
                    child: Icon(Icons.person_rounded, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    auth.user?.username ?? '',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            // storage selection
            StorageSelector(onStorageSelected: _onStorageSelected),
            const Divider(),
            // folder text
            if (fileProvider.isTreeLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (fileProvider.folderTree.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Folders',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2),
                ),
              ),
              FolderTreeView(
                nodes: fileProvider.folderTree,
                currentNodeUuid: fileProvider.currentNode.nodeUuid,
                onFolderTapped: _onFolderTapped,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

