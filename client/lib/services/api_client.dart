import 'package:dio/dio.dart';
import '../config/app_config.dart';
import 'auth_refresh_interceptor.dart';

/// Dio-based API client (storage / files / shares).
/// - attaches the Bearer token to every request
/// - on 401 triggers the provider-level coalesced refresh and retries once
/// - refresh-endpoint 401s are not retried (loop guard)
/// - a genuine refresh failure (real expiry) routes back to login
///
/// NR0003 F2 / L0004 §2.2: the per-Dio `_isRefreshing` mutex + pending queue
/// that this client used to own were removed. Rotation is now coalesced at the
/// AuthProvider level (a single in-flight future shared with MailApiClient and
/// the proactive timer), so the refresh token is never POSTed twice.
class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  /// Wire the shared auth refresh interceptor. Called once by AuthProvider.
  void configure({
    required String? Function() getAccessToken,
    required Future<String?> Function() ensureFreshToken,
    required bool Function() isSessionExpired,
    required Future<void> Function() onSessionExpired,
  }) {
    final interceptor = AuthRefreshInterceptor(
      getAccessToken: getAccessToken,
      ensureFreshToken: ensureFreshToken,
      isSessionExpired: isSessionExpired,
      onSessionExpired: onSessionExpired,
    )..dio = _dio;
    _dio.interceptors.add(interceptor);
  }

  /// Override the API base URL at runtime from a server host:port string.
  ///
  /// Normalization:
  ///   1. trim()
  ///   2. strip trailing slash
  ///   3. prepend 'http://' when no scheme is present
  ///   4. ensure the '/fileforge' path suffix
  void setBaseUrl(String hostPort) {
    final trimmed = hostPort.trim();
    if (trimmed.isEmpty) {
      _dio.options.baseUrl = AppConfig.baseUrl;
      return;
    }

    String normalized = trimmed.replaceAll(RegExp(r'/+$'), '');

    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    if (!normalized.endsWith('/fileforge')) {
      normalized = '$normalized/fileforge';
    }

    _dio.options.baseUrl = normalized;
  }

  Dio get dio => _dio;
}
