import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail_account.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/screens/mail/mail_list_screen.dart';

/// R0001(0022) 실시간 수신(방향 A) — 받은편지함이 떠 있는 동안 주기 폴링으로
/// 자동 수신하되, ★T0004 제약: 메일 작성 화면이 위에 push되어 있는 동안에는
/// 절대 동기화하지 않는다(작성 방해 금지). 네트워크 없이 syncInbox 호출 횟수로 고정.
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

/// 계정 1개 연결된 상태(no network).
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

  // 화면 진입(_enterMail)으로 syncInbox가 1회 호출된 시점까지 펌프.
  Future<void> settleEnter(WidgetTester tester) async {
    await tester.pump(); // account 분기
    await tester.pump(); // postFrame _enterMail
    await tester.pump(); // load 완료 후 syncInbox
  }

  testWidgets('polls and auto-syncs the inbox after the interval', (tester) async {
    final mail = _CountingMailProvider();
    await tester.pumpWidget(harness(mail));
    await settleEnter(tester);

    final afterEnter = mail.syncs;
    expect(afterEnter, greaterThanOrEqualTo(1)); // 진입 시 1회

    // 간격(10s)을 넘기면 폴링 tick이 한 번 더 동기화한다 = 실시간 수신.
    await tester.pump(const Duration(seconds: 11));
    expect(mail.syncs, greaterThan(afterEnter));

    // 타이머 정리: 화면 dispose.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does NOT sync while a screen is pushed above the inbox (compose-safe)',
      (tester) async {
    final mail = _CountingMailProvider();
    await tester.pumpWidget(harness(mail));
    await settleEnter(tester);

    // 작성 화면을 받은편지함 위로 push(메일 작성 중 상황 모사).
    navKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('composing')),
      ),
    );
    await tester.pumpAndSettle();
    final baseline = mail.syncs;

    // 작성 중에 간격이 지나도 폴링은 절대 동기화하지 않아야 한다(★T0004 제약).
    await tester.pump(const Duration(seconds: 11));
    expect(mail.syncs, baseline,
        reason: '메일 작성 화면이 위에 있는 동안 자동 새로고침이 발생하면 안 된다');

    // 작성 화면을 닫고 받은편지함으로 복귀하면 폴링이 재개된다.
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    expect(mail.syncs, greaterThan(baseline));

    await tester.pumpWidget(const SizedBox());
  });
}
