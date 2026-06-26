import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail_account.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/services/mail_envelope.dart';
import 'package:file_forge_app/screens/mail/account_connect_screen.dart';

/// NR0007 §6 L3 — consent URL issue failed text "toasttext text text"(§5.4) text, OAuth
/// translated text minutestext text(L1) + diagnostic translated text(L2) + retry/fallback path bannertext translated text text.
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
      'OAuth authorize 404/MALFORMED → translated text banner(minutestext message + diagnostic + retry/text)',
      (tester) async {
    final err = MailApiException.fromEnvelope(
      {'error': {'code': 'MALFORMED_RESPONSE', 'message': 'x', 'request_id': 'rq_1'}},
      httpStatus: 404,
    );
    await tester.pumpWidget(_harness(_FakeAccounts(err)));
    await tester.pump();

    // text screentext bannertext text.
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

    // "Sign in with Google" text → issue failed → banner text.
    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    await tester.pump();

    // L1: MALFORMED text minutestext message(text "Failed to connect" text).
    expect(find.textContaining('unexpected response'), findsOneWidget);
    expect(find.text('Failed to connect the account'), findsNothing);
    // L2: diagnostic translated text(code · HTTP status · requestId).
    expect(find.text('MALFORMED_RESPONSE · HTTP 404 · req rq_1'), findsOneWidget);
    // L3: translated text screen prohibited — retry + text manual entry text text.
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Advanced: enter a code manually'), findsWidgets);
  });

  testWidgets('bannertext "text manual entry text" text → banner translated text text text text',
      (tester) async {
    final err = MailApiException(code: 'UNKNOWN', message: 'net');
    await tester.pumpWidget(_harness(_FakeAccounts(err)));
    await tester.pump();
    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    // banner text text translated text text(text text text translated text translated text text text).
    await tester.tap(find.text('Advanced: enter a code manually').first);
    await tester.pump();

    // bannertext translated text text text translated text translated text.
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(find.text('Authorization code'), findsOneWidget);
  });
}
