import 'dart:async';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

/// MailAnchor(Go 서비스) 전용 Dio 클라이언트 — NR0003 §1/§3.3.
///
/// 흡수 아키텍처에서 메일은 FileForge 세션을 그대로 탄다(별도 로그인 없음).
/// 따라서 본 클라이언트는 토큰을 **발급하지 않고**, FileForge AuthProvider가
/// 보유한 access token을 주입하고, 401이면 동일 AuthProvider의 리프레시를
/// 트리거한 뒤 원요청을 재시도한다(L0010 §2.2 사후 리프레시 + 단일비행).
class MailApiClient {
  late final Dio _dio;

  String? Function()? _getAccessToken;
  Future<bool> Function()? _onRefreshToken;
  Future<void> Function()? _onSessionExpired;

  bool _isRefreshing = false;
  final List<Completer<String?>> _pendingRequests = [];

  MailApiClient() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.mailBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _setupInterceptors();
  }

  /// AuthProvider의 토큰 접근자/리프레시/세션만료 콜백을 등록한다.
  /// 리프레시는 FileForge dio에서 수행되며, 새 access token이 여기로 공유된다.
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

          // 리프레시 진행 중이면 대기열에 합류(단일비행).
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
          } catch (_) {
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

  Dio get dio => _dio;
}
