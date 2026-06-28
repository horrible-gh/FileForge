import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:file_forge_app/widgets/mail_html_body.dart';

/// 0020 R0001 / NR0003 — Google security-alert mail rendered "vertically, one
/// character per line". Root cause: `flutter_widget_from_html_core` 0.17.2's
/// table column-width algorithm (`html_table.dart`) collapses the content column
/// of a `min-width` nested table down to ~1 character (~33px at an 800px-wide
/// surface). Google wraps the whole body in such a table — an outer `min-width`
/// table containing a nested table whose content cell is flanked by ~8px spacer
/// columns — which is the worst case for the algorithm.
///
/// The fix forces table-family elements to `display:block` in
/// [MailHtmlBody]'s `customStylesBuilder`, so fwfh lays the cells out as ordinary
/// block children that take the available width instead of routing through the
/// collapsing column-width code. These tests pin the symptom (content column
/// must NOT collapse to ~1 char) and the no-regression guarantee for the
/// pre-existing image overrides.

const _png40x20 =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAJElEQVR4nO3NMQ0AAAACIPuX1hg+bPykycVnFYvFYrFYLO4jHn36HQ4oCLQGAAAAAElFTkSuQmCC';

Future<void> _pump(WidgetTester tester, Widget body) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            child: SingleChildScrollView(child: body),
          ),
        ),
      ),
    ),
  );
}

// Mirrors the Google security-alert layout: outer min-width table → nested
// min-width table with 8px spacer columns flanking the content cell.
const _googleStyleBody =
    '<table style="min-width:600px;width:100%"><tr><td>'
    '<table style="min-width:220px"><tr>'
    '<td style="width:8px;font-size:1px">&nbsp;</td>'
    '<td><div style="padding:40px 20px">'
    '보안 알림 새로운 기기에서 로그인했습니다 이것은 충분히 긴 본문 문장입니다'
    '</div></td>'
    '<td style="width:8px;font-size:1px">&nbsp;</td>'
    '</tr></table>'
    '</td></tr></table>';

void main() {
  testWidgets(
    'Google-style min-width nested table does not collapse the content column to ~1 char/line',
    (tester) async {
      await _pump(tester, const MailHtmlBody(_googleStyleBody));
      await tester.pump();

      final content = find.textContaining('보안 알림', findRichText: true);
      expect(content, findsOneWidget);

      // Pre-fix the content paragraph collapses to ~33px (one CJK glyph wide,
      // wrapping every character to a new line). With the table forced to
      // display:block it takes the available width (NR0003 measured ~476px).
      final width = tester.getSize(content).width;
      expect(
        width,
        greaterThan(200),
        reason:
            'content column collapsed to ${width.toStringAsFixed(1)}px '
            '(~1 char/line) — fwfh table layout was not bypassed',
      );
    },
  );

  testWidgets(
    'plain (non-table) body still renders at full width',
    (tester) async {
      // A control: the override must not change ordinary block text.
      const html = '<p>보안 알림 새로운 기기에서 로그인했습니다 이것은 긴 본문</p>';
      await _pump(tester, const MailHtmlBody(html));
      await tester.pump();

      final content = find.textContaining('보안 알림', findRichText: true);
      expect(content, findsOneWidget);
      expect(tester.getSize(content).width, greaterThan(200));
    },
  );

  testWidgets(
    'image overrides survive the table override (0009 no-regression)',
    (tester) async {
      // The pre-existing <img> display:block / max-width:100% override must be
      // preserved: an image with attrs still gets its deterministic StableImage
      // box, and an oversized image is still capped to the available width.
      const html = '<img src="$_png40x20" width="1600" height="800">';
      await _pump(tester, const MailHtmlBody(html));
      await tester.pump();

      expect(find.byType(StableImage), findsOneWidget);
      final size = tester.getSize(find.byType(Image));
      expect(size.width, 800);
      expect(size.height, 400);
    },
  );
}
