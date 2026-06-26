import 'dart:async';
import 'package:dio/dio.dart';
import '../config/app_config.dart';

/// MailAnchor(Go translated text) text Dio translated text — NR0003 §1/§3.3.
///
/// merge translated text translated text FileForge sessiontext as-is text(text login None).
/// translated text text translated text tokentext **issuetext text**, FileForge AuthProvidertext
/// translated text access tokentext translated text, 401text text AuthProvidertext translated text
/// translated text text translated text retrytext(L0010 §2.2 text translated text + translated text).
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

  /// AuthProvidertext token translated text/translated text/sessionexpired translated text registertext.
  /// translated text FileForge diotext translated text, text access tokentext translated text translated text.
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

          // translated text text translated text translated text text(translated text).
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
