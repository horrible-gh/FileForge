import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/mail_account.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/screens/mail/mail_list_screen.dart';

/// R0001 (fileforge.mailanchorpython.0042) — "전체 읽음 처리와 계정 연동 버튼 사이에
/// 동기화 버튼 하나 추가". Pins the tray sync button:
///   (A) a sync IconButton (Icons.sync_rounded) is rendered in the mail toolbar tray
///       positioned BETWEEN mark-all-read and account-connect,
///   (B) tapping it fires a server sync (POST /sync) via MailProvider.syncRefresh.
class _RecordingAdapter implements HttpClientAdapter {
  final Map<String, (int, Object?)> routes;
  final List<({String method, String path})> calls = [];

  _RecordingAdapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add((method: options.method, path: options.path));
    final entry = routes['${options.method} ${options.path}'];
    if (entry == null) {
      return ResponseBody.fromString(
        '{"ok":true,"data":[],"meta":{"has_more":false}}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        },
      );
    }
    final (status, body) = entry;
    return ResponseBody.fromString(body == null ? '' : jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = adapter;
  return dio;
}

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
  testWidgets(
      'tray sync button sits between mark-all-read and account, and syncs on tap',
      (tester) async {
    final adapter = _RecordingAdapter({
      'POST /sync': (200, {'ok': true, 'data': {}}),
      'GET /mails': (200, {'ok': true, 'data': [], 'meta': {'has_more': false}}),
    });
    final mail = MailProvider(_dioWith(adapter));
    await tester.pumpWidget(_harness(mail, _ConnectedAccountProvider()));

    // Drain the on-mount sync (_enterMail fires syncInbox, which shows a spinner in
    // place of the sync icon) so the idle sync icon is present before we assert/tap.
    final sync = find.byIcon(Icons.sync_rounded);
    for (var i = 0; i < 20 && sync.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    // (A) the sync icon exists and is ordered between mark-all-read and account.
    final markAllRead = find.byIcon(Icons.mark_email_read_rounded);
    final account = find.byIcon(Icons.manage_accounts_rounded);
    expect(markAllRead, findsOneWidget);
    expect(sync, findsOneWidget);
    expect(account, findsOneWidget);
    final markX = tester.getCenter(markAllRead).dx;
    final syncX = tester.getCenter(sync).dx;
    final accountX = tester.getCenter(account).dx;
    expect(markX < syncX, isTrue, reason: 'sync is right of mark-all-read');
    expect(syncX < accountX, isTrue, reason: 'sync is left of account');

    // (B) tapping fires a server sync (POST /sync) via syncRefresh.
    adapter.calls.clear();
    await tester.tap(sync);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(
      adapter.calls.any((c) => c.method == 'POST' && c.path.contains('sync')),
      isTrue,
      reason: 'sync button must POST a server sync',
    );

    // Drain the success-toast timer (AppToast ~2s) so no timer is pending at dispose.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });
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
        MailAccount(accountId: 'acc', email: 'me@gmail.com', provider: 'gmail'),
      ];
}
