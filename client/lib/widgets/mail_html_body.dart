import 'package:flutter/material.dart';

import 'mail_html_fallback.dart' as legacy;
import 'mail_html_native.dart'
    if (dart.library.js_interop) 'mail_html_web.dart' as platform;

// Preserve the public types used by the existing image-stability tests.
export 'mail_html_fallback.dart' show MailImageFactory, StableImage;

/// Browser-rendered mail: keep real table rows/cells and sender styles instead
/// of rewriting every table element to display:block. The surrounding app may
/// be dark; the message has its own light default canvas and author colours.
class MailHtmlBody extends StatelessWidget {
  const MailHtmlBody(this.html, {super.key});

  final String html;

  @override
  Widget build(BuildContext context) => platform.MailHtmlView(
        // Never reuse a document/channel after switching to another message.
        key: ValueKey(html),
        html: html,
        fallbackBuilder: (context) {
          // Linux, missing WebView2, unsupported plugins or a failed browser
          // bootstrap still get the previous readable renderer. Keep its image
          // stability workarounds; do NOT apply its table rewrite to browsers.
          final theme = ThemeData.light(useMaterial3: true);
          return ColoredBox(
            color: Colors.white,
            child: Theme(
              data: theme,
              child: DefaultTextStyle(
                style: theme.textTheme.bodyMedium!.copyWith(color: Colors.black),
                child: legacy.MailHtmlBody(html),
              ),
            ),
          );
        },
      );
}
