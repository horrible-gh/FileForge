import 'package:dio/dio.dart';
import '../config/app_config.dart';
import 'auth_refresh_interceptor.dart';

/// Separate Dio for the MailAnchor (Go) server — NR0003 §1/§3.3.
///
/// MailAnchor reuses the FileForge session unchanged (no separate login). It
/// never mints its own token: it carries FileForge's access token, and on 401
/// it triggers the **same provider-level coalesced refresh** as the file Dio,
/// then retries (L0004 §2.2). Sharing one in-flight rotation is what fixes the
/// dual-Dio concurrent-refresh race (NR0003 F2) that made the mail server
/// "loosen" the session and force re-login.
class MailApiClient {
  late final Dio _dio;

  MailApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.mailBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  /// Wire the shared auth refresh interceptor (same coalesced rotation as
  /// ApiClient). Called once by App from app.dart.
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

  Dio get dio => _dio;
}
