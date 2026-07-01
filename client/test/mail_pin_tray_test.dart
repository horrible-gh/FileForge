import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail.dart';
import 'package:file_forge_app/models/mail_account.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/screens/mail/mail_list_screen.dart';

/// R0001(0027) — "ピン留め (Pinned)" tray UX (reflecting user rejection). Verifies that pinned
/// mails do not pile up in the chronological list but gather and render in a **separate tray**,
/// that the header shows a label/count, and that collapsing it hides the pinned mails in the
/// tray (non-pinned body mails are always visible).
class _FixedMailProvider extends MailProvider {
  _FixedMailProvider(this._fixed) : super(Dio());
  final List<MailSummary> _fixed;

  @override
  List<MailSummary> get mails => _fixed;

  @override
  Future<void> syncInbox({String label = 'inbox', bool quiet = false}) async {}

  @override
  Future<void> loadInbox({String label = 'inbox'}) async {}
}

class _ConnectedAccountProvider extends AccountProvider {
  _ConnectedAccountProvider() : super(Dio());

  @override
  Future<bool> primeFromCache() async => true;

  @override
  Future<void> load() async => notifyListeners();

  @override
  bool get hasAccounts => true;

  @override
  bool get isResolved => true;

  @override
  AccountGateState get gate => AccountGateState.ready;

  @override
  List<MailAccount> get accounts => const [
        MailAccount(
            accountId: 'acc_a', email: 'a@gmail.com', provider: 'gmail'),
      ];
}

MailSummary _mail(String id, String fromName, {bool pinned = false}) =>
    MailSummary.fromJson({
      'mail_id': id,
      'from': {'name': fromName, 'address': '$id@ext.com'},
      'subject': 'subject_$id',
      'is_pinned': pinned,
    });

void main() {
  Widget harness(MailProvider provider) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<MailProvider>.value(value: provider),
            ChangeNotifierProvider<AccountProvider>.value(
                value: _ConnectedAccountProvider()),
          ],
          child: const MailListScreen(),
        ),
      );

  testWidgets(
      'pinned mails render in a dedicated "Pinned" tray, separate from the body list',
      (tester) async {
    final mails = [
      _mail('m1', 'Pinned Alice', pinned: true),
      _mail('m2', 'Plain Bob'),
    ];
    await tester.pumpWidget(harness(_FixedMailProvider(mails)));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // The tray header (label + count badge) is present, and BOTH the pinned
    // sender (inside the tray) and the unpinned sender (body list) are visible.
    expect(find.text('Pinned'), findsOneWidget); // tray header label
    expect(find.text('1'), findsOneWidget); // count badge
    expect(find.text('Pinned Alice'), findsOneWidget);
    expect(find.text('Plain Bob'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('collapsing the tray hides pinned mails but keeps the body list',
      (tester) async {
    final mails = [
      _mail('m1', 'Pinned Alice', pinned: true),
      _mail('m2', 'Plain Bob'),
    ];
    await tester.pumpWidget(harness(_FixedMailProvider(mails)));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Pinned Alice'), findsOneWidget);

    // Tap the tray header to collapse it.
    await tester.tap(find.text('Pinned'));
    await tester.pumpAndSettle();

    // The pinned mail is now hidden (tray collapsed) but the header and the
    // unpinned body mail remain.
    expect(find.text('Pinned Alice'), findsNothing);
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Plain Bob'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no tray is rendered when there are no pinned mails',
      (tester) async {
    final mails = [_mail('m1', 'Plain Bob')];
    await tester.pumpWidget(harness(_FixedMailProvider(mails)));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Pinned'), findsNothing); // no tray header
    expect(find.text('Plain Bob'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
