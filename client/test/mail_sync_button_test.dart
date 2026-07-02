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

  // R0001(0042, rev1) — "동기버튼은 내가 누를때만 돌았으면 좋겠다": the sync button must
  // spin ONLY in response to the user's own tap, never on its own during the
  // background 10s poll / on-mount sync. This pins that the button stays the idle
  // sync icon (not a spinner) even while the provider's global isSyncing is true.
  // Load-bearing: if the button reverts to watching MailProvider.isSyncing, the
  // idle icon disappears (replaced by a spinner) and this fails.
  testWidgets(
      'sync button stays idle while a background/global sync is in flight',
      (tester) async {
    final mail = _AlwaysSyncingMailProvider();
    await tester.pumpWidget(_harness(mail, _ConnectedAccountProvider()));
    await tester.pump(const Duration(milliseconds: 20));

    // The provider reports isSyncing == true the whole time, yet because no tap
    // occurred the button shows the plain sync icon and is NOT a spinner.
    expect(mail.isSyncing, isTrue);
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget,
        reason: 'button must stay idle during background sync (not spin)');

    await tester.pumpWidget(const SizedBox());
  });
}

/// A MailProvider whose global sync state is permanently "in flight" but whose
/// sync methods are inert — used to prove the tray button does not spin off the
/// global isSyncing (only off its own tap).
class _AlwaysSyncingMailProvider extends MailProvider {
  _AlwaysSyncingMailProvider() : super(Dio());

  @override
  bool get isSyncing => true;

  @override
  Future<void> syncInbox({String label = 'inbox', bool quiet = false}) async {}

  @override
  Future<void> syncRefresh() async {}
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
