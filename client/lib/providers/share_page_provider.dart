import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../services/download_save_service.dart';

/// L004 ST-L4-01 기준 — SharePage 5-상태 머신
enum SharePageState { loading, password, file, folder, error }

/// 폴더 내 항목 모델
class ShareItem {
  final String uuid;
  final String name;
  final String type; // 'file' | 'folder'
  final int? size;
  final String? mimeType;

  const ShareItem({
    required this.uuid,
    required this.name,
    required this.type,
    this.size,
    this.mimeType,
  });

  factory ShareItem.fromJson(Map<String, dynamic> json) {
    return ShareItem(
      uuid: json['uuid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'file',
      size: json['size'] as int?,
      mimeType: json['mime_type'] as String?,
    );
  }
}

/// 파일 공유 메타 모델
class ShareFileInfo {
  final String name;
  final int? fileSize;
  final String? mimeType;

  const ShareFileInfo({
    required this.name,
    this.fileSize,
    this.mimeType,
  });

  factory ShareFileInfo.fromJson(Map<String, dynamic> json) {
    return ShareFileInfo(
      name: json['name'] as String? ?? '',
      fileSize: json['file_size'] as int?,
      mimeType: json['mime_type'] as String?,
    );
  }
}

/// L004 §2 SharePage 상태 머신 Provider.
/// - app.dart MultiProvider에 전역 등록 금지 (L004 ST-L4-02).
/// - SharePage 위젯 내부에서 ChangeNotifierProvider(create: ...) 로 직접 생성.
/// - 공개 API 전용 별도 Dio 사용 — ApiClient/authProvider 불필요.
class SharePageProvider extends ChangeNotifier {
  // ── 상태 ────────────────────────────────────────────────────────────────
  SharePageState _state = SharePageState.loading;
  String _token = '';
  String? _verifiedPassword;
  String _currentPath = '';
  String? _folderName;
  List<ShareItem> _items = [];
  ShareFileInfo? _fileInfo;
  String? _errorMessage;
  List<String> _breadcrumbs = [];

  // ── 공개 API 전용 Dio (AppConfig.baseUrl 기반; 인증 헤더 없음) ────────────
  late final Dio _dio;

