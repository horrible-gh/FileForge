import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail_account.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/screens/mail/mail_list_screen.dart';

/// 라벨 스위처(초안 이어쓰기 UI 진입) — TR0009 잔여작업의 동작 검증.
///
/// 네트워크 없이 라벨 전환만 확인하기 위해 [MailProvider.loadInbox] 를
/// 가로채는 페이크를 쓴다. 계정 게이트(T0004)가 추가되어 라벨 스위처는
/// 계정이 1개 이상일 때만 보이므로, 계정 보유 상태의 페이크 게이트를 함께 건다.
class _FakeMailProvider extends MailProvider {
  _FakeMailProvider() : super(Dio());

  final List<String> loaded = [];

  @override
  Future<void> loadInbox({String label = 'inbox'}) async {
    loaded.add(label);
    notifyListeners();
  }
}

/// 계정 1개 보유로 게이트를 통과시키는 페이크(네트워크 없음).
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
    await tester.pump(); // 게이트 통과(계정 보유)
    await tester.pump(); // 초기 postFrame loadInbox

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

    expect(fake.loaded, contains('inbox')); // 게이트 통과 후 받은편지함 로드

    await tester.tap(find.text('Drafts'));
    await tester.pump();

    expect(fake.loaded.last, 'drafts');
  });

  test('mailLabelName maps system labels (incl. legacy "draft")', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(mailLabelName(en, 'inbox'), 'Inbox');
    expect(mailLabelName(en, 'drafts'), 'Drafts');
    expect(mailLabelName(en, 'draft'), 'Drafts'); // 단수 별칭도 임시보관함
    expect(mailLabelName(en, 'sent'), 'Sent');
    expect(kMailSystemLabels, ['inbox', 'drafts', 'sent']);
  });
}
