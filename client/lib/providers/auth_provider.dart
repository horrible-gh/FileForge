import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/auth_exception.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../utils/secure_storage.dart';
import '../config/app_config.dart';

/// L002 ST-01 login result translated text
enum LoginResult { success, totpRequired, failed }

/// authentication state management Provider
/// Phase 1+2 text:
///   - access/refresh token notetext text
///   - SecureStorage save/load/delete
///   - tryAutoLogin() — text text text text login
///   - refreshAccessToken() — token refresh
///   - logout() — logout
///   - login() — ID/PW login (Phase 2)
///   - verifyTotp() — TOTP 2text authentication (Phase 2)
class AuthProvider extends ChangeNotifier {
  // state
  User? _user;
  String? _accessToken;
  String? _refreshToken;
  String? _tempToken;   // TOTP screentext translated text temp_token
  bool _isLoading = false;
  String? _error;

  // translated text
  late final ApiClient _apiClient;
  late final AuthService _authService;
  final SecureStorage _secureStorage = SecureStorage();

  /// logout/session expired text StorageProvider·FileProvider initialize translated text (T074)
  VoidCallback? _onProviderReset;

  /// 서버 주소 오버라이드 시 메일 Dio도 함께 따라가도록 하는 콜백 (B0001 / NR0003 §3).
  /// app.dart에서 MailApiClient.setBaseUrl을 등록한다. 등록 전이면 파일 Dio만 갱신.
  ValueChanged<String>? _onServerUrlChanged;

  // read-only
  bool get isAuthenticated => _accessToken != null && _user != null;
  User? get user => _user;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get tempToken => _tempToken;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// StorageProvider / FileProvider text text translated text translated text text translated text.
  Dio get dio => _apiClient.dio;

  /// app.darttext StorageProvider·FileProvider reset()text translated text (T074).
  void setProviderResetCallback(VoidCallback callback) {
    _onProviderReset = callback;
  }

  /// 메일 Dio도 서버 주소 오버라이드를 따라가도록 콜백 등록 (B0001 / NR0003 §3).
  /// app.dart에서 MailApiClient 생성 직후 1회 배선한다.
  void setServerUrlChangeCallback(ValueChanged<String> callback) {
    _onServerUrlChanged = callback;
  }

  /// server translated text translated text changetext. text screentext translated text.
  ///
  /// 파일 API Dio뿐 아니라 메일 Dio도 같은 origin으로 따라가게 한다 — 그렇지 않으면
  /// 메일/계정 요청이 빌드에 박힌 주소(기본 localhost)로 가서 "구글 연동하라"가
  /// 뜬다(B0001 / NR0003 §3).
  void setServerUrl(String hostPort) {
    _apiClient.setBaseUrl(hostPort);
    _onServerUrlChanged?.call(hostPort);
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

  // ── session expired text (401 refresh failed) ──────────────────────────────────────

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

  // ── text login ─────────────────────────────────────────────────────────────

  /// L001 text 3branch text login:
  ///   1. accessToken text → true (server text None)
  ///   2. accessToken expired + refreshToken text → refresh text → true/false
  ///   3. text text None/expired → false
  /// JWT exptext local translated text translated text text validitytext servertext translated text (BD-01).
  Future<bool> tryAutoLogin() async {
    final storedRefresh = await _secureStorage.read(AppConfig.keyRefreshToken);
    final storedUserId = await _secureStorage.read(AppConfig.keyUserId);

    if (storedRefresh == null || storedUserId == null) return false;

    final storedAccess = await _secureStorage.read(AppConfig.keyAccessToken);
    final storedUsername = await _secureStorage.read(AppConfig.keyUsername);
    final storedUserUuid = await _secureStorage.read(AppConfig.keyUserUuid);

    // translated text session text: userUuid translated text token delete text textlogin text
    if (storedUserUuid == null || storedUserUuid.isEmpty) {
      await _clearTokens();
      return false;
    }

    // notetext text
    _accessToken = storedAccess;
    _refreshToken = storedRefresh;
    _user = User(
      userId: storedUserId,
      username: storedUsername ?? storedUserId,
      userUuid: storedUserUuid,
    );

    // branch 1: access tokentext translated text expiredtext translated text as-is session keep
    if (storedAccess != null && !_isJwtExpired(storedAccess)) {
      notifyListeners();
      return true;
    }

    // branch 2: access expired(text None) — refreshtext refresh text
    return await refreshAccessToken();
  }

  /// JWT payloadtext exp claimstext local translated text expired translated text returntext.
  /// parse failed text expiredtext translated text (BD-01: text validitytext server text).
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

  // ── token refresh ────────────────────────────────────────────────────────────────

  /// POST /login/refresh text. success text text access token save text true return.
  /// failed text savetext token translated text deletetext false return.
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

  // ── login (Phase 2) ─────────────────────────────────────────────────────────

  /// POST /login text. L002 ST-01 text.
  /// - success      : access/refresh token + user save
  /// - totpRequired : _tempToken text, screentext /login/totp navigate
  /// - failed       : _error text (L002 translated text text)
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

  // ── TOTP verify (Phase 2) ──────────────────────────────────────────────────────

  /// POST /login/totp/verify text.
  /// success: access/refresh token save, _tempToken text.
  /// failed: AuthException rethrow — screentext detail translated text branch.
  ///   - 'invalid_code'  → screen keep, error translated text display
  ///   - 'token_expired' → /login navigate
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

  // ── internal helper ────────────────────────────────────────────────────────────────

  Future<void> _saveSession(AuthLoginResponse resp) async {
    // T074: text session save text text account state initialize (login text path text)
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

  // ── logout ─────────────────────────────────────────────────────────────────

  /// POST /logout → local token text delete.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    try {
      if (_refreshToken != null) {
        await _authService.logout(_refreshToken!);
      }
    } catch (_) {
      // server errortext translated text local sessiontext translated text.
    }
    _onProviderReset?.call();
    await _clearTokens();
    _isLoading = false;
    notifyListeners();
  }

}


