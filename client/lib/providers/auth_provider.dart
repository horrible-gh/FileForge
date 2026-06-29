import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import '../models/user.dart';
import '../models/auth_exception.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../utils/secure_storage.dart';
import '../config/app_config.dart';

/// L002 ST-01 login result translated text
enum LoginResult { success, totpRequired, failed }

/// Outcome of the most recent rotation attempt — lets the 401 interceptor tell
/// a genuine expiry (log out) from a transient network blip (keep session).
/// L0004 §2.4.
enum _RefreshOutcome { none, success, expired, transient }

/// authentication state management Provider
/// Phase 1+2 text:
///   - access/refresh token notetext text
///   - SecureStorage save/load/delete
///   - tryAutoLogin() — text text text text login
///   - refreshAccessToken() — token refresh
///   - logout() — logout
///   - login() — ID/PW login (Phase 2)
///   - verifyTotp() — TOTP 2text authentication (Phase 2)
class AuthProvider extends ChangeNotifier with WidgetsBindingObserver {
  // ── 3rd-gen session keep-alive parameters (L0004 §1) ─────────────────────
  /// Rotate this long before the access token expires so expiry never surfaces
  /// to a user request as a 401.
  static const int refreshSkewMs = 60 * 1000;
  /// Floor for the proactive timer delay (avoid a busy-loop near expiry).
  static const int minRefreshDelayMs = 2 * 1000;
  /// On resume/focus, treat the token as "due" if it expires within this window.
  static const int nearExpiryThresholdMs = refreshSkewMs;
  /// Network-error retries during a rotation before giving up as transient.
  static const int refreshNetworkRetry = 2;
  /// Backoff (ms) between network retries (index by attempt).
  static const List<int> refreshRetryBackoffMs = [1000, 3000];

  // state
  User? _user;
  String? _accessToken;
  String? _refreshToken;
  String? _tempToken;   // TOTP screentext translated text temp_token
  bool _isLoading = false;
  String? _error;

  // ── token-manager internals (NR0003 F1/F2, L0004 §2) ─────────────────────
  /// The single in-flight rotation. Every caller (both Dios' 401 handlers, the
  /// proactive timer, startup) awaits this same future so the refresh token is
  /// POSTed at most once — fixes the dual-Dio race (F2).
  Future<String?>? _refreshFuture;
  /// Outcome of the last completed rotation (drives logout-vs-keep decision).
  _RefreshOutcome _lastRefreshOutcome = _RefreshOutcome.none;
  /// Proactive pre-expiry refresh timer.
  Timer? _proactiveTimer;
  /// True once the app shell has started session keep-alive (lifecycle observer
  /// + proactive scheduling). Gated so plain unit tests never spawn timers.
  bool _keepAliveActive = false;
  /// Suppress rotations while an explicit logout is in progress (L0004 §5).
  bool _loggingOut = false;

  // translated text
  late final ApiClient _apiClient;
  late final AuthService _authService;
  final SecureStorage _secureStorage = SecureStorage();

  /// logout/session expired text StorageProvider·FileProvider initialize translated text (T074)
  VoidCallback? _onProviderReset;

  /// 서버 주소 오버라이드 시 메일 Dio도 함께 따라가도록 하는 콜백 (B0001 / NR0003 §3).
  /// app.dart에서 MailApiClient.setBaseUrl을 등록한다. 등록 전이면 파일 Dio만 갱신.
  ValueChanged<String>? _onServerUrlChanged;

  /// SecureBolt(fileforge.securebolt.0002 / TR0005): 신선 ID/PW 로그인 직후
  /// 그 평문 비밀번호로 볼트 마스터 키를 파생해 두기 위한 콜백.
  /// app.dart에서 VaultProvider.unlock(username, password)를 등록한다.
  ///
  /// 토큰 자동로그인(앱 재시작)에는 평문 비번이 없어 호출되지 않는다 — 그 경우
  /// 볼트는 잠금 상태로 남고, SecureBolt 첫 진입 시 1회 인라인 언락으로 폴백한다
  /// (제로지식: 마스터 해시/비번은 절대 영속하지 않는다).
  Future<void> Function(String username, String password)? _onVaultUnlock;

  /// TOTP 사용자는 비밀번호가 login()에서, 세션 확정은 verifyTotp()에서 일어난다.
  /// 그 사이에만 평문 비번을 잠시 보관했다가 verifyTotp() 성공 시 소비·즉시 폐기한다.
  String? _pendingVaultPassword;

  // read-only
  bool get isAuthenticated => _accessToken != null && _user != null;
  User? get user => _user;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get tempToken => _tempToken;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// True iff the most recent rotation failed with a genuine server rejection
  /// (real expiry). The shared 401 interceptor uses this to log out only on a
  /// real expiry, never on a transient network failure (L0004 §2.4).
  bool get lastRefreshWasExpired =>
      _lastRefreshOutcome == _RefreshOutcome.expired;

