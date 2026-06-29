import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/auth_exception.dart';

/// A rotated access+refresh token pair returned by POST /login/refresh.
/// The server rotates the refresh token on every call (login.py:159-203), so a
/// successful rotation always yields BOTH a new access and a new refresh token;
/// the caller must persist both atomically (NR0003 F1 / L0004 §2.1).
class TokenPair {
  final String accessToken;
  final String refreshToken;
  const TokenPair(this.accessToken, this.refreshToken);
}

/// The server rejected the refresh token (HTTP 401): it is expired, revoked, or
/// was already rotated (reuse). This is the only failure that ends the session.
class RefreshExpiredException implements Exception {
  const RefreshExpiredException();
}

/// The rotation could not reach a verdict from the server (timeout, connection
/// failure, 5xx). The session is kept alive and the next trigger retries
/// (L0004 §2.4 transient protection).
class RefreshNetworkException implements Exception {
  const RefreshNetworkException();
}

/// login success text text
class AuthLoginResponse {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final User user;

  AuthLoginResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.user,
  });

  factory AuthLoginResponse.fromJson(Map<String, dynamic> json) {
    return AuthLoginResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      tokenType: json['token_type'] as String? ?? 'bearer',
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

/// authentication text API text text
/// endpointstext server routers/login/login.py, logout.py text
class AuthService {
  final Dio _dio;

  AuthService(this._dio);

  /// DioExceptiontext response bodytext detail stringtext translated text.
  String _extractDetail(DioException e) {
    try {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        return data['detail'] as String? ?? 'unknown_error';
      }
    } catch (_) {}
    return 'unknown_error';
  }

  /// POST /login
  /// Content-Type: application/x-www-form-urlencoded
  /// return: {access_token, refresh_token, ...} text {totp_required, temp_token}
  /// failed: AuthException(detail)
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await _dio.post(
        '/login',
        data: {'username': username, 'password': password},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final detail = _extractDetail(e);
      debugPrint(
        '[B004][AuthService.login] DioException '
        'status=${e.response?.statusCode} '
        'detail=$detail '
        'data=${e.response?.data}',
      );
      throw AuthException(detail);
    }
  }

  /// POST /login/totp/verify
  /// Body: {temp_token, code}
  /// failed: AuthException('invalid_code') text AuthException('token_expired')
  Future<AuthLoginResponse> verifyTotp(String tempToken, String code) async {
    try {
      final response = await _dio.post(
        '/login/totp/verify',
        data: {'temp_token': tempToken, 'code': code},
      );
      return AuthLoginResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      final detail = _extractDetail(e);
      debugPrint(
        '[B004][AuthService.login] DioException '
        'status=${e.response?.statusCode} '
        'detail=$detail '
        'data=${e.response?.data}',
      );
      throw AuthException(detail);
    }
  }

  /// POST /login/refresh
  /// Body: {refresh_token}
  /// Returns the rotated access+refresh pair. Persistence is the caller's job
  /// (AuthProvider writes both in-memory and SecureStorage atomically) so the
  /// in-memory refresh token can never drift from storage — the desync that was
  /// NR0003 F1.
  ///
  /// Throws [RefreshExpiredException] on HTTP 401 (real expiry/revocation) and
  /// [RefreshNetworkException] on any other failure (timeout/connection/5xx),
  /// letting the caller keep the session alive on a transient blip (L0004 §2.4).
  Future<TokenPair> rotateToken(String refreshToken) async {
    try {
      final response = await _dio.post(
        '/login/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = response.data as Map<String, dynamic>;
      final newAccessToken = data['access_token'] as String;
      // Server always rotates; fall back to the sent token only defensively.
      final newRefreshToken =
          data['refresh_token'] as String? ?? refreshToken;
      return TokenPair(newAccessToken, newRefreshToken);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const RefreshExpiredException();
      }
      // No response (timeout/connection) or a non-401 status (e.g. 5xx) →
      // transient: do not log the user out over a blip.
      throw const RefreshNetworkException();
    }
  }

  /// POST /logout
  /// Authorization: Bearer {access_token}
  /// Body: {refresh_token}
  Future<void> logout(String refreshToken) async {
    await _dio.post(
      '/logout',
      data: {'refresh_token': refreshToken},
    );
  }
}



