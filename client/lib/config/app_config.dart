import 'env.dart';

class AppConfig {
  /// baseUrl — SERVER_URL 환경설정값을 그대로 API 루트로 사용한다 (T077).
  /// SERVER_URL 에 컨텍스트 경로(/fileforge)까지 포함해 설정한다.
  static String get baseUrl => Env.serverUrl;

  // SecureStorage keys
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyUsername = 'username';
  static const String keyUserUuid = 'user_uuid';
}

