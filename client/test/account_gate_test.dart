import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail_account.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/screens/mail/mail_list_screen.dart';

/// text text translated text — TS0006 scenario 4(core regression guard).
///
/// NR0003 §6: "textaccounttext text GET /mails(loadInbox)text translated text text" text text translated text
/// translated text translated text regression text coretext. loadInbox text translated text translated text faketext
/// translated text branch(textaccount→translated text / account→inbox / error→retry)text verifytext.
class _SpyMailProvider extends MailProvider {
  _SpyMailProvider() : super(Dio());
  final List<String> loaded = [];

  @override
  Future<void> loadInbox({String label = 'inbox'}) async {
    loaded.add(label);
    notifyListeners();
  }
}

/// translated text statetext translated text fake(no network).
class _FakeAccounts extends AccountProvider {
  _FakeAccounts(this._gate, this._accounts, {AccountLoadErrorKind? errorKind})
      : _errorKind = errorKind,
        super(Dio());
  final AccountGateState _gate;
  final List<MailAccount> _accounts;
  final AccountLoadErrorKind? _errorKind;

  @override
  Future<void> load() async => notifyListeners();
  @override
  AccountGateState get gate => _gate;
  @override
  AccountLoadErrorKind? get errorKind => _errorKind;
  @override
  bool get isResolved => _gate == AccountGateState.ready;
  @override
  bool get hasAccounts => _accounts.isNotEmpty;
  @override
  List<MailAccount> get accounts => List.unmodifiable(_accounts);
}

const _oneAccount = [
  MailAccount(accountId: 'a1', email: 'me@example.com', provider: 'gmail'),
];

Widget _harness(MailProvider mail, AccountProvider accounts) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<MailProvider>.value(value: mail),
          ChangeNotifierProvider<AccountProvider>.value(value: accounts),
        ],
        child: const MailListScreen(),
      ),
    );

void main() {
  testWidgets('no accounts → onboarding shown and loadInbox NOT called',
      (tester) async {
    final mail = _SpyMailProvider();
    await tester.pumpWidget(
        _harness(mail, _FakeAccounts(AccountGateState.ready, const [])));
    await tester.pump(); // _enterMail postFrame
    await tester.pump();

    // core regression guard: inbox text text translated text.
    expect(mail.loaded, isEmpty);
    // translated text(text text)text translated text, translated text text error screentext translated text.
    expect(find.text('Connect account'), findsOneWidget);
    expect(find.text('Failed to load mail'), findsNothing);
  });

  testWidgets('≥1 account → gate passes and loadInbox called',
      (tester) async {
    final mail = _SpyMailProvider();
    await tester.pumpWidget(
        _harness(mail, _FakeAccounts(AccountGateState.ready, _oneAccount)));
    await tester.pump();
    await tester.pump();

    expect(mail.loaded, contains('inbox'));
    expect(find.text('Inbox'), findsOneWidget); // text translated text text
    expect(find.text('Connect account'), findsNothing);
  });

  testWidgets(
      'transient gate error → non-blocking banner + connect CTA reachable, '
      'loadInbox NOT called (NR0004 §4)', (tester) async {
    final mail = _SpyMailProvider();
    await tester.pumpWidget(_harness(
        mail,
        _FakeAccounts(AccountGateState.error, const [],
            errorKind: AccountLoadErrorKind.transient)));
    await tester.pump();
    await tester.pump();

    expect(mail.loaded, isEmpty);
    // translated text prohibited: account add CTA text translated text text translated text text(translated text translated text).
    expect(find.text('Connect account'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // text error messagetext text, session messagetext text translated text.
    expect(
        find.textContaining("Couldn't reach the mail service"), findsOneWidget);
  });

  testWidgets(
      'session gate error (401/403) → re-login wording, connect CTA still '
      'reachable (NR0004 §2·§4)', (tester) async {
    final mail = _SpyMailProvider();
    await tester.pumpWidget(_harness(
        mail,
        _FakeAccounts(AccountGateState.error, const [],
            errorKind: AccountLoadErrorKind.session)));
    await tester.pump();
    await tester.pump();

    expect(mail.loaded, isEmpty);
    // 401 text "account text failed"text translated text session translated text translated text.
    expect(find.textContaining('session has expired'), findsOneWidget);
    // translated text text text translated text: account add CTA·retry text.
    expect(find.text('Connect account'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
