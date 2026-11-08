import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../utils/mail_html_document.dart';
import '../utils/mail_link_launcher.dart';

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
      ..style.cssText = 'display:block;width:100%;height:100%;border:0;'
          'background:white;color-scheme:light;';
    _watchdog = Timer(const Duration(seconds: 12), _fail);
    frame.srcdoc = _document.html.toJS;
  }

  void _receive(web.MessageEvent event) {
    if (!mounted || _failed || _frame == null) return;
    if (event.source != _frame!.contentWindow || event.origin != 'null') return;
    final data = event.data.dartify();
    if (data is! Map ||
        data['channel'] != 'fileforge-mail' ||
        data['token'] != _document.token) {
      return;
    }
    switch (data['kind']) {
      case 'ready':
        _watchdog?.cancel();
        break;
      case 'height':
        final heightValue = data['value'];
        if (heightValue is num && heightValue.isFinite) {
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
    // Flutter dialog painted above them. Restore input even after cancellation.
    _frame?.style.pointerEvents = 'none';
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
