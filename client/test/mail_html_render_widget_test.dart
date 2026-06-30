import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

/// 0008 R0001 — proves the HTML body renderer (the path the mail detail screen
/// now uses) shows the readable body and does NOT leak `<style>` CSS as text,
/// the way the old tag-stripping renderer did.
void main() {
  testWidgets('HtmlWidget renders body text and hides <style> CSS', (tester) async {
    // Shape mirrors R0001: a <head><style>…</style></head> block + body text.
    const html = '<html><head><style>'
        '.sup{vertical-align:1px !important;font-size:100%;}'
        '@media all and (max-width:480px){.pad0{padding:0 !important;}}'
        'wbr{display:none !important;}'
        '</style></head><body>'
        '<p>トップリーグに挑む準備はできていますか？</p>'
        '</body></html>';

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HtmlWidget(html)))),
    );
    await tester.pump();

    // Readable body is shown (HtmlWidget renders into RichText spans).
    expect(
      find.textContaining('トップリーグに挑む準備', findRichText: true),
      findsOneWidget,
    );

    // The CSS rules from <style> must not appear anywhere as visible text.
    final cssLeaks = ['vertical-align', '@media', '.sup{', 'display:none'];
    for (final leak in cssLeaks) {
      expect(
        find.textContaining(leak, findRichText: true),
        findsNothing,
        reason: 'CSS "$leak" leaked into body',
      );
    }
  });

  // B0001 / 0018 — the KB statement body rendered BLANK ("showed nothing at all").
  // Root cause is server-side (the image-proxy rewrite emitted a CSS url() DOUBLE-
  // QUOTED inside a double-quoted style="…" attribute, so the inner quote closed the
  // attribute and the HTML parser swallowed the rest of the body). These two tests
  // pin the *client-visible* contract for both the fixed and the broken server output.
  testWidgets('CSS url() emitted UNQUOTED inside style="…" renders the whole body',
      (tester) async {
    // Shape of the FIXED server output: url(/same-origin/proxy?…) with no inner quote.
    const html = '<body>'
        '<p style="background:url(/fileforge/mail/image-proxy?u=AA&sig=bb) no-repeat 0 11px;">'
        '이메일명세서</p>'
        '<p>바로가기</p>'
        '</body>';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HtmlWidget(html)))),
    );
    await tester.pump();
    // fwfh tries to fetch the CSS background image as a NetworkImage; under the test
    // binding that returns 400 and throws. It is incidental to this test (we assert on
    // text, not the background pixel), so drain it.
    while (tester.takeException() != null) {}
    expect(find.textContaining('이메일명세서', findRichText: true), findsOneWidget);
    // The element AFTER the styled one must survive — this is what was lost.
    expect(find.textContaining('바로가기', findRichText: true), findsOneWidget);
  });

  testWidgets('regression witness: DOUBLE-QUOTED url() inside style="…" swallows the body',
      (tester) async {
    // Shape of the OLD broken server output: style="…url("PROXY")…". The first inner
    // double quote closes the style attribute; the parser then drops the rest.
    const html = '<body>'
        '<p style="background:url(&quot;/proxy?u=AA&quot;) no-repeat;">이메일명세서</p>'
        '<p>바로가기</p>'
        '</body>';
    // Reproduce the literal broken bytes (an actual " not the &quot; entity):
    final broken = html.replaceAll('&quot;', '"');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HtmlWidget(broken)))),
    );
    await tester.pump();
    // With the broken emission fwfh produces no readable body text at all.
    expect(find.textContaining('바로가기', findRichText: true), findsNothing);
  });
}
