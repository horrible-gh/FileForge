import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/screens/mail/mail_detail_screen.dart';

/// F6 (B0001/0043) — the detail screen shows a Bcc row so the sender can verify
/// the hidden recipients of their own sent mail. The server fills `bcc` for the
/// Sent folder only; on received mail the field is empty and no row may appear.
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

  testWidgets('sent mail with bcc shows a Bcc row', (tester) async {
    final detail = MailDetail(
      mailId: 'm1',
      from: const MailAddress(address: 'me@example.com'),
      to: const [MailAddress(address: 'boss@example.com')],
      bcc: const [MailAddress(name: 'Hidden', address: 'hidden@example.com')],
      subject: 'Report',
      body: const MailBody(format: 'text', content: 'body'),
      labels: const ['sent'],
    );
    await tester.pumpWidget(harness(_FixedDetailMailProvider(detail)));
    await tester.pump();

    expect(find.text('Bcc'), findsOneWidget);
    expect(find.textContaining('hidden@example.com'), findsOneWidget);
  });

  testWidgets('mail without bcc renders no Bcc row', (tester) async {
    final detail = MailDetail(
      mailId: 'm1',
      from: const MailAddress(address: 'alice@ext.com'),
      to: const [MailAddress(address: 'me@example.com')],
      cc: const [MailAddress(address: 'peer@example.com')],
      subject: 'Hello',
      body: const MailBody(format: 'text', content: 'body'),
    );
    await tester.pumpWidget(harness(_FixedDetailMailProvider(detail)));
    await tester.pump();

    expect(find.text('Cc'), findsOneWidget);
    expect(find.text('Bcc'), findsNothing);
  });
}
