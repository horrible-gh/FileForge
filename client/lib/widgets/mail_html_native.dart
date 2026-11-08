import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/mail_html_document.dart';
import '../utils/mail_link_launcher.dart';

Future<WebViewEnvironment>? _windowsEnvironment;

Future<WebViewEnvironment> _createWindowsEnvironment() async {
  final version = await WebViewEnvironment.getAvailableVersion();
  if (version == null) throw StateError('WebView2 runtime is unavailable');
  final support = await getApplicationSupportDirectory();
  final directory = Directory('${support.path}${Platform.pathSeparator}mail-webview');
  await directory.create(recursive: true);
  // Never write a WebView2 profile next to the executable (Program Files is
  // commonly read-only). This environment is shared for the app lifetime.
  return WebViewEnvironment.create(
    settings: WebViewEnvironmentSettings(userDataFolder: directory.path),
  );
}

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
  WebViewEnvironment? _environment;
  Timer? _watchdog;
  bool _initialized = false;
  bool _failed = false;
  bool _openingLink = false;
  double _height = 320;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _document = MailHtmlDocument(widget.html);
    // flutter_inappwebview 6.1.5 has no Linux/Fuchsia implementation. A null
    // platform also covers ordinary Flutter widget tests without native plugins.
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.fuchsia ||
        InAppWebViewPlatform.instance == null) {
      _failed = true;
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      unawaited(_initializeWindows());
    } else {
      _initialized = true;
    }
  }

  Future<void> _initializeWindows() async {
    try {
      final environment = await (_windowsEnvironment ??= _createWindowsEnvironment());
      if (!mounted) return;
      setState(() {
        _environment = environment;
        _initialized = true;
      });
    } catch (error) {
      _windowsEnvironment = null;
      debugPrint('Mail HTML browser unavailable: $error');
      _fail();
    }
  }

  void _fail() {
    _watchdog?.cancel();
    if (mounted && !_failed) setState(() => _failed = true);
  }

  void _receive(dynamic data) {
    if (!mounted || _failed || data is! Map ||
        data['channel'] != 'fileforge-mail' ||
        data['token'] != _document.token) return;
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
    setState(() => _openingLink = true);
    try {
      await confirmAndOpenMailLink(context, url);
    } finally {
      if (mounted) setState(() => _openingLink = false);
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_failed) return widget.fallbackBuilder(context);
    if (!_initialized) {
      return const SizedBox(height: 320, child: Center(child: CircularProgressIndicator()));
    }
    return ColoredBox(
      color: Colors.white,
      child: SizedBox(
        height: _height,
        width: double.infinity,
        child: IgnorePointer(
          ignoring: _openingLink,
          child: InAppWebView(
            // Let the browser own selection and inner scrolling. The trusted
            // bootstrap forwards boundary scrolls to the outer Flutter list.
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
            },
            webViewEnvironment: _environment,
            initialData: InAppWebViewInitialData(
              data: _document.html,
              mimeType: 'text/html',
              encoding: 'utf-8',
              baseUrl: WebUri('about:blank'),
            ),
            initialSettings: InAppWebViewSettings(
              // Only the CSP-nonced FileForge bootstrap may execute. Sender
              // scripts, handlers and active elements are removed separately.
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: false,
              useShouldOverrideUrlLoading: true,
              useOnDownloadStart: true,
              incognito: true,
              cacheEnabled: false,
              sharedCookiesEnabled: false,
              thirdPartyCookiesEnabled: false,
              domStorageEnabled: false,
              databaseEnabled: false,
              allowFileAccess: false,
              allowContentAccess: false,
              allowFileAccessFromFileURLs: false,
              allowUniversalAccessFromFileURLs: false,
              geolocationEnabled: false,
              supportMultipleWindows: false,
              allowsLinkPreview: false,
              allowsBackForwardNavigationGestures: false,
              forceDark: ForceDark.OFF,
              algorithmicDarkeningAllowed: false,
              transparentBackground: false,
              // The document declares its viewport. Do not shrink a wide data
              // table to microscopic text; let it scroll horizontally instead.
              loadWithOverviewMode: false,
              useWideViewPort: true,
              mediaPlaybackRequiresUserGesture: true,
            ),
            onWebViewCreated: (controller) {
              _watchdog?.cancel();
              _watchdog = Timer(const Duration(seconds: 12), _fail);
              controller.addJavaScriptHandler(
                handlerName: 'fileforgeMail',
                callback: (arguments) {
                  if (arguments.length == 1) _receive(arguments.first);
                  return null;
                },
              );
            },
            onLoadStop: (controller, url) async {
              // Platform-ready can precede the bootstrap on some platforms.
              // Re-announce after load so height/ready cannot be lost in a race.
              try {
                await controller.evaluateJavascript(
                  source: 'window.dispatchEvent(new Event("fileforge-mail-ready"));',
                );
              } catch (_) {
                _fail();
              }
            },
            shouldOverrideUrlLoading: (controller, action) async {
              final url = action.request.url?.toString() ?? '';
              if (url == 'about:blank' || url.startsWith('about:blank#')) {
                return NavigationActionPolicy.ALLOW;
              }
              // External links travel through the nonce-checked bridge AND
              // Flutter's confirmation dialog, never through WebView navigation.
              return NavigationActionPolicy.CANCEL;
            },
            onCreateWindow: (controller, action) async => false,
            onDownloadStartRequest: (controller, request) {},
            onPermissionRequest: (controller, request) async => PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.DENY,
            ),
            onReceivedError: (controller, request, error) {
              if (request.isForMainFrame == true) _fail();
            },
            onWebContentProcessDidTerminate: (controller) => _fail(),
          ),
        ),
      ),
    );
  }
}
