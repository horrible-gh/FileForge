import 'dart:async';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

/// Dio 기반 API 클라이언트.
/// - 모든 요청에 Bearer 토큰 자동 주입
/// - 401 수신 시 refresh 요청 → 성공이면 원래 요청 재시도
/// - refresh 중 중복 401은 대기열로 처리
/// - refresh 실패 시 onSessionExpired 콜백 호출
class ApiClient {
  late final Dio _dio;

  String? Function()? _getAccessToken;
  Future<bool> Function()? _onRefreshToken;
  Future<void> Function()? _onSessionExpired;

  bool _isRefreshing = false;
  final List<Completer<String?>> _pendingRequests = [];

  ApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _setupInterceptors();
  }

  /// AuthProvider에서 콜백을 등록한다.
  void configure({
    required String? Function() getAccessToken,
    required Future<bool> Function() onRefreshToken,
    required Future<void> Function() onSessionExpired,
  }) {
    _getAccessToken = getAccessToken;
    _onRefreshToken = onRefreshToken;
    _onSessionExpired = onSessionExpired;
  }

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _getAccessToken?.call();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode != 401) {
            handler.next(error);
            return;
          }

          // refresh 엔드포인트 자체의 401은 재시도하지 않는다.
          final isRefreshEndpoint =
              error.requestOptions.path.contains('/login/refresh');
          if (isRefreshEndpoint) {
            handler.next(error);
            return;
          }

          // refresh 중 중복 401 → 대기열에 추가
          if (_isRefreshing) {
            final completer = Completer<String?>();
            _pendingRequests.add(completer);
            try {
              final newToken = await completer.future;
              if (newToken != null) {
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Bearer $newToken';
                final response = await _dio.fetch(opts);
                handler.resolve(response);
              } else {
                handler.next(error);
              }
            } catch (_) {
              handler.next(error);
            }
            return;
          }

          _isRefreshing = true;
          try {
            final success =
                await (_onRefreshToken?.call() ?? Future.value(false));
            if (success) {
              final newToken = _getAccessToken?.call();
              for (final c in _pendingRequests) {
                c.complete(newToken);
              }
              _pendingRequests.clear();

              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer $newToken';
              final response = await _dio.fetch(opts);
              handler.resolve(response);
            } else {
              for (final c in _pendingRequests) {
                c.complete(null);
              }
              _pendingRequests.clear();
              await _onSessionExpired?.call();
              handler.next(error);
            }
          } catch (e) {
            for (final c in _pendingRequests) {
              c.complete(null);
            }
            _pendingRequests.clear();
            await _onSessionExpired?.call();
            handler.next(error);
          } finally {
            _isRefreshing = false;
          }
        },
      ),
    );
  }

  /// 서버 주소 문자열을 받아 baseUrl을 동적으로 업데이트한다.
  ///
  /// 처리 순서:
  ///   1. trim()
  ///   2. trailing slash 제거
  ///   3. scheme 없으면 'http://' 추가
  ///   4. 이미 '/fileforge'로 끝나면 그대로, 아니면 '/fileforge' 추가
  void setBaseUrl(String hostPort) {
    final trimmed = hostPort.trim();
    if (trimmed.isEmpty) {
      _dio.options.baseUrl = AppConfig.baseUrl;
      return;
    }

    // trailing slash 제거
    String normalized = trimmed.replaceAll(RegExp(r'/+$'), '');

    // scheme 없으면 http:// 추가
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    // /fileforge 경로 추가 (중복 방지)
    if (!normalized.endsWith('/fileforge')) {
      normalized = '$normalized/fileforge';
    }

    _dio.options.baseUrl = normalized;
  }

  Dio get dio => _dio;
}