  /// StorageProvider / FileProvider text text translated text translated text text translated text.
  Dio get dio => _apiClient.dio;

  /// app.darttext StorageProvider·FileProvider reset()text translated text (T074).
  void setProviderResetCallback(VoidCallback callback) {
    _onProviderReset = callback;
  }

  /// SecureBolt(TR0005): 신선 로그인 시 볼트 마스터 키를 파생할 콜백 등록.
  /// app.dart에서 VaultProvider.unlock을 1회 배선한다.
  void setVaultUnlockCallback(
    Future<void> Function(String username, String password) callback,
  ) {
    _onVaultUnlock = callback;
  }

  /// 신선 로그인 직후 볼트 키 파생을 트리거한다(있을 때만). 로그인 결과를
  /// 막지 않도록 await 하지 않으며, 실패해도 로그인 흐름에는 영향이 없다
  /// (SecureBolt 첫 진입 시 인라인 언락으로 폴백). 마스터 키 파생에는
  /// _UnlockView와 동일하게 **확정된 user.username**을 사용한다.
  void _primeVaultFromLogin(String password) {
    final cb = _onVaultUnlock;
    final username = _user?.username;
    if (cb == null || username == null || username.isEmpty || password.isEmpty) {
      return;
    }
    // fire-and-forget: 볼트 풀(pull) 실패/오프라인은 볼트 화면에서 처리한다.
    cb(username, password).catchError((_) {});
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
      ensureFreshToken: ensureFreshToken,
      isSessionExpired: () => _lastRefreshOutcome == _RefreshOutcome.expired,
      onSessionExpired: handleSessionExpired,
    );
  }

  // ── session keep-alive lifecycle (L0004 §2.5/§2.6) ───────────────────────

  /// Start proactive refresh + lifecycle-resume keep-alive. Called by the app
  /// shell once the providers are wired. Idempotent.
  void startSessionKeepAlive() {
    if (_keepAliveActive) return;
    _keepAliveActive = true;
    WidgetsBinding.instance.addObserver(this);
    _scheduleProactiveRefresh();
  }

  /// Stop proactive refresh and detach the lifecycle observer.
  void stopSessionKeepAlive() {
    if (!_keepAliveActive) return;
    _keepAliveActive = false;
    WidgetsBinding.instance.removeObserver(this);
    _cancelProactiveRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timers are throttled/parked while backgrounded or while the machine
    // sleeps; on return the token may already be (near) expired, so check now.
    // On web this also fires for tab visibility regain.
    if (state == AppLifecycleState.resumed) {
      _onResume();
    }
  }

  void _onResume() {
    if (_refreshToken == null) return;
    final expMs = _accessToken == null ? null : _decodeJwtExpMs(_accessToken!);
    if (expMs == null ||
        expMs - DateTime.now().millisecondsSinceEpoch <= nearExpiryThresholdMs) {
      // Due/expired → rotate immediately (fire-and-forget; failures recover via
      // the reactive 401 path).
      unawaited(ensureFreshToken());
    } else {
      _scheduleProactiveRefresh();
    }
  }

  @override
  void dispose() {
    if (_keepAliveActive) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _cancelProactiveRefresh();
    super.dispose();
  }

  // ── session expired text (401 refresh failed) ──────────────────────────────────────

  /// Tear the local session down and route back to login. Invoked by the shared
  /// 401 interceptor only on a genuine refresh rejection (real expiry), never on
  /// a transient network failure (L0004 §2.4).
  Future<void> handleSessionExpired() async {
    _cancelProactiveRefresh();
    _onProviderReset?.call();
    await _clearTokens();
    notifyListeners();
  }

  Future<void> _clearTokens() async {
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    _tempToken = null;
    _pendingVaultPassword = null; // SecureBolt(TR0005): never outlive a session
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
      _scheduleProactiveRefresh();
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

  // ── token refresh (3rd-gen, NR0003 F1/F2 · L0004 §2) ─────────────────────

  /// Boolean convenience wrapper around [ensureFreshToken] (kept for callers
  /// such as tryAutoLogin). Returns true iff a fresh access token is now held.
  Future<bool> refreshAccessToken() async {
    final token = await ensureFreshToken();
    return token != null;
  }

  /// Single in-flight, coalesced rotation (L0004 §2.2). All concurrent callers —
  /// both Dios' 401 handlers, the proactive timer, startup — join the same
  /// future, so the refresh token is POSTed exactly once. On success the
  /// proactive timer is re-armed off the new token.
  Future<String?> ensureFreshToken() {
    if (_loggingOut) return Future<String?>.value(null);
    _refreshFuture ??= _runRefresh().then((token) {
      if (token != null) _scheduleProactiveRefresh();
      return token;
    }).whenComplete(() {
      _refreshFuture = null;
    });
    return _refreshFuture!;
  }

  /// Perform one rotation with transient-network protection. Returns the new
  /// access token, or null on failure (inspect [_lastRefreshOutcome] to tell a
  /// real expiry — which logs out — from a transient blip — which keeps the
  /// session). Persists the rotated access AND refresh tokens atomically to both
  /// memory and storage, closing the NR0003 F1 desync.
  Future<String?> _runRefresh() async {
    final current = _refreshToken ??
        await _secureStorage.read(AppConfig.keyRefreshToken);
    if (current == null) {
      _lastRefreshOutcome = _RefreshOutcome.expired;
      return null;
    }
    var attempt = 0;
    while (true) {
      try {
        final pair = await _authService.rotateToken(current);
        // ★ NR0003 F1: in-memory refresh is replaced too, not just access.
        _accessToken = pair.accessToken;
        _refreshToken = pair.refreshToken;
        await Future.wait([
          _secureStorage.write(AppConfig.keyAccessToken, pair.accessToken),
          _secureStorage.write(AppConfig.keyRefreshToken, pair.refreshToken),
        ]);
        _lastRefreshOutcome = _RefreshOutcome.success;
        notifyListeners();
        return pair.accessToken;
      } on RefreshExpiredException {
        // Server rejected the token: real expiry/revocation/reuse.
        _lastRefreshOutcome = _RefreshOutcome.expired;
        return null;
      } on RefreshNetworkException {
        if (attempt < refreshNetworkRetry) {
          await Future<void>.delayed(Duration(
            milliseconds: refreshRetryBackoffMs[
                attempt.clamp(0, refreshRetryBackoffMs.length - 1)],
          ));
          attempt++;
          continue;
        }
        // Exhausted retries — keep the session, fail just this request.
        _lastRefreshOutcome = _RefreshOutcome.transient;
        return null;
      }
    }
  }

  /// (Re)arm the proactive pre-expiry refresh timer. No-op until keep-alive has
  /// been started by the app shell, so unit tests never spawn timers.
  void _scheduleProactiveRefresh() {
    if (!_keepAliveActive) return;
    _cancelProactiveRefresh();
    final token = _accessToken;
    if (token == null || _refreshToken == null) return;
    final expMs = _decodeJwtExpMs(token);
    if (expMs == null) return; // unparseable → rely on reactive 401 path
    final raw = expMs - DateTime.now().millisecondsSinceEpoch - refreshSkewMs;
    final delayMs = raw < minRefreshDelayMs ? minRefreshDelayMs : raw;
    _proactiveTimer = Timer(Duration(milliseconds: delayMs), () {
      _proactiveTimer = null;
      unawaited(ensureFreshToken());
    });
  }

  void _cancelProactiveRefresh() {
    _proactiveTimer?.cancel();
    _proactiveTimer = null;
  }

  /// Decode the JWT `exp` claim (seconds) to epoch ms, or null if unparseable.
  int? _decodeJwtExpMs(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final exp = json['exp'] as int?;
      return exp == null ? null : exp * 1000;
    } catch (_) {
      return null;
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
        // SecureBolt(TR0005): 세션은 verifyTotp()에서 확정되므로 그때까지만
        // 평문 비번을 보관했다가 소비·폐기한다.
        _pendingVaultPassword = password;
        _isLoading = false;
        notifyListeners();
        return LoginResult.totpRequired;
      }
      final resp = AuthLoginResponse.fromJson(data);
      await _saveSession(resp);
      // SecureBolt(TR0005): 신선 로그인 — 이 비번으로 볼트 키를 파생해 둔다
      // (두 번째 비밀번호 프롬프트 제거). _saveSession 뒤라 _user 가 확정돼 있다.
      _primeVaultFromLogin(password);
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
      // SecureBolt(TR0005): TOTP 확정 후 보관해 둔 비번으로 볼트 키 파생, 즉시 폐기.
      final pendingPw = _pendingVaultPassword;
      _pendingVaultPassword = null;
      if (pendingPw != null) {
        _primeVaultFromLogin(pendingPw);
      }
      _isLoading = false;
      notifyListeners();
    } on AuthException {
      _pendingVaultPassword = null;
      _isLoading = false;
      notifyListeners();
      rethrow;
    } catch (_) {
      _pendingVaultPassword = null;
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
    // Arm the proactive timer off the just-issued access token so a long-running
    // session rotates before expiry instead of waiting for a 401.
    _scheduleProactiveRefresh();
  }

  // ── logout ─────────────────────────────────────────────────────────────────

  /// POST /logout → local token text delete.
  Future<void> logout() async {
    _isLoading = true;
    // Suppress any concurrent rotation (e.g. a proactive timer or in-flight 401)
    // from re-issuing tokens mid-logout (L0004 §5).
    _loggingOut = true;
    _cancelProactiveRefresh();
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
    _loggingOut = false;
    notifyListeners();
  }

}


