import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/auth_exception.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../utils/secure_storage.dart';
import '../config/app_config.dart';

/// L002 ST-01 로그인 결과 열거형
enum LoginResult { success, totpRequired, failed }

/// 인증 상태 관리 Provider
/// Phase 1+2 책임:
///   - access/refresh token 메모리 보관
///   - SecureStorage 저장/불러오기/삭제
///   - tryAutoLogin() — 앱 시작 시 자동 로그인
///   - refreshAccessToken() — 토큰 갱신
///   - logout() — 로그아웃
///   - login() — ID/PW 로그인 (Phase 2)
///   - verifyTotp() — TOTP 2차 인증 (Phase 2)
class AuthProvider extends ChangeNotifier {
  // 상태
  User? _user;
  String? _accessToken;
  String? _refreshToken;
  String? _tempToken;   // TOTP 화면으로 전달할 temp_token
  bool _isLoading = false;
  String? _error;

  // 서비스
  late final ApiClient _apiClient;
  late final AuthService _authService;
  final SecureStorage _secureStorage = SecureStorage();

  /// 로그아웃/세션 만료 시 StorageProvider·FileProvider 초기화 트리거 (T074)
  VoidCallback? _onProviderReset;

  // 읽기 전용
  bool get isAuthenticated => _accessToken != null && _user != null;
  User? get user => _user;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get tempToken => _tempToken;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// StorageProvider / FileProvider 가 같은 인터셉터를 공유하기 위해 노출한다.
  Dio get dio => _apiClient.dio;

  /// app.dart에서 StorageProvider·FileProvider reset()을 연결한다 (T074).
  void setProviderResetCallback(VoidCallback callback) {
    _onProviderReset = callback;
  }

