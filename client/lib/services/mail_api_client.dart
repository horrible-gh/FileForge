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

  /// 런타임 서버 주소 오버라이드를 메일 Dio에 반영한다 (B0001 / NR0003 §3·§6).
  ///
  /// 기존 결함: 사용자가 설정 화면에서 서버 주소를 바꾸면 파일 API Dio
  /// (`ApiClient.setBaseUrl`)만 따라가고, 메일 Dio는 빌드에 박힌
  /// `AppConfig.mailBaseUrl`(기본 localhost)에 영구히 고정돼 메일/계정 요청이
  /// 엉뚱한 서버로 가서 "구글 연동하라"가 떴다. 이 메서드로 메일 base도 파일
  /// base와 **같은 origin**(`.../fileforge/mail`)을 따라가게 한다.
  ///
  /// 정규화(파일 [ApiClient.setBaseUrl]와 동일 입력 규약):
  ///   1. trim() — 빈 값이면 빌드 기본값으로 복귀
  ///   2. trailing slash 제거
  ///   3. scheme 없으면 'http://' 추가
  ///   4. 끝이 `/fileforge/mail`이면 그대로, `/fileforge`면 `/mail` 추가,
  ///      그 외(host:port)면 `/fileforge/mail` 추가
  void setBaseUrl(String hostPort) {
    final trimmed = hostPort.trim();
    if (trimmed.isEmpty) {
      _dio.options.baseUrl = AppConfig.mailBaseUrl;
      return;
    }

    String normalized = trimmed.replaceAll(RegExp(r'/+$'), '');

    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    if (normalized.endsWith('/fileforge/mail')) {
      // 이미 메일 경로 — 그대로 사용.
    } else if (normalized.endsWith('/fileforge')) {
      normalized = '$normalized/mail';
    } else {
      normalized = '$normalized/fileforge/mail';
    }

    _dio.options.baseUrl = normalized;
  }

  Dio get dio => _dio;
}
