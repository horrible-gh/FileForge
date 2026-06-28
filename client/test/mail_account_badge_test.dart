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

/// R0001(0013) — 다계정 연동 시 받은편지함 리스트에서 각 메일이 *내 어느 계정*으로
/// 왔는지 한눈에 보여야 한다. 서버가 행마다 실어 보내는 account 식별자를 리스트
/// 타일이 배지로 렌더하는지 검증한다(이전 rev들이 "안 나온다"고 반려된 핵심).
class _FixedMailProvider extends MailProvider {
  _FixedMailProvider(this._fixed) : super(Dio());
  final List<MailSummary> _fixed;

  @override
  List<MailSummary> get mails => _fixed;

  @override
  Future<void> syncInbox({String label = 'inbox'}) async {}

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
        MailAccount(accountId: 'acc_work', email: 'work@gmail.com', provider: 'gmail'),
        MailAccount(accountId: 'acc_home', email: 'home@gmail.com', provider: 'gmail'),
      ];
}

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
      'list shows a per-mail account badge so two Gmail accounts are distinguishable',
      (tester) async {
    final mails = [
      MailSummary.fromJson({
        'mail_id': 'm1',
        'from': {'name': 'Alice', 'address': 'alice@ext.com'},
        'subject': 'Hello from work',
        'account': {
          'account_id': 'acc_work',
          'email': 'work@gmail.com',
          'name': 'Work Gmail',
          'color': '#EA4335',
        },
      }),
      MailSummary.fromJson({
        'mail_id': 'm2',
        'from': {'name': 'Bob', 'address': 'bob@ext.com'},
        'subject': 'Hello from home',
        'account': {
          'account_id': 'acc_home',
          'email': 'home@gmail.com',
          'name': 'Personal Gmail',
          // identical default color to the work account on purpose:
          'color': '#EA4335',
        },
      }),
    ];

    await tester.pumpWidget(harness(_FixedMailProvider(mails)));
    await tester.pump(); // account 분기
    await tester.pump(); // postFrame _enterMail
    await tester.pump(); // settle

    // 두 메일의 *수신 계정* 라벨이 리스트에 실제로 보인다 = 어느 계정인지 구분 가능.
    expect(find.text('Work Gmail'), findsOneWidget);
    expect(find.text('Personal Gmail'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
