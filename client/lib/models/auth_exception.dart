/// 인증 관련 서버 에러를 detail 문자열로 전달하는 예외.
/// P002 프로토콜 기준 detail 값:
///   - 'Invalid credentials'  : ID/PW 불일치
///   - 'invalid_code'         : TOTP 코드 오류
///   - 'token_expired'        : TOTP temp_token 또는 refresh_token 만료
class AuthException implements Exception {
  final String detail;

  const AuthException(this.detail);

  @override
  String toString() => 'AuthException: $detail';
}
