import 'dart:async';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

/// Dio text API translated text.
/// - all translated text Bearer token text text
/// - 401 text text refresh text → successtext text text retry
/// - refresh text text 401text translated text text
/// - refresh failed text onSessionExpired text text
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

  /// AuthProvidertext translated text registertext.
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

          // refresh endpoints translated text 401text retrytext translated text.
          final isRefreshEndpoint =
              error.requestOptions.path.contains('/login/refresh');
          if (isRefreshEndpoint) {
            handler.next(error);
            return;
          }

          // refresh text text 401 → translated text add
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

  /// server text stringtext text baseUrltext translated text translated text.
  ///
  /// text text:
  ///   1. trim()
  ///   2. trailing slash text
  ///   3. scheme translated text 'http://' add
  ///   4. text '/fileforge'text translated text as-is, translated text '/fileforge' add
  void setBaseUrl(String hostPort) {
    final trimmed = hostPort.trim();
    if (trimmed.isEmpty) {
      _dio.options.baseUrl = AppConfig.baseUrl;
      return;
    }

    // trailing slash text
    String normalized = trimmed.replaceAll(RegExp(r'/+$'), '');

    // scheme translated text http:// add
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    // /fileforge path add (text text)
    if (!normalized.endsWith('/fileforge')) {
      normalized = '$normalized/fileforge';
    }

    _dio.options.baseUrl = normalized;
  }

  Dio get dio => _dio;
}
