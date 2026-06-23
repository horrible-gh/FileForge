import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail_account.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/services/mail_envelope.dart';
import 'package:file_forge_app/screens/mail/account_connect_screen.dart';

/// NR0007 §6 L3 — 동의 URL 발급 실패 시 "토스트만 뜨고 막힘"(§5.4) 대신, OAuth
/// 섹션에 분화된 원인(L1) + 진단 꼬리표(L2) + 재시도/대체경로 배너가 뜨는지 본다.
class _FakeAccounts extends AccountProvider {
  _FakeAccounts(this._error) : super(Dio());
  final MailApiException _error;

  @override
  Future<({String? url, MailApiException? error})> oauthAuthorizeUrl(
          String provider) async =>
      (url: null, error: _error);

  @override
  bool get hasAccounts => false;
  @override
  List<MailAccount> get accounts => const [];
}

Widget _harness(AccountProvider accounts) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<AccountProvider>.value(
        value: accounts,
        child: const AccountConnectScreen(),
      ),
    );

void main() {
  testWidgets(
      'OAuth authorize 404/MALFORMED → 인라인 배너(분화 문구 + 진단 + 재시도/대체)',
      (tester) async {
    final err = MailApiException.fromEnvelope(
      {'error': {'code': 'MALFORMED_RESPONSE', 'message': 'x', 'request_id': 'rq_1'}},
      httpStatus: 404,
    );
    await tester.pumpWidget(_harness(_FakeAccounts(err)));
    await tester.pump();

    // 시작 화면엔 배너가 없다.
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

    // "Sign in with Google" 탭 → 발급 실패 → 배너 등장.
    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    await tester.pump();

    // L1: MALFORMED 전용 분화 문구(일반 "Failed to connect" 아님).
    expect(find.textContaining('unexpected response'), findsOneWidget);
    expect(find.text('Failed to connect the account'), findsNothing);
    // L2: 진단 꼬리표(code · HTTP status · requestId).
    expect(find.text('MALFORMED_RESPONSE · HTTP 404 · req rq_1'), findsOneWidget);
    // L3: 막다른 화면 금지 — 재시도 + 코드 직접 입력 전환 제공.
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Advanced: enter a code manually'), findsWidgets);
  });

  testWidgets('배너의 "코드 직접 입력 전환" 탭 → 배너 사라지고 수동 입력 펼침',
      (tester) async {
    final err = MailApiException(code: 'UNKNOWN', message: 'net');
    await tester.pumpWidget(_harness(_FakeAccounts(err)));
    await tester.pump();
    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    // 배너 안의 전환 액션을 탭(여러 곳에 같은 라벨이 있으므로 첫 번째).
    await tester.tap(find.text('Advanced: enter a code manually').first);
    await tester.pump();

    // 배너는 사라지고 수동 입력 필드가 보인다.
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(find.text('Authorization code'), findsOneWidget);
  });
}
