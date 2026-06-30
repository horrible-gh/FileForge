import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Inbound deep-link (custom scheme) receiver service — R0001/NR0003/T0004 §Option C.
///
/// When the OAuth success page (server `_oauth_result_page`) auto-redirects to
/// `fileforge://oauth/gmail/success`, the mobile OS leaves the external browser,
/// brings this app to the foreground and delivers that URI. At that point
/// [onOAuthSuccess] is invoked so the app reloads its account list (= detects the
/// connection). This spares the user from manually closing the browser and
/// switching back to the app (resolving the mobile annoyance).
///
/// Handles both cold start (app was dead and is launched by the deep link) and
/// warm resume (already running).
class DeepLinkService {
  DeepLinkService({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  /// Callback invoked when an OAuth (gmail) connection-success deep link arrives.
  VoidCallback? onOAuthSuccess;

  /// Starts receiving deep links. Duplicate calls are ignored.
  Future<void> init() async {
    // Web is not a custom-scheme deep-link target (web uses the server redirect path).
    if (kIsWeb) return;
    if (_sub != null) return;

    try {
      // Cold start: handle the initial link that woke the app.
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {
      // May be unsupported on some platforms/configs, but does not affect app behavior.
    }

    try {
      // Warm resume: stream of links received while running.
      _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
    } catch (_) {
      // Ignore — deep links are a secondary path, and a manual-refresh fallback always exists.
    }
  }

  void _handle(Uri uri) {
    if (isOAuthSuccessUri(uri)) {
      onOAuthSuccess?.call();
    }
  }

  /// Identifies the `fileforge://oauth/gmail/success` form.
  /// A custom-scheme URI parses with host 'oauth' and path '/gmail/success'.
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
