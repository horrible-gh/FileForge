import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/services/mail_service.dart';

/// R0001 — receive sync trigger (TR0005). Root cause: the client never called `POST /sync`
/// (and the server had no background worker either), so the inbox stayed empty forever.
/// This test pins (1) MailService.triggerSync parsing, (2) MailProvider.syncInbox calling
/// sync→list in that order on inbox and skipping sync on other labels, and (3) sync failure
/// being best-effort (the local list still loads).
class _StubAdapter implements HttpClientAdapter {
  /// (METHOD path) → (status, jsonBody).
  final Map<String, (int, Object?)> routes;
  final List<String> calls = [];
  bool failSync;

  _StubAdapter(this.routes, {this.failSync = false});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    calls.add(key);
    if (failSync && key == 'POST /sync') {
      throw DioException(requestOptions: options, message: 'boom');
    }
    final entry = routes[key];
    if (entry == null) {
      return ResponseBody.fromString(
          '{"ok":false,"error":{"code":"MAIL_NOT_FOUND","message":"no route"}}', 404,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    }
    final (status, body) = entry;
    final text = body == null ? '' : jsonEncode(body);
    return ResponseBody.fromString(text, status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_StubAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = adapter;
  return dio;
}

const _emptyInbox = (200, {
  'ok': true,
  'data': <dynamic>[],
  'meta': {'has_more': false}
});

void main() {
  group('MailService.triggerSync', () {
    test('parses {state, applied, reauth_required} from the §7.15 envelope', () async {
      final svc = MailService(_dioWith(_StubAdapter({
        'POST /sync': (
          202,
          {
            'ok': true,
            'data': {'state': 'idle', 'started_at': 'x', 'applied': 3}
          }
        ),
      })));
      final r = await svc.triggerSync();
      expect(r.state, 'idle');
      expect(r.applied, 3);
      expect(r.reauthRequired, false);
    });

    test('surfaces reauth_required when the server flips the account', () async {
      final svc = MailService(_dioWith(_StubAdapter({
        'POST /sync': (
          202,
          {
            'ok': true,
            'data': {'state': 'error', 'applied': 0, 'reauth_required': true}
          }
        ),
      })));
      final r = await svc.triggerSync();
      expect(r.reauthRequired, true);
    });

    test('parses per-account errors[] (B0001/0037 H2: failures no longer silent)',
        () async {
      final svc = MailService(_dioWith(_StubAdapter({
        'POST /sync': (
          200,
          {
            'ok': true,
            'data': {
              'state': 'idle',
              'applied': 2,
              'reauth_required': false,
              'errors': [
                {
                  'account_id': 'acc-bad',
                  'email': 'bad@example.com',
                  'message': 'IMAP 연결 실패: too many connections'
                }
              ]
            }
          }
        ),
      })));
      final r = await svc.triggerSync();
      expect(r.applied, 2);
      expect(r.accountErrors, hasLength(1));
      expect(r.accountErrors.first.accountId, 'acc-bad');
      expect(r.accountErrors.first.email, 'bad@example.com');
      expect(r.accountErrors.first.message, contains('too many connections'));
    });

    test('absent errors[] yields an empty accountErrors list (clean sync)',
        () async {
      final svc = MailService(_dioWith(_StubAdapter({
        'POST /sync': (202, {'ok': true, 'data': {'state': 'idle', 'applied': 0}}),
      })));
      final r = await svc.triggerSync();
      expect(r.accountErrors, isEmpty);
    });
  });

  group('MailProvider.syncInbox', () {
    test('inbox: triggers POST /sync BEFORE GET /mails (receiving is pulled)', () async {
      final adapter = _StubAdapter({
        'POST /sync': (202, {'ok': true, 'data': {'state': 'idle', 'applied': 1}}),
        'GET /mails': _emptyInbox,
      });
      final provider = MailProvider(_dioWith(adapter));
      await provider.syncInbox();
      expect(adapter.calls, ['POST /sync', 'GET /mails']);
      expect(provider.isSyncing, false);
    });

    test('non-inbox label skips sync and only lists locally', () async {
      final adapter = _StubAdapter({
        'POST /sync': (202, {'ok': true, 'data': {'state': 'idle', 'applied': 0}}),
        'GET /mails': _emptyInbox,
      });
      final provider = MailProvider(_dioWith(adapter));
      await provider.syncInbox(label: 'sent');
      expect(adapter.calls, ['GET /mails']);
      expect(adapter.calls, isNot(contains('POST /sync')));
    });

    test('sync failure is best-effort: inbox still loads', () async {
      final adapter = _StubAdapter({
        'GET /mails': _emptyInbox,
      }, failSync: true);
      final provider = MailProvider(_dioWith(adapter));
      await provider.syncInbox();
      // sync threw, but the local list load still ran and no error surfaced.
      expect(adapter.calls, ['POST /sync', 'GET /mails']);
      expect(provider.error, isNull);
      expect(provider.isSyncing, false);
    });

    test('exposes per-account sync errors (B0001/0037 H2) for the banner', () async {
      final adapter = _StubAdapter({
        'POST /sync': (
          200,
          {
            'ok': true,
            'data': {
              'state': 'idle',
              'applied': 0,
              'errors': [
                {'account_id': 'acc-x', 'email': 'x@e.com', 'message': 'IMAP 거부'}
              ]
            }
          }
        ),
        'GET /mails': _emptyInbox,
      });
      final provider = MailProvider(_dioWith(adapter));
      await provider.syncInbox();
      expect(provider.syncAccountErrors, hasLength(1));
      expect(provider.syncAccountErrors.first.accountId, 'acc-x');
      // A clean follow-up sync clears the surfaced errors.
      adapter.routes['POST /sync'] =
          (202, {'ok': true, 'data': {'state': 'idle', 'applied': 0}});
      await provider.syncInbox();
      expect(provider.syncAccountErrors, isEmpty);
    });
  });
}
