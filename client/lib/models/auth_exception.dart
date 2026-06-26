/// authentication text server errortext detail stringtext translated text exampletext.
/// P002 translated text text detail text:
///   - 'Invalid credentials'  : ID/PW translated text
///   - 'invalid_code'         : TOTP text error
///   - 'token_expired'        : TOTP temp_token text refresh_token expired
class AuthException implements Exception {
  final String detail;

  const AuthException(this.detail);

  @override
  String toString() => 'AuthException: $detail';
}
