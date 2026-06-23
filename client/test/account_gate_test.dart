import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail_account.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/screens/mail/mail_list_screen.dart';

/// 메일 진입 게이트 — TS0006 시나리오 4(핵심 회귀 가드).
///
/// NR0003 §6: "무계정일 때 GET /mails(loadInbox)가 호출되지 않음" 이 현 버그의
/// 정확한 반대이며 회귀 방지 핵심이다. loadInbox 호출 여부를 추적하는 페이크로
/// 게이트 분기(무계정→온보딩 / 계정→inbox / 에러→재시도)를 검증한다.
class _SpyMailProvider extends MailProvider {
  _SpyMailProvider() : super(Dio());
  final List<String> loaded = [];

  @override
  Future<void> loadInbox({String label = 'inbox'}) async {
    loaded.add(label);
    notifyListeners();
  }
}

/// 게이트 상태를 고정하는 페이크(네트워크 없음).
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

    // 핵심 회귀 가드: inbox 를 긁지 않는다.
    expect(mail.loaded, isEmpty);
    // 온보딩(연결 버튼)이 보이고, 무서운 메일 에러 화면이 아니다.
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
    expect(find.text('Inbox'), findsOneWidget); // 라벨 스위처 노출
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
    // 블랙아웃 금지: 계정 추가 CTA 가 여전히 도달 가능해야 한다(썬더버드 패리티).
    expect(find.text('Connect account'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // 일시 오류 문구가 뜨고, 세션 문구는 뜨지 않는다.
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
    // 401 은 "계정 읽기 실패"가 아니라 세션 문제로 안내된다.
    expect(find.textContaining('session has expired'), findsOneWidget);
    // 그래도 앱을 막지 않는다: 계정 추가 CTA·재시도 노출.
    expect(find.text('Connect account'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
