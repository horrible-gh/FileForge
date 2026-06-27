import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'package:file_forge_app/widgets/mail_html_body.dart';

/// 0009 R0001 / NR0003 (+ 0005-TR rev1) — the mail detail body flooded
/// `mouse_tracker.dart:199 Assertion failed` because a bare [HtmlWidget]
/// rendered each `<img>` as a free-sizing [Image] that relayouts the hovered
/// subtree when its stream resolves. [MailHtmlBody] (a) wraps every image in a
/// [StableImage] whose box size does not depend on stream resolution, and
/// (b) forces every image to `display:block` so it is never an inline
/// `WidgetSpan` whose baseline computation trips `box.dart:2292`
/// (`computeDryBaseline`) — the regression that froze image-heavy mails.
///
/// These tests prove the stabilising invariants deterministically (data: URIs,
/// no network): images get a fixed, resolution-independent box, and an image in
/// inline text context lays out without throwing a framework assertion.

// A 40x20 red PNG and a 4x2 red PNG (RGB), generated offline.
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

void main() {
  testWidgets(
    'image with width/height attrs gets a deterministic box without loading',
    (tester) async {
      // Attributes 600x200; the box must be fixed from the first frame — the
      // image stream is never even consulted, so no relayout can occur.
      const html = '<img src="$_png40x20" width="600" height="200">';
      await _pump(tester, MailHtmlBody(html));
      await tester.pump();

      expect(find.byType(StableImage), findsOneWidget);
      final size = tester.getSize(find.byType(Image));
      expect(size.width, 600);
      expect(size.height, 200);
    },
  );

  testWidgets(
    'oversized attrs are capped to available width with aspect preserved',
    (tester) async {
      // 1600x800 (ratio 2:1) in an 800-wide surface → 800x400, no distortion.
      const html = '<img src="$_png40x20" width="1600" height="800">';
      await _pump(tester, MailHtmlBody(html));
      await tester.pump();

      final size = tester.getSize(find.byType(Image));
      expect(size.width, 800);
      expect(size.height, 400);
    },
  );

  testWidgets(
    'image without dimensions settles to a tight natural-size box',
    (tester) async {
      // No width/height attrs: the size is measured once from the stream and the
      // box settles to the natural 40x20 (under 800 wide, so uncapped). After
      // this single transition the box is constant — hovering cannot relayout.
      const html = '<img src="$_png40x20">';
      await _pump(tester, MailHtmlBody(html));
      // Image decoding runs on the real event loop, so let it complete under
      // runAsync, then pump to apply the resolved-size setState.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      // The settle is applied off-band (post-frame) to avoid a synchronous
      // relayout during the pointer device-update phase, so flush two frames.
      await tester.pump();
      await tester.pump();

      expect(find.byType(StableImage), findsOneWidget);
      final size = tester.getSize(find.byType(Image));
      expect(size.width, 40);
      expect(size.height, 20);
      // The size is stable across further frames / pointer activity.
      await tester.pump();
      expect(tester.getSize(find.byType(Image)), const Size(40, 20));
    },
  );

  testWidgets(
    'MailHtmlBody routes images through StableImage; bare HtmlWidget does not',
    (tester) async {
      const html = '<p>hi</p><img src="$_png40x20" width="40" height="20">';

      await _pump(tester, MailHtmlBody(html));
      await tester.pump();
      expect(find.byType(StableImage), findsOneWidget);
      expect(
        find.textContaining('hi', findRichText: true),
        findsOneWidget,
        reason: 'text alongside images still renders',
      );

      // Control: the unstabilised path (what flooded the assert) has no
      // StableImage wrapper.
      await _pump(tester, const HtmlWidget(html));
      await tester.pump();
      expect(find.byType(StableImage), findsNothing);
    },
  );

  testWidgets(
    'image in inline text context lays out without a framework assertion',
    (tester) async {
      // The 0005-TR rev0 regression: an `<img>` inside flowing text is an inline
      // WidgetSpan; the RenderParagraph computes its baseline via getDryBaseline,
      // and the AspectRatio/Align wrapper tripped box.dart:2292
      // (RenderBox.size accessed in computeDryBaseline). For an image-heavy mail
      // this fired every layout pass and froze the app. Forcing display:block
      // removes the inline-baseline path. With attrs the box is fixed without
      // touching the stream, so a single pump fully lays it out.
      const html =
          '<p>see the statement <img src="$_png40x20" width="40" height="20"> '
          'attached and <a href="https://example.com">click here</a></p>';
      await _pump(tester, MailHtmlBody(html));
      await tester.pump();

      // No assertion (box.dart:2292 / mouse_tracker.dart:199) was thrown during
      // layout — pre-fix this surfaced as a non-null taken exception.
      expect(tester.takeException(), isNull);
      expect(find.byType(StableImage), findsOneWidget);
      expect(
        find.textContaining('see the statement', findRichText: true),
        findsOneWidget,
      );
    },
  );
}
