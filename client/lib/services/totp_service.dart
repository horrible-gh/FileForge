import 'package:dio/dio.dart';
import '../models/auth_exception.dart';

class TotpSetupResponse {
  final String qrImage;
  final List<String> recoveryCodes;

  TotpSetupResponse({
    required this.qrImage,
    required this.recoveryCodes,
  });

  factory TotpSetupResponse.fromJson(Map<String, dynamic> json) {
    final rawCodes = json['recovery_codes'] as List<dynamic>? ?? const [];
    return TotpSetupResponse(
      qrImage: json['qr_image'] as String? ?? '',
      recoveryCodes: rawCodes.map((code) => code.toString()).toList(),
    );
  }
}

class TotpService {
  final Dio _dio;

  TotpService(this._dio);

  String _extractDetail(DioException e) {
    try {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        return data['detail'] as String? ?? 'unknown_error';
      }
    } catch (_) {}
    return 'unknown_error';
  }

  Never _handleAndThrow(DioException e) {
    final statusCode = e.response?.statusCode;
    final detail = _extractDetail(e);

    if (statusCode == 400 && detail == 'invalid_code') {
      throw AuthException(detail);
    }

    if (statusCode == 500) {
      throw AuthException(detail);
    }

    throw e;
  }

  Future<bool> getStatus() async {
    try {
      final response = await _dio.get('/auth/totp/status');
      final data = response.data as Map<String, dynamic>;
      return data['enabled'] == true;
    } on DioException catch (e) {
      _handleAndThrow(e);
    }
  }

  Future<TotpSetupResponse> setup() async {
    try {
      final response = await _dio.post('/auth/totp/setup');
      return TotpSetupResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _handleAndThrow(e);
    }
  }

  Future<bool> activate(String code) async {
    try {
      final response = await _dio.post(
        '/auth/totp/activate',
        data: {'code': code},
      );
      final data = response.data as Map<String, dynamic>;
      return data['success'] == true;
    } on DioException catch (e) {
      _handleAndThrow(e);
    }
  }

  Future<bool> disable(String code) async {
    try {
      final response = await _dio.post(
        '/auth/totp/disable',
        data: {'code': code},
      );
      final data = response.data as Map<String, dynamic>;
      return data['success'] == true;
    } on DioException catch (e) {
      _handleAndThrow(e);
    }
  }

  Future<List<String>> regenerate(String code) async {
    try {
      final response = await _dio.post(
        '/auth/totp/regenerate',
        data: {'code': code},
      );
      final data = response.data as Map<String, dynamic>;
      final rawCodes = data['recovery_codes'] as List<dynamic>? ?? const [];
      return rawCodes.map((code) => code.toString()).toList();
    } on DioException catch (e) {
      _handleAndThrow(e);
    }
  }
}
