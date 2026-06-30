/// Opening links found in a mail body (R0001 / 0031 — "메일로 온 링크가 단 하나도
/// 눌러지지 않음 … 최소한 누를 수 있게 옵션이라도 주던가").
///
/// The detail body renders `<a href>` (HTML) and bare URLs (plain text) but
/// nothing ever opened them: the HTML renderer
/// (`flutter_widget_from_html_core`) only styles anchors unless the caller
/// supplies an `onTapUrl` callback, and the plain-text body was a bare [Text]
/// with no URL recognition (NR0003 root causes A and B).
///
/// This wires both paths to the same guarded launch flow:
///  1. **Scheme allow-list** — only `http`/`https`/`mailto` open. Anything else
///     (`javascript:`, `file:`, `data:`, custom app schemes …) is refused, so a
///     hostile mail can't steer the system launcher into an unexpected handler.
///  2. **Explicit confirm** — tapping shows the real destination URL and opens
///     only on the user's confirmation, honouring R0001's security concern
///     while still giving the "option" to follow the link. The link opens in
///     the **external** browser, never in-app.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../widgets/app_toast.dart';

/// Schemes a mail-body link is allowed to open.
const Set<String> kAllowedMailLinkSchemes = {'http', 'https', 'mailto'};

/// Whether [url] is a link this app will offer to open. Pure (no context) so it
/// is unit-testable and reused by the plain-text linkifier to decide what to
/// turn into a tappable span.
bool isOpenableMailLink(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return false;
  return kAllowedMailLinkSchemes.contains(uri.scheme.toLowerCase());
}

/// Confirm with the user (showing the real destination), then open [url] in the
/// external browser.
///
/// Always returns `true`: the tap is considered handled whether the user
/// confirms, cancels, or the scheme is refused — fwfh uses the return value to
/// decide whether the anchor was consumed, and we never want an unhandled link
/// to fall through to fwfh's default (which does nothing anyway).
Future<bool> confirmAndOpenMailLink(BuildContext context, String url) async {
  final t = AppLocalizations.of(context);
  final trimmed = url.trim();

  if (!isOpenableMailLink(trimmed)) {
    AppToast.error(context, t.mailLinkOpenFailed);
    return true;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.mailLinkOpenTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.mailLinkOpenConfirm),
          const SizedBox(height: 12),
          // The real destination, selectable so the user can inspect/copy it
          // before deciding to open it.
          SelectableText(
            trimmed,
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(t.mailLinkOpenAction),
        ),
      ],
    ),
  );

  if (confirmed != true) return true;
  if (!context.mounted) return true;

  var ok = false;
  try {
    ok = await launchUrl(
      Uri.parse(trimmed),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    AppToast.error(context, t.mailLinkOpenFailed);
  }
  return true;
}
