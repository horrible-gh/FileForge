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

/// R0001(0013) — with multiple accounts connected, the inbox list must show at a glance
/// which of *my accounts* each mail arrived on. Verifies the list tile renders the per-row
/// account identifier the server sends as a badge (the crux earlier revs were rejected over as "not showing").
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
    await tester.pump(); // account branch
    await tester.pump(); // postFrame _enterMail
    await tester.pump(); // settle

    // Both mails' *receiving account* labels actually appear in the list = the account is distinguishable.
    expect(find.text('Work Gmail'), findsOneWidget);
    expect(find.text('Personal Gmail'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'R0001(0037 rev1) — two accounts get DISTINCT row colors (not one color)',
      (tester) async {
    // Both accounts ship an identical server `display_color` (#EA4335). The
    // list must NOT collapse them to a single color: the avatar color is derived
    // from the account's position in the linked-account list, so acc_work and
    // acc_home end up on two different palette slots.
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
          'color': '#EA4335',
        },
      }),
    ];

    await tester.pumpWidget(harness(_FixedMailProvider(mails)));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // The leading avatar of each row carries the account color.
    final avatars = tester
        .widgetList<CircleAvatar>(find.byType(CircleAvatar))
        .toList();
    expect(avatars.length, 2, reason: 'one avatar per mail row');
    final colors = avatars.map((a) => a.backgroundColor).toSet();
    expect(colors.length, 2,
        reason: 'the two accounts must render in two DIFFERENT colors, '
            'not collapse to one (the rejection)');
    expect(colors.contains(null), isFalse,
        reason: 'both accounts have identity so both get a real color');

    await tester.pumpWidget(const SizedBox());
  });
}
