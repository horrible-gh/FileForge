import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/user.dart';
import '../models/auth_exception.dart';
import '../utils/secure_storage.dart';

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
  /// return: text access_token (text refresh_tokentext SecureStoragetext save)
  Future<String> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      '/login/refresh',
      data: {'refresh_token': refreshToken},
    );
    final data = response.data as Map<String, dynamic>;
    final newAccessToken = data['access_token'] as String;
    final newRefreshToken = data['refresh_token'] as String?;
    if (newRefreshToken != null) {
      await SecureStorage().write(AppConfig.keyRefreshToken, newRefreshToken);
    }
    return newAccessToken;
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



