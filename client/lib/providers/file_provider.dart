import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/node.dart';
import '../services/logger.dart';
import '../models/breadcrumb.dart';
import '../services/storage_service.dart';

/// 파일 목록 뷰 모드 (T052)
enum FileViewMode { list, grid }

/// L001 § 3-3 — 파일 목록, 현재 폴더, 빵부스러기, 폴더 트리, 검색 상태 관리
/// L002 ST-02 경계 준수:
///   - 서버 응답 전 낙관적 업데이트 금지
///   - 빈 검색어로 API 호출 금지 (loadChildren search 파라미터 전달 안 함)
///   - folderTree에 파일 노드 포함 금지 (서버 directory_trees 응답은 폴더만)
///   - 리프레시 중 중복 요청 금지 (_isLoading 가드)
class FileProvider extends ChangeNotifier {
  // ── 상태 ─────────────────────────────────────────────────────────────────
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

  // ── 서비스 ────────────────────────────────────────────────────────────────
  late final StorageService _storageService;

  static const _kViewModeKey = 'fileforge_viewMode';

  /// [initialViewMode]: main()에서 runApp 전 사전 로드한 초기값 (T055 깜빡임 방지)
  FileProvider(Dio dio, {FileViewMode initialViewMode = FileViewMode.list}) {
    _storageService = StorageService(dio);
    _fileViewMode = initialViewMode;
  }

  // ── 읽기 전용 ─────────────────────────────────────────────────────────────
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

  // ── 초기화 ────────────────────────────────────────────────────────────────

  /// 스토리지 전환 시 이전 상태 전체 초기화 (L002 ST-02 Row2).
  /// fileViewMode는 사용자 선호값이므로 유지한다 (T055).
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

  /// 리스트/그리드 뷰 모드 토글 (T052) + SharedPreferences 저장 (T055)
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

  // ── 파일 목록 로드 ────────────────────────────────────────────────────────

  /// GET /storages/get_node_children
  /// 리프레시 중 중복 요청은 무시한다 (L002 ST-02 Row6).
  Future<void> loadChildren(
    String storageUuid,
    String userUuid, {
    String? nodeUuid,
    String? search,
  }) async {
    // storageUuid + nodeUuid + search 조합이 완전히 동일한 중복 요청만 차단한다.
    final key = '$storageUuid|$nodeUuid|$search';
    AppLogger.debug('FileProvider', 'loadChildren storageUuid=$storageUuid nodeUuid=$nodeUuid key=$key isLoading=$_isLoading loadingKey=$_loadingKey seq=${_loadingSeq + 1}');
    if (_isLoading && _loadingKey == key) return;
    // 시퀀스 증가: 응답 수신 시점에 이 요청이 여전히 최신인지 판별하기 위함.
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
      // stale 응답 무시: 이 응답이 수신될 때 더 새로운 요청이 있으면 버린다.
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

  // ── 폴더 트리 로드 ────────────────────────────────────────────────────────

  /// GET /storages/get_directory_trees
  /// 서버가 폴더만 반환하므로 추가 필터 없이 사용 (L002 ST-02 Row10).
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
      // 트리 로드 실패는 메인 에러로 처리하지 않음 (보조 UI)
    } finally {
      _isTreeLoading = false;
      notifyListeners();
    }
  }

  // ── 검색 ──────────────────────────────────────────────────────────────────

  /// 검색 모드 진입 — 빈 쿼리는 일반 목록으로 전환 (L002 ST-02 Row7).
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
}