  /// 서버 주소를 동적으로 변경한다. 설정 화면에서 호출한다.
  void setServerUrl(String hostPort) {
    _apiClient.setBaseUrl(hostPort);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  AuthProvider() {
    _apiClient = ApiClient();
    _authService = AuthService(_apiClient.dio);
    _apiClient.configure(
      getAccessToken: () => _accessToken,
      onRefreshToken: refreshAccessToken,
      onSessionExpired: _handleSessionExpired,
    );
  }

  // ── 세션 만료 처리 (401 refresh 실패) ──────────────────────────────────────

  Future<void> _handleSessionExpired() async {
    _onProviderReset?.call();
    await _clearTokens();
    notifyListeners();
  }

  Future<void> _clearTokens() async {
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    _tempToken = null;
    _error = null;
    await Future.wait([
      _secureStorage.delete(AppConfig.keyAccessToken),
      _secureStorage.delete(AppConfig.keyRefreshToken),
      _secureStorage.delete(AppConfig.keyUserId),
      _secureStorage.delete(AppConfig.keyUsername),
      _secureStorage.delete(AppConfig.keyUserUuid),
    ]);
  }

  // ── 자동 로그인 ─────────────────────────────────────────────────────────────

  /// L001 기준 3분기 자동 로그인:
  ///   1. accessToken 유효 → true (서버 요청 없음)
  ///   2. accessToken 만료 + refreshToken 존재 → refresh 시도 → true/false
  ///   3. 둘 다 없음/만료 → false
  /// JWT exp는 로컬 파싱으로 판단하되 최종 유효성은 서버가 결정한다 (BD-01).
  Future<bool> tryAutoLogin() async {
    final storedRefresh = await _secureStorage.read(AppConfig.keyRefreshToken);
    final storedUserId = await _secureStorage.read(AppConfig.keyUserId);

    if (storedRefresh == null || storedUserId == null) return false;

    final storedAccess = await _secureStorage.read(AppConfig.keyAccessToken);
    final storedUsername = await _secureStorage.read(AppConfig.keyUsername);
    final storedUserUuid = await _secureStorage.read(AppConfig.keyUserUuid);

    // 불완전 세션 감지: userUuid 없으면 토큰 삭제 후 재로그인 유도
    if (storedUserUuid == null || storedUserUuid.isEmpty) {
      await _clearTokens();
      return false;
    }

    // 메모리 복원
    _accessToken = storedAccess;
    _refreshToken = storedRefresh;
    _user = User(
      userId: storedUserId,
      username: storedUsername ?? storedUserId,
      userUuid: storedUserUuid,
    );

    // 분기 1: access token이 존재하고 만료되지 않았으면 그대로 세션 유지
    if (storedAccess != null && !_isJwtExpired(storedAccess)) {
      notifyListeners();
      return true;
    }

    // 분기 2: access 만료(또는 없음) — refresh로 갱신 시도
    return await refreshAccessToken();
  }

  /// JWT payload의 exp 클레임을 로컬 파싱하여 만료 여부를 반환한다.
  /// 파싱 실패 시 만료로 처리한다 (BD-01: 최종 유효성은 서버 판단).
  bool _isJwtExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final exp = json['exp'] as int?;
      if (exp == null) return true;
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp;
    } catch (_) {
      return true;
    }
  }

  // ── 토큰 갱신 ────────────────────────────────────────────────────────────────

  /// POST /login/refresh 호출. 성공 시 새 access token 저장 후 true 반환.
  /// 실패 시 저장된 토큰 전체를 삭제하고 false 반환.
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;
    try {
      final newAccessToken = await _authService.refreshToken(_refreshToken!);
      _accessToken = newAccessToken;
      await _secureStorage.write(AppConfig.keyAccessToken, newAccessToken);
      notifyListeners();
      return true;
    } catch (_) {
      await _clearTokens();
      notifyListeners();
      return false;
    }
  }

  // ── 로그인 (Phase 2) ─────────────────────────────────────────────────────────

  /// POST /login 호출. L002 ST-01 기준.
  /// - success      : access/refresh token + user 저장
  /// - totpRequired : _tempToken 보관, 화면이 /login/totp 이동
  /// - failed       : _error 설정 (L002 메시지 기준)
  Future<LoginResult> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _authService.login(username, password);
      if (data['totp_required'] == true) {
        _tempToken = data['temp_token'] as String?;
        _isLoading = false;
        notifyListeners();
        return LoginResult.totpRequired;
      }
      final resp = AuthLoginResponse.fromJson(data);
      await _saveSession(resp);
      _isLoading = false;
      notifyListeners();
      return LoginResult.success;
    } on AuthException catch (e) {
      debugPrint('[B004][AuthProvider.login] AuthException detail=${e.detail}');
      _isLoading = false;
      _error = _loginErrorMessage(e.detail);
      notifyListeners();
      return LoginResult.failed;
    } catch (e, st) {
      debugPrint('[B004][AuthProvider.login] Unexpected error=$e');
      debugPrint('$st');
      _isLoading = false;
      _error = 'An error occurred during login';
      notifyListeners();
      return LoginResult.failed;
    }
  }

  String _loginErrorMessage(String detail) {
    if (detail == 'Invalid credentials') {
      return 'Invalid username or password';
    }
    return 'An error occurred during login';
  }

  // ── TOTP 검증 (Phase 2) ──────────────────────────────────────────────────────

  /// POST /login/totp/verify 호출.
  /// 성공: access/refresh token 저장, _tempToken 소거.
  /// 실패: AuthException rethrow — 화면이 detail 값으로 분기.
  ///   - 'invalid_code'  → 화면 유지, 오류 메시지 표시
  ///   - 'token_expired' → /login 이동
  Future<void> verifyTotp(String tempToken, String code) async {
    _isLoading = true;
    notifyListeners();
    try {
      final resp = await _authService.verifyTotp(tempToken, code);
      _tempToken = null;
      await _saveSession(resp);
      _isLoading = false;
      notifyListeners();
    } on AuthException {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // ── 내부 헬퍼 ────────────────────────────────────────────────────────────────

  Future<void> _saveSession(AuthLoginResponse resp) async {
    // T074: 새 세션 저장 전 이전 계정 상태 초기화 (로그인 직후 경로 보장)
    _onProviderReset?.call();
    _user = resp.user;
    _accessToken = resp.accessToken;
    _refreshToken = resp.refreshToken;
    await Future.wait([
      _secureStorage.write(AppConfig.keyAccessToken, resp.accessToken),
      _secureStorage.write(AppConfig.keyRefreshToken, resp.refreshToken),
      _secureStorage.write(AppConfig.keyUserId, resp.user.userId),
      _secureStorage.write(AppConfig.keyUsername, resp.user.username),
      _secureStorage.write(AppConfig.keyUserUuid, resp.user.userUuid ?? ''),
    ]);
  }

  // ── 로그아웃 ─────────────────────────────────────────────────────────────────

  /// POST /logout → 로컬 토큰 전체 삭제.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    try {
      if (_refreshToken != null) {
        await _authService.logout(_refreshToken!);
      }
    } catch (_) {
      // 서버 오류가 발생해도 로컬 세션은 정리한다.
    }
    _onProviderReset?.call();
    await _clearTokens();
    _isLoading = false;
    notifyListeners();
  }

}


