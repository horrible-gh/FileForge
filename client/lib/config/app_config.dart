import 'env.dart';

class AppConfig {
  /// baseUrl — SERVER_URL translated text as-is API translated text uses (T077).
  /// SERVER_URL text translated text path(/fileforge)text translated text translated text.
  static String get baseUrl => Env.serverUrl;

  /// MailAnchor(Go) API base URL — NR0003 §3.3. text text text Diotext uses.
  static String get mailBaseUrl => Env.mailServerUrl;

  // SecureStorage keys
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyUsername = 'username';
  static const String keyUserUuid = 'user_uuid';
}

