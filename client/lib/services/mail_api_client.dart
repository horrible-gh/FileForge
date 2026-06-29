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

  /// 런타임 서버 주소 오버라이드를 메일 Dio에 반영한다 (B0001 / NR0003 §3·§6).
  ///
  /// 기존 결함: 사용자가 설정 화면에서 서버 주소를 바꾸면 파일 API Dio
  /// (`ApiClient.setBaseUrl`)만 따라가고, 메일 Dio는 빌드에 박힌
  /// `AppConfig.mailBaseUrl`(기본 localhost)에 영구히 고정돼 메일/계정 요청이
  /// 엉뚱한 서버로 가서 "구글 연동하라"가 떴다. 이 메서드로 메일 base도 파일
  /// base와 **같은 origin**(`.../fileforge/mail`)을 따라가게 한다.
  ///
  /// 정규화(파일 [ApiClient.setBaseUrl]와 동일 입력 규약):
  ///   1. trim() — 빈 값이면 빌드 기본값으로 복귀
  ///   2. trailing slash 제거
  ///   3. scheme 없으면 'http://' 추가
  ///   4. 끝이 `/fileforge/mail`이면 그대로, `/fileforge`면 `/mail` 추가,
  ///      그 외(host:port)면 `/fileforge/mail` 추가
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
      // 이미 메일 경로 — 그대로 사용.
    } else if (normalized.endsWith('/fileforge')) {
      normalized = '$normalized/mail';
    } else {
      normalized = '$normalized/fileforge/mail';
    }

    _dio.options.baseUrl = normalized;
  }

  Dio get dio => _dio;
}
