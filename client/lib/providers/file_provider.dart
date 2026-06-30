import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/node.dart';
import '../services/logger.dart';
import '../models/breadcrumb.dart';
import '../services/storage_service.dart';

/// file text text text (T052)
enum FileViewMode { list, grid }

/// L001 § 3-3 — file text, current folder, translated text, folder text, text state management
/// L002 ST-02 text text:
///   - server text text translated text translated text prohibited
///   - empty translated text API text prohibited (loadChildren search parameters text text text)
///   - folderTreetext file text text prohibited (server directory_trees translated text foldertext)
///   - translated text text text text prohibited (_isLoading guard)
class FileProvider extends ChangeNotifier {
  // ── state ─────────────────────────────────────────────────────────────────
  List<Node> _children = [];
  Node _currentNode = Node.root();
  List<Breadcrumb> _breadcrumbs = [];
  List<Node> _folderTree = [];
  bool _isLoading = false;
  bool _isTreeLoading = false;
  int _loadingSeq = 0;
  String _loadingKey = '';
  String? _error;
  String _searchQuery = '';
  bool _isSearchMode = false;
  FileViewMode _fileViewMode = FileViewMode.list;

  // ── translated text ────────────────────────────────────────────────────────────────
  late final StorageService _storageService;

  static const _kViewModeKey = 'fileforge_viewMode';

  /// [initialViewMode]: main()text runApp text text translated text translated text (T055 translated text text)
  FileProvider(Dio dio, {FileViewMode initialViewMode = FileViewMode.list}) {
    _storageService = StorageService(dio);
    _fileViewMode = initialViewMode;
  }

  // ── read-only ─────────────────────────────────────────────────────────────
  List<Node> get children => _children;
  Node get currentNode => _currentNode;
  List<Breadcrumb> get breadcrumbs => _breadcrumbs;
  List<Node> get folderTree => _folderTree;
  bool get isLoading => _isLoading;
  bool get isTreeLoading => _isTreeLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  bool get isSearchMode => _isSearchMode;
  FileViewMode get fileViewMode => _fileViewMode;

  // ── initialize ────────────────────────────────────────────────────────────────

  /// storage text text text state text initialize (L002 ST-02 Row2).
  /// fileViewModetext translated text translated text keeptext (T055).
  void reset() {
    _children = [];
    _currentNode = Node.root();
    _breadcrumbs = [];
    _folderTree = [];
    _error = null;
    _searchQuery = '';
    _isSearchMode = false;
    notifyListeners();
  }

  /// translated text/translated text text text text (T052) + SharedPreferences save (T055)
  Future<void> toggleFileViewMode() async {
    _fileViewMode = _fileViewMode == FileViewMode.list
        ? FileViewMode.grid
        : FileViewMode.list;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kViewModeKey,
        _fileViewMode == FileViewMode.grid ? 'grid' : 'list');
  }

  // ── file text text ────────────────────────────────────────────────────────

  /// GET /storages/get_node_children
  /// translated text text text translated text translated text (L002 ST-02 Row6).
  Future<void> loadChildren(
    String storageUuid,
    String userUuid, {
    String? nodeUuid,
    String? search,
  }) async {
    // storageUuid + nodeUuid + search translated text translated text translated text text translated text translated text.
    final key = '$storageUuid|$nodeUuid|$search';
    AppLogger.debug('FileProvider', 'loadChildren storageUuid=$storageUuid nodeUuid=$nodeUuid key=$key isLoading=$_isLoading loadingKey=$_loadingKey seq=${_loadingSeq + 1}');
    if (_isLoading && _loadingKey == key) return;
    // translated text text: text text translated text text translated text translated text translated text translated text text.
    final seq = ++_loadingSeq;
    _loadingKey = key;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _storageService.getNodeChildren(
        storageUuid: storageUuid,
        userUuid: userUuid,
        nodeUuid: nodeUuid,
        search: search,
      );
      // stale text text: text translated text translated text text text translated text translated text translated text translated text.
      if (seq != _loadingSeq) return;
      _children = (data['children'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(Node.fromJson)
          .toList();
      _currentNode = data['current_node'] != null
          ? Node.fromJson(data['current_node'] as Map<String, dynamic>)
          : Node.root();
      _breadcrumbs = (data['breadcrumb_path'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(Breadcrumb.fromJson)
          .toList();
    } catch (e) {
      if (seq == _loadingSeq) _error = e.toString();
    } finally {
      if (seq == _loadingSeq) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // ── folder text text ────────────────────────────────────────────────────────

  /// GET /storages/get_directory_trees
  /// servertext foldertext returntranslated text add text text text (L002 ST-02 Row10).
  Future<void> loadFolderTree(String storageUuid, String userUuid) async {
    _isTreeLoading = true;
    notifyListeners();
    try {
      final data = await _storageService.getDirectoryTrees(
        storageUuid: storageUuid,
        userUuid: userUuid,
      );
      _folderTree = (data['tree'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(Node.fromJson)
          .toList();
    } catch (_) {
      // text text failedtext text errortext translated text text (text UI)
    } finally {
      _isTreeLoading = false;
      notifyListeners();
    }
  }

  // ── text ──────────────────────────────────────────────────────────────────

  /// text text text — empty translated text text translated text text (L002 ST-02 Row7).
  void setSearchQuery(
    String query,
    String storageUuid,
    String userUuid,
  ) {
    _searchQuery = query;
    if (query.isEmpty) {
      _isSearchMode = false;
      loadChildren(storageUuid, userUuid);
    } else {
      _isSearchMode = true;
      loadChildren(storageUuid, userUuid, search: query);
    }
  }

  void enterSearchMode() {
    _isSearchMode = true;
    notifyListeners();
  }

  void exitSearchMode(String storageUuid, String userUuid) {
    _searchQuery = '';
    _isSearchMode = false;
    loadChildren(storageUuid, userUuid);
  }

  /// Toggle off only the search UI (B0001/0026) — does not reload file children.
  /// The shared AppBar search box is shown via this flag, but in mail storage
  /// search is routed to MailProvider, so closing mail search must not call the file node API.
  void exitSearchModeUiOnly() {
    _searchQuery = '';
    _isSearchMode = false;
    notifyListeners();
  }
}
