import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail_account.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/screens/mail/mail_list_screen.dart';

/// R0001(0022) real-time receive (direction A) — while the inbox is open, periodic polling
/// auto-receives, but with the ★T0004 constraint: never sync while the compose screen is
/// pushed on top (no interrupting composition). Pinned by syncInbox call count, no network.
class _CountingMailProvider extends MailProvider {
  _CountingMailProvider() : super(Dio());

  int syncs = 0;

  @override
  Future<void> syncInbox({String label = 'inbox'}) async {
    syncs++;
    notifyListeners();
  }

  @override
  Future<void> loadInbox({String label = 'inbox'}) async {
    notifyListeners();
  }
}

/// State with one account connected (no network).
class _ConnectedAccountProvider extends AccountProvider {
  _ConnectedAccountProvider() : super(Dio());

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
        MailAccount(accountId: 'a1', email: 'me@example.com', provider: 'gmail')
      ];
}

void main() {
  final navKey = GlobalKey<NavigatorState>();

  Widget harness(MailProvider provider) => MaterialApp(
        navigatorKey: navKey,
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

  // Pump until screen entry (_enterMail) has called syncInbox once.
  Future<void> settleEnter(WidgetTester tester) async {
    await tester.pump(); // account branch
    await tester.pump(); // postFrame _enterMail
    await tester.pump(); // syncInbox after load completes
  }

  testWidgets('polls and auto-syncs the inbox after the interval', (tester) async {
    final mail = _CountingMailProvider();
    await tester.pumpWidget(harness(mail));
    await settleEnter(tester);

    final afterEnter = mail.syncs;
    expect(afterEnter, greaterThanOrEqualTo(1)); // once on entry

    // Past the interval (10s), a polling tick syncs once more = real-time receive.
    await tester.pump(const Duration(seconds: 11));
    expect(mail.syncs, greaterThan(afterEnter));

    // Timer cleanup: dispose the screen.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does NOT sync while a screen is pushed above the inbox (compose-safe)',
      (tester) async {
    final mail = _CountingMailProvider();
    await tester.pumpWidget(harness(mail));
    await settleEnter(tester);

    // Push the compose screen on top of the inbox (simulating mid-composition).
    navKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('composing')),
      ),
    );
    await tester.pumpAndSettle();
    final baseline = mail.syncs;

    // While composing, polling must never sync even past the interval (★T0004 constraint).
    await tester.pump(const Duration(seconds: 11));
    expect(mail.syncs, baseline,
        reason: '메일 작성 화면이 위에 있는 동안 자동 새로고침이 발생하면 안 된다');

    // Closing the compose screen and returning to the inbox resumes polling.
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    expect(mail.syncs, greaterThan(baseline));

    await tester.pumpWidget(const SizedBox());
  });
}
