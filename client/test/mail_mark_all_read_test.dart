import 'dart:convert';
import 'dart:typed_data';
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

/// R0001 (fileforge.mailanchorpython.0030) — "읽은/안읽은 구분이 안 보인다 + 전체
/// 읽음처리 기능 없음". Pins both halves of the fix:
///   (A) MailProvider.markAllRead POSTs /mails/mark-all-read, clears every loaded
///       summary's unread flag locally, and reports the server count.
///   (B) the list tile renders an *extra* unread cue (accent dot + row tint) beyond
///       the pre-existing bold, and a read row carries neither.
class _RecordingAdapter implements HttpClientAdapter {
  final Map<String, (int, Object?)> routes;
  final List<({String method, Uri uri})> calls = [];

  _RecordingAdapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add((method: options.method, uri: options.uri));
    final entry = routes['${options.method} ${options.path}'];
    if (entry == null) {
      return ResponseBody.fromString(
        '{"ok":false,"error":{"code":"MAIL_NOT_FOUND","message":"no route"}}',
        404,
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

Map<String, Object?> _item(String id, {required bool read}) => {
      'mail_id': id,
      'subject': 'subject-$id',
      'snippet': '',
      'from': {'name': 'A', 'address': 'a@b.c'},
      'is_read': read,
      'labels': ['inbox'],
    };

Object _page(List<Map<String, Object?>> items) => {
      'ok': true,
      'data': items,
      'meta': {'has_more': false},
    };

void main() {
  group('MailProvider.markAllRead (R0001/0030)', () {
    test('POSTs mark-all-read, clears unread locally, returns server count',
        () async {
      final adapter = _RecordingAdapter({
        'GET /mails': (
          200,
          _page([
            _item('m1', read: false),
            _item('m2', read: false),
            _item('m3', read: true),
          ])
        ),
        'POST /mails/mark-all-read': (200, {
          'ok': true,
          'data': {'updated': 2}
        }),
      });
      final provider = MailProvider(_dioWith(adapter));
      await provider.loadInbox();
      expect(provider.mails.where((m) => !m.isRead).length, 2);

      final updated = await provider.markAllRead();

      // server-reported count is surfaced to the caller
      expect(updated, 2);
      // the bulk endpoint was hit with POST
      final last = adapter.calls.last;
      expect(last.method, 'POST');
      expect(last.uri.path, '/mails/mark-all-read');
      // every loaded summary is now read → the unread cue clears without a reload
      expect(provider.mails.every((m) => m.isRead), isTrue);
    });

    test('failure leaves local state intact and returns -1', () async {
      final adapter = _RecordingAdapter({
        'GET /mails': (200, _page([_item('m1', read: false)])),
        'POST /mails/mark-all-read': (
          500,
          {
            'ok': false,
            'error': {'code': 'UPSTREAM_UNAVAILABLE', 'message': 'boom'}
          }
        ),
      });
      final provider = MailProvider(_dioWith(adapter));
      await provider.loadInbox();

      final updated = await provider.markAllRead();

      expect(updated, -1);
      // unchanged: the one unread mail is still unread (no optimistic flip on failure)
      expect(provider.mails.single.isRead, isFalse);
    });
  });

  group('unread visual cue (R0001/0030)', () {
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

    testWidgets('unread row gets a tileColor tint; read row does not',
        (tester) async {
      final mails = [
        MailSummary.fromJson(_item('u', read: false)),
        MailSummary.fromJson(_item('r', read: true)),
      ];
      await tester.pumpWidget(harness(_FixedMailProvider(mails)));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      ListTile tileFor(String id) => tester.widget<ListTile>(
            find.ancestor(
              of: find.text('subject-$id'),
              matching: find.byType(ListTile),
            ),
          );

      // unread row carries the surface tint, read row is untinted (null) — the
      // contrast is the extra always-visible cue R0001 asked for beyond bold.
      expect(tileFor('u').tileColor, isNotNull);
      expect(tileFor('r').tileColor, isNull);

      await tester.pumpWidget(const SizedBox());
    });
  });
}

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
        MailAccount(accountId: 'acc', email: 'me@gmail.com', provider: 'gmail'),
      ];
}
