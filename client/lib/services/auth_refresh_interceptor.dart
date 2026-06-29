import 'package:dio/dio.dart';

/// Shared 401 → refresh interceptor for every authenticated Dio in the app
/// (ApiClient + MailApiClient).
///
/// NR0003 F2 / L0004 §2.2-2.4: each Dio used to keep its own `_isRefreshing`
/// mutex and pending-request queue, so when the file Dio and the mail Dio both
/// received a 401 right after expiry they rotated the refresh token concurrently
/// — the server retired the token on the first call and rejected the second,
/// tearing the whole session down. Instead, **all** clients funnel through a
/// single coalesced [ensureFreshToken] on the AuthProvider, so the refresh token
/// is POSTed at most once regardless of how many Dios 401 at the same instant.
///
/// The interceptor also enforces the "only a real server rejection logs you out"
/// rule (L0004 §2.4): when [ensureFreshToken] returns null it consults
/// [isSessionExpired]; a transient network failure keeps the session alive and
/// merely fails the one request.
class AuthRefreshInterceptor extends Interceptor {
  AuthRefreshInterceptor({
    required this.getAccessToken,
    required this.ensureFreshToken,
    required this.isSessionExpired,
    required this.onSessionExpired,
  });

  /// Current in-memory access token (null when unauthenticated).
  final String? Function() getAccessToken;

  /// Provider-level, coalesced rotation. Returns the new access token on
  /// success, or null when the rotation failed (see [isSessionExpired] to tell
  /// a real expiry apart from a transient blip).
  final Future<String?> Function() ensureFreshToken;

  /// True iff the last rotation failed because the server rejected the refresh
  /// token (HTTP 401) — i.e. a genuine expiry/revocation. False for transient
  /// network errors.
  final bool Function() isSessionExpired;

  /// Tear the local session down and route back to login.
  final Future<void> Function() onSessionExpired;

  /// Set by the owning client right after its Dio is constructed; used to
  /// replay the original request once with the rotated token.
  late final Dio dio;

  /// Per-request marker so a request is retried at most once (L0004 §2.3).
  static const String retriedKey = '__ff_auth_retried__';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // The refresh call itself returning 401 means the refresh token is dead —
    // never recurse into another refresh (loop guard, L0004 §2.3).
    if (err.requestOptions.path.contains('/login/refresh')) {
      handler.next(err);
      return;
    }

    // One retry per request: mark BEFORE retrying so a still-401 response (e.g.
    // a token rejected mid-flight) cannot spin into an infinite refresh loop.
    if (err.requestOptions.extra[retriedKey] == true) {
      handler.next(err);
      return;
    }
    err.requestOptions.extra[retriedKey] = true;

    final newToken = await ensureFreshToken();
    if (newToken == null) {
      // Only a genuine 401 ends the session; a transient network failure keeps
      // it and just fails this one request (L0004 §2.4 / §5 transient guard).
      if (isSessionExpired()) {
        await onSessionExpired();
      }
      handler.next(err);
      return;
    }

    try {
      final opts = err.requestOptions;
      opts.headers['Authorization'] = 'Bearer $newToken';
      final response = await dio.fetch(opts);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    } catch (_) {
      handler.next(err);
    }
  }
}
