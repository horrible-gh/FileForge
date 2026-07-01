import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail_account.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/screens/mail/mail_list_screen.dart';

/// text translated text(Draft translated text UI text) — TR0009 remaining worktranslated text text verify.
///
/// translated text text text translated text translated text text [MailProvider.loadInbox] text
/// translated text faketext text. account translated text(T0004)text addtext text translated text
/// accounttext 1text and abovetext text translated text, account text statetext fake translated text text text.
class _FakeMailProvider extends MailProvider {
  _FakeMailProvider() : super(Dio());

  final List<String> loaded = [];

  @override
  Future<void> loadInbox({String label = 'inbox'}) async {
    loaded.add(label);
    notifyListeners();
  }

  // R0001(TR0005): screen entry/refresh now calls syncInbox. Delegate to local load
  // (loadInbox) only, with no network, to preserve the existing regression intent.
  @override
  Future<void> syncInbox({String label = 'inbox', bool quiet = false}) =>
      loadInbox(label: label);
}

/// account 1text translated text translated text translated text fake(no network).
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
  List<MailAccount> get accounts =>
      const [MailAccount(accountId: 'a1', email: 'me@example.com', provider: 'gmail')];
}

void main() {
  Widget harness(MailProvider provider, {AccountProvider? accounts}) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<MailProvider>.value(value: provider),
            ChangeNotifierProvider<AccountProvider>.value(
                value: accounts ?? _ConnectedAccountProvider()),
          ],
          child: const MailListScreen(),
        ),
      );

  testWidgets('shows the three system labels', (tester) async {
    await tester.pumpWidget(harness(_FakeMailProvider()));
    await tester.pump(); // translated text text(account text)
    await tester.pump(); // text postFrame loadInbox

    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Drafts'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('tapping Drafts switches the provider label to drafts',
      (tester) async {
    final fake = _FakeMailProvider();
    await tester.pumpWidget(harness(fake));
    await tester.pump();
    await tester.pump();

    expect(fake.loaded, contains('inbox')); // translated text text text Inbox text

    await tester.tap(find.text('Drafts'));
    await tester.pump();

    expect(fake.loaded.last, 'drafts');
  });

  test('mailLabelName maps system labels (incl. legacy "draft")', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(mailLabelName(en, 'inbox'), 'Inbox');
    expect(mailLabelName(en, 'drafts'), 'Drafts');
    expect(mailLabelName(en, 'draft'), 'Drafts'); // text translated text Drafts
    expect(mailLabelName(en, 'sent'), 'Sent');
    expect(kMailSystemLabels, ['inbox', 'drafts', 'sent']);
  });
}
