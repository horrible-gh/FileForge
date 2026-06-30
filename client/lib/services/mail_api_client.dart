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

  /// Applies the runtime server-address override to the mail Dio (B0001 / NR0003 §3·§6).
  ///
  /// Prior defect: when the user changed the server address on the settings
  /// screen, only the file API Dio (`ApiClient.setBaseUrl`) followed it, while the
  /// mail Dio stayed permanently pinned to the build-baked
  /// `AppConfig.mailBaseUrl` (default localhost), so mail/account requests went to
  /// the wrong server and "connect Google" appeared. This method makes the mail
  /// base follow the **same origin** as the file base (`.../fileforge/mail`).
  ///
  /// Normalization (same input contract as the file [ApiClient.setBaseUrl]):
  ///   1. trim() — an empty value reverts to the build default
  ///   2. strip trailing slashes
  ///   3. add 'http://' if no scheme
  ///   4. if it ends with `/fileforge/mail` keep as-is; if `/fileforge` append `/mail`;
  ///      otherwise (host:port) append `/fileforge/mail`
  void setBaseUrl(String hostPort) {
    final trimmed = hostPort.trim();
    if (trimmed.isEmpty) {
      _dio.options.baseUrl = AppConfig.mailBaseUrl;
      return;
    }

    String normalized = trimmed.replaceAll(RegExp(r'/+$'), '');

    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    if (normalized.endsWith('/fileforge/mail')) {
      // Already a mail path — use as-is.
    } else if (normalized.endsWith('/fileforge')) {
      normalized = '$normalized/mail';
    } else {
      normalized = '$normalized/fileforge/mail';
    }

    _dio.options.baseUrl = normalized;
  }

  Dio get dio => _dio;
}
