import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// 인바운드 딥링크(custom scheme) 수신 서비스 — R0001/NR0003/T0004 §Option C.
///
/// OAuth 성공 페이지(server `_oauth_result_page`)가 `fileforge://oauth/gmail/success`
/// 로 자동 리다이렉트하면, 모바일 OS 가 외부 브라우저를 떠나 이 앱을 foreground 로
/// 올리고 해당 URI 를 전달한다. 그 시점에 [onOAuthSuccess] 를 호출해 앱이 계정 목록을
/// 재로딩(=연결 감지)하도록 한다. 이로써 사용자가 브라우저를 수동으로 닫고 앱을 다시
/// 찾아 전환할 필요가 없어진다(모바일 불편 해소).
///
/// 콜드 스타트(앱이 죽어 있다가 딥링크로 기동)와 웜 리줌(이미 실행 중) 양쪽을 처리한다.
class DeepLinkService {
  DeepLinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  /// OAuth(gmail) 연동 성공 딥링크를 수신했을 때 호출되는 콜백.
  VoidCallback? onOAuthSuccess;

  /// 딥링크 수신을 시작한다. 중복 호출은 무시된다.
  Future<void> init() async {
    // 웹은 custom scheme 딥링크 대상이 아니다(웹은 서버 redirect 경로 사용).
    if (kIsWeb) return;
    if (_sub != null) return;

    try {
      // 콜드 스타트: 앱을 깨운 최초 링크 처리.
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {
      // 일부 플랫폼/구성에서 미지원일 수 있으나 앱 동작에는 영향 없음.
    }

    try {
      // 웜 리줌: 실행 중 수신되는 링크 스트림.
      _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
    } catch (_) {
      // 무시 — 딥링크는 보조 경로이며, 수동 새로고침 폴백이 항상 존재한다.
    }
  }

  void _handle(Uri uri) {
    if (isOAuthSuccessUri(uri)) {
      onOAuthSuccess?.call();
    }
  }

  /// `fileforge://oauth/gmail/success` 형태를 식별한다.
  /// custom scheme URI 는 host 가 'oauth', path 가 '/gmail/success' 로 파싱된다.
  @visibleForTesting
  static bool isOAuthSuccessUri(Uri uri) {
    if (uri.scheme != 'fileforge') return false;
    final segments = [uri.host, ...uri.pathSegments]
        .where((s) => s.isNotEmpty)
        .toList();
    return segments.length >= 3 &&
        segments[0] == 'oauth' &&
        segments[1] == 'gmail' &&
        segments[2] == 'success';
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
