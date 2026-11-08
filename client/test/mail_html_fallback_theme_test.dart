import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:file_forge_app/widgets/mail_html_body.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('unsupported native platform keeps a light, readable fallback', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: const Scaffold(body: MailHtmlBody('<p style="color:black">Readable mail</p>')),
    ));
    await tester.pump();
    expect(find.textContaining('Readable mail', findRichText: true), findsOneWidget);
    final element = tester.element(find.byType(HtmlWidget));
    expect(Theme.of(element).brightness, Brightness.light);
    expect(DefaultTextStyle.of(element).style.color, Colors.black);
    expect(tester.takeException(), isNull);
  });
}
