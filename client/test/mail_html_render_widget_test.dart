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
}