  SharePageProvider() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => true, // 에러 코드도 직접 처리
    ));
  }

  // ── 읽기 전용 ─────────────────────────────────────────────────────────
  SharePageState get state => _state;
  String get token => _token;
  String get currentPath => _currentPath;
  String? get folderName => _folderName;
  List<ShareItem> get items => List.unmodifiable(_items);
  ShareFileInfo? get fileInfo => _fileInfo;
  String? get errorMessage => _errorMessage;
  List<String> get breadcrumbs => List.unmodifiable(_breadcrumbs);

  /// T075: 비밀번호 보호 공유 여부. 비밀번호 없이 메타 조회 성공 시 false.
  bool get isPasswordProtected => _verifiedPassword != null;

  // ── 내부 헬퍼 ─────────────────────────────────────────────────────────

  Map<String, String> get _passwordHeader => _verifiedPassword != null
      ? {'X-Share-Password': _verifiedPassword!}
      : {};

  /// currentPath → breadcrumbs 파싱 (BT-L4-02)
  List<String> _parseBreadcrumbs(String path) {
    if (path.isEmpty) return ['Home'];
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    return ['Home', ...segments];
  }

  void _applyMetaResponse(Map<String, dynamic> data) {
    final nodeType = data['node_type'] as String? ?? '';
    if (nodeType == 'file') {
      _fileInfo = ShareFileInfo.fromJson(data);
      _state = SharePageState.file;
    } else {
      _folderName = data['folder_name'] as String?;
      _currentPath = data['current_path'] as String? ?? '';
      _breadcrumbs = _parseBreadcrumbs(_currentPath);
      final rawItems = data['items'] as List<dynamic>? ?? [];
      _items = rawItems
          .cast<Map<String, dynamic>>()
          .map(ShareItem.fromJson)
          .toList();
      _state = SharePageState.folder;
    }
  }

  // ── 공개 API ──────────────────────────────────────────────────────────

  /// ST-L4-01 #1~#5: 공유 링크 메타 조회.
  Future<void> loadMeta(String token) async {
    _token = token;
    _state = SharePageState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/share/$token',
        queryParameters: {'meta': 'true'},
        options: Options(headers: _passwordHeader),
      );
      _handleMetaResponse(response);
    } catch (e) {
      _state = SharePageState.error;
      _errorMessage = 'Network error occurred';
    }
    notifyListeners();
  }

  void _handleMetaResponse(Response<Map<String, dynamic>> response,
      {bool fromPassword = false, String? pw}) {
    final status = response.statusCode ?? 0;
    if (status == 200) {
      final data = response.data ?? {};
      if (fromPassword && pw != null) {
        _verifiedPassword = pw;
      }
      _applyMetaResponse(data);
    } else if (status == 401) {
      _state = SharePageState.password;
      _errorMessage = null;
    } else if (status == 403) {
      _state = SharePageState.password;
      _errorMessage = 'Incorrect password';
    } else if (status == 404) {
      _state = SharePageState.error;
      _errorMessage = 'Shared link not found';
    } else {
      _state = SharePageState.error;
      _errorMessage = 'An error occurred (HTTP $status)';
    }
  }

  /// ST-L4-01 #6~#8: 비밀번호 제출.
  Future<void> submitPassword(String pw) async {
    _state = SharePageState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/share/$_token',
        queryParameters: {'meta': 'true'},
        options: Options(headers: {'X-Share-Password': pw}),
      );
      _handleMetaResponse(response, fromPassword: true, pw: pw);
    } catch (e) {
      _state = SharePageState.password;
      _errorMessage = 'Network error occurred';
    }
    notifyListeners();
  }

  /// ST-L4-01 #9~#10: 서브폴더 탐색.
  Future<void> navigateFolder(
    String folderName, {
    required void Function(String) onToast,
  }) async {
    final newPath = _currentPath.isEmpty
        ? folderName
        : '$_currentPath/$folderName';
    _state = SharePageState.loading;
    notifyListeners();

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/share/$_token',
        queryParameters: {'meta': 'true', 'path': newPath},
        options: Options(headers: _passwordHeader),
      );
      final status = response.statusCode ?? 0;
      if (status == 200) {
        _applyMetaResponse(response.data ?? {});
      } else if (status == 404) {
        onToast('Folder not found');
        // 루트로 복귀 (error 상태로 전이 금지 — L004 ST-L4-01 #10)
        await _loadRoot();
        return;
      } else {
        _state = SharePageState.folder; // 현재 상태 복구
      }
    } catch (e) {
      _state = SharePageState.folder;
    }
    notifyListeners();
  }

  /// ST-L4-01 #11: 빵부스러기 클릭.
  Future<void> clickBreadcrumb(int index) async {
    // index 0 = '홈' → path = ""
    // index N → breadcrumbs[1..N] 조합
    final segments = _breadcrumbs.skip(1).take(index).toList();
    final targetPath = segments.join('/');
    _state = SharePageState.loading;
    notifyListeners();

    try {
      final queryParams = <String, String>{'meta': 'true'};
      if (targetPath.isNotEmpty) queryParams['path'] = targetPath;
      final response = await _dio.get<Map<String, dynamic>>(
        '/share/$_token',
        queryParameters: queryParams,
        options: Options(headers: _passwordHeader),
      );
      if ((response.statusCode ?? 0) == 200) {
        _applyMetaResponse(response.data ?? {});
      } else {
        _state = SharePageState.folder;
      }
    } catch (e) {
      _state = SharePageState.folder;
    }
    notifyListeners();
  }

  /// ST-L4-01 #12~#13: 파일 다운로드.
  /// - file 상태: GET /share/{token}
  /// - folder 상태 내 항목: GET /share/{token}/{fileUuid}
  Future<void> downloadFile({
    String? fileUuid,
    required void Function(String) onToast,
  }) async {
    try {
      final path = (fileUuid != null)
          ? '/share/$_token/$fileUuid'
          : '/share/$_token';

      final response = await _dio.get<List<int>>(
        path,
        options: Options(
          headers: _passwordHeader,
          responseType: ResponseType.bytes,
        ),
      );

      final status = response.statusCode ?? 0;
      if (status != 200) {
        onToast(status == 404 ? 'File not found' : 'Download failed');
        return;
      }

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        onToast('Download failed');
        return;
      }

      final cdHeader = response.headers.value('content-disposition');
      final filename = DownloadSaveService.extractFilename(cdHeader) ??
          (fileUuid != null ? 'file_$fileUuid' : 'download');

      await DownloadSaveService.saveBytes(bytes: bytes, filename: filename);
      onToast('Download complete');
    } catch (e) {
      onToast('Download failed');
    }
  }

  /// 루트 폴더로 복귀해 재조회.
  Future<void> _loadRoot() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/share/$_token',
        queryParameters: {'meta': 'true'},
        options: Options(headers: _passwordHeader),
      );
      if ((response.statusCode ?? 0) == 200) {
        _applyMetaResponse(response.data ?? {});
      } else {
        _state = SharePageState.folder;
      }
    } catch (e) {
      _state = SharePageState.folder;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    // ST-L4-02 #4: dispose 시 verifiedPassword 폐기
    _verifiedPassword = null;
    super.dispose();
  }
}
