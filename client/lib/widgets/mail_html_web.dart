import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../utils/mail_html_document.dart';
import '../utils/mail_link_launcher.dart';

// MessageEvent.source can be a cross-origin WindowProxy. Keep it as JSAny?
// all the way to the JavaScript identity comparison. Dart runtime checks on a
// Window/JSObject (including ordinary Dart ==) can read forbidden properties
// on that proxy and throw SecurityError before ready/height is processed.
extension type _OpaqueMessageEvent(JSObject _) implements JSObject {
  @JS('source')
  external JSAny? get sourceWindow;
}

/// Opaque-origin iframe. Deliberately NEVER combine allow-scripts with
/// allow-same-origin: mail cannot read the app DOM, cookies or storage.
class MailHtmlView extends StatefulWidget {
  const MailHtmlView({
    super.key,
    required this.html,
    required this.fallbackBuilder,
  });

  final String html;
  final WidgetBuilder fallbackBuilder;

  @override
  State<MailHtmlView> createState() => _MailHtmlViewState();
}

class _MailHtmlViewState extends State<MailHtmlView>
    with AutomaticKeepAliveClientMixin {
  late final MailHtmlDocument _document;
  late final JSFunction _listener;
  web.HTMLIFrameElement? _frame;
  Timer? _watchdog;
  double _height = 320;
  bool _failed = false;
  bool _openingLink = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _document = MailHtmlDocument(widget.html);
    _listener = ((web.Event event) => _receive(event as web.MessageEvent)).toJS;
    web.window.addEventListener('message', _listener);
  }

  void _created(Object element) {
    final frame = element as web.HTMLIFrameElement;
    _frame = frame;
    frame
      ..setAttribute('sandbox', 'allow-scripts')
      ..setAttribute('referrerpolicy', 'no-referrer')
      ..setAttribute('allow', "camera 'none'; microphone 'none'; geolocation 'none'; payment 'none'")
      ..setAttribute('title', 'HTML email')
      ..setAttribute('data-fileforge-mail-state', 'starting')
      ..style.cssText = 'display:block;width:100%;height:100%;border:0;'
          'background:white;color-scheme:light;';
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 12), _fail);
    frame.srcdoc = _document.html.toJS;
  }

  void _acknowledgeBrowser() {
    _watchdog?.cancel();
    _watchdog = null;
    _frame?.setAttribute('data-fileforge-mail-state', 'ready');
  }

  void _receive(web.MessageEvent event) {
    final frame = _frame;
    if (!mounted || _failed || frame == null || event.origin != 'null') return;

    // Use package:web's cross-origin-safe accessor, not frame.contentWindow.
    // The source check is still mandatory: a sibling opaque-origin frame must
    // NOT be able to resize this mail or open a link, even with a copied token.
    final expectedSource = frame.contentWindowCrossOrigin;
    if (expectedSource == null ||
        !_OpaqueMessageEvent(event)
            .sourceWindow
            .strictEquals(expectedSource.unsafeWindow)
            .toDart) {
      return;
    }

    final Object? data;
    try {
      data = event.data.dartify();
    } catch (_) {
      return; // A malformed message is not a renderer failure.
    }
    if (data is! Map ||
        data['channel'] != 'fileforge-mail' ||
        data['token'] != _document.token) {
      return;
    }
    switch (data['kind']) {
      case 'ready':
        if (data['value'] == true) _acknowledgeBrowser();
        break;
      case 'height':
        final heightValue = data['value'];
        if (heightValue is num && heightValue.isFinite && heightValue > 0) {
          // A valid measured height also proves the authenticated bootstrap is
          // alive. Do not replace a working browser if an earlier ready event
          // was missed during mounting.
          _acknowledgeBrowser();
          final next = heightValue.toDouble().clamp(48.0, mailHtmlMaxHeight).toDouble();
          if ((next - _height).abs() > 1) setState(() => _height = next);
        }
        break;
      case 'scroll':
        final scrollValue = data['value'];
        if (!_openingLink && scrollValue is num && scrollValue.isFinite) {
          Scrollable.maybeOf(context)?.position.pointerScroll(
            scrollValue.toDouble().clamp(-1500.0, 1500.0).toDouble(),
          );
        }
        break;
      case 'link':
        final linkValue = data['value'];
        if (linkValue is String) unawaited(_openLink(linkValue));
        break;
      case 'error':
        _fail();
        break;
    }
  }

  Future<void> _openLink(String url) async {
    if (_openingLink || !isOpenableMailLink(url)) return;
    _openingLink = true;
    // HTML platform views otherwise swallow pointer events intended for a
    // Flutter dialog painted above them. Pointer-events alone does NOT move
    // keyboard focus out of the iframe: Escape/Tab would still go to the mail.
    // Blur the parent-owned element (no cross-origin DOM access) before the
    // Flutter dialog requests focus. Restore input even after cancellation.
    _frame?.style.pointerEvents = 'none';
    _frame?.blur();
    web.window.focus();
    try {
      await confirmAndOpenMailLink(context, url);
    } finally {
      _openingLink = false;
      if (mounted) _frame?.style.pointerEvents = '';
    }
  }

  void _fail() {
    _watchdog?.cancel();
    if (!mounted || _failed) return;
    _frame?.srcdoc = ''.toJS;
    setState(() => _failed = true);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    web.window.removeEventListener('message', _listener);
    _frame?.srcdoc = ''.toJS;
    _frame = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_failed) return widget.fallbackBuilder(context);
    return ColoredBox(
      color: Colors.white,
      child: SizedBox(
        width: double.infinity,
        height: _height,
        child: HtmlElementView.fromTagName(
          tagName: 'iframe',
          onElementCreated: _created,
        ),
      ),
    );
  }
}
