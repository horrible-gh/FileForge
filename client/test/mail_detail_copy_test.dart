import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/screens/mail/mail_detail_screen.dart';

/// R0001(0016) — the mail detail screen must let the user *copy* the subject,
/// body and sender address (text selection in this non-standard Flutter app is
/// inconsistent — HTML bodies render as non-selectable RichText). The copy
/// affordance is a single AppBar overflow menu (no buttons scattered around),
/// and copying an HTML body must put readable plain text on the clipboard, not
/// raw markup/CSS.
class _FixedDetailMailProvider extends MailProvider {
  _FixedDetailMailProvider(this._fixed) : super(Dio());
  final MailDetail _fixed;

  // initState calls openMail(); make it a no-op so no network/Dio is touched.
  @override
  Future<void> openMail(String mailId) async {}

  @override
  MailDetail? get detail => _fixed;

  @override
  bool get detailLoading => false;

  @override
  String? get detailError => null;
}

void main() {
  Widget harness(MailProvider provider) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChangeNotifierProvider<MailProvider>.value(
          value: provider,
          child: const MailDetailScreen(mailId: 'm1', subject: 'Hello'),
        ),
      );

  // Capture what the app writes to the system clipboard.
  String? clipboardText;
  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> openCopyMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.content_copy_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets('copy menu copies the subject', (tester) async {
    final detail = MailDetail(
      mailId: 'm1',
      from: const MailAddress(name: 'Alice', address: 'alice@ext.com'),
      subject: 'Quarterly report',
      body: const MailBody(format: 'text', content: 'plain body'),
    );
    await tester.pumpWidget(harness(_FixedDetailMailProvider(detail)));
    await tester.pump();

    await openCopyMenu(tester);
    await tester.tap(find.text('Copy subject'));
    await tester.pumpAndSettle();

    expect(clipboardText, 'Quarterly report');
    // Feedback snackbar confirms the action.
    expect(find.text('Copied to clipboard'), findsOneWidget);
  });

  testWidgets('copy menu copies the sender address only', (tester) async {
    final detail = MailDetail(
      mailId: 'm1',
      from: const MailAddress(name: 'Alice', address: 'alice@ext.com'),
      subject: 'Subj',
    );
    await tester.pumpWidget(harness(_FixedDetailMailProvider(detail)));
    await tester.pump();

    await openCopyMenu(tester);
    await tester.tap(find.text('Copy sender address'));
    await tester.pumpAndSettle();

    expect(clipboardText, 'alice@ext.com');
  });

  testWidgets('copying an HTML body strips tags/CSS to readable text',
      (tester) async {
    const html = '<html><head><style>.x{color:red}</style></head>'
        '<body><p>Hello&nbsp;world</p></body></html>';
    final detail = MailDetail(
      mailId: 'm1',
      from: const MailAddress(address: 'a@b.com'),
      subject: 'Subj',
      body: const MailBody(format: 'html', content: html),
    );
    await tester.pumpWidget(harness(_FixedDetailMailProvider(detail)));
    await tester.pump();

    await openCopyMenu(tester);
    await tester.tap(find.text('Copy body'));
    await tester.pumpAndSettle();

    final copied = clipboardText ?? '';
    expect(copied.contains('Hello world'), isTrue,
        reason: 'readable text expected, got: $copied');
    // No markup or CSS may leak onto the clipboard.
    expect(copied.contains('<'), isFalse);
    expect(copied.contains('color:red'), isFalse);
    expect(copied.contains('.x{'), isFalse);
  });

  testWidgets('detail body is wrapped in a SelectionArea (selection restored)',
      (tester) async {
    final detail = MailDetail(
      mailId: 'm1',
      from: const MailAddress(address: 'a@b.com'),
      subject: 'Subj',
      body: const MailBody(format: 'text', content: 'selectable body'),
    );
    await tester.pumpWidget(harness(_FixedDetailMailProvider(detail)));
    await tester.pump();

    expect(find.byType(SelectionArea), findsOneWidget);
  });
}
