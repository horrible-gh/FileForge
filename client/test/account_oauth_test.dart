import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/services/account_cache.dart';
import 'package:file_forge_app/services/account_service.dart';
import 'package:file_forge_app/services/mail_envelope.dart';

/// TR0005 — symptom1(text text: translated text translated text + text text text) / symptom2(browser
/// OAuth: consent URL issue)text translated text translated text text stub translated text verifytext.
class _StubAdapter implements HttpClientAdapter {
  final Map<String, (int, Object?)> routes;
  final List<String> calls = [];
  RequestOptions? lastOptions;

  _StubAdapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    final key = '${options.method} ${options.path}';
    calls.add(key);
    final entry = routes[key];
    if (entry == null) {
      return ResponseBody.fromString(
          '{"ok":false,"error":{"code":"MAIL_NOT_FOUND","message":"no route"}}', 404,
          headers: {Headers.contentTypeHeader: ['application/json']});
    }
    final (status, body) = entry;
    final text = body == null ? '' : jsonEncode(body);
    return ResponseBody.fromString(text, status,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_StubAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = adapter;
  return dio;
}

/// textnotetext account text text text(SharedPreferences translated text translated text).
class _MemCache implements AccountPresenceCache {
  bool? value;
  _MemCache([this.value]);
  @override
  Future<bool?> getHasAccounts() async => value;
  @override
  Future<void> setHasAccounts(bool v) async => value = v;
}

void main() {
  group('symptom2 — authorize URL (browser OAuth)', () {
    test('authorizeUrl parses auth_url from the envelope', () async {
      final adapter = _StubAdapter({
        'GET /accounts/oauth/authorize': (200, {
          'ok': true,
          'data': {'auth_url': 'https://accounts.google.com/o/oauth2/v2/auth?x=1', 'state': 'st_1'}
        })
      });
      final svc = AccountService(_dioWith(adapter));
      final url = await svc.authorizeUrl('gmail');
      expect(url, startsWith('https://accounts.google.com/'));
      expect(adapter.calls.single, 'GET /accounts/oauth/authorize');
    });

    test('authorizeUrl maps oauth-not-configured to an exception', () async {
      final svc = AccountService(_dioWith(_StubAdapter({
        'GET /accounts/oauth/authorize': (503, {
          'ok': false,
          'error': {
            'code': 'UPSTREAM_UNAVAILABLE',
            'message': 'unavailable',
            'details': {'reason': 'oauth not configured'}
          }
        })
      })));
      expect(
        () => svc.authorizeUrl('gmail'),
        throwsA(isA<MailApiException>()
            .having((e) => e.code, 'code', 'UPSTREAM_UNAVAILABLE')),
      );
    });

    test('authorizeUrl missing auth_url → MALFORMED_RESPONSE', () async {
      final svc = AccountService(_dioWith(_StubAdapter({
        'GET /accounts/oauth/authorize': (200, {'ok': true, 'data': {'state': 'st'}})
      })));
      expect(
        () => svc.authorizeUrl('gmail'),
        throwsA(isA<MailApiException>()
            .having((e) => e.code, 'code', 'MALFORMED_RESPONSE')),
      );
    });

    test('provider.oauthAuthorizeUrl returns (url,null) on success', () async {
      final p = AccountProvider(_dioWith(_StubAdapter({
        'GET /accounts/oauth/authorize': (200, {
          'ok': true,
          'data': {'auth_url': 'https://login.microsoftonline.com/x', 'state': 's'}
        })
      })));
      final res = await p.oauthAuthorizeUrl('outlook');
      expect(res.url, isNotNull);
      expect(res.error, isNull);
    });

    test('provider.oauthAuthorizeUrl returns (null,error) on failure', () async {
      final p = AccountProvider(_dioWith(_StubAdapter({
        'GET /accounts/oauth/authorize': (400, {
          'ok': false,
          'error': {'code': 'VALIDATION_FAILED', 'message': 'bad', 'details': {'field': 'provider'}}
        })
      })));
      final res = await p.oauthAuthorizeUrl('imap');
      expect(res.url, isNull);
      expect(res.error!.code, 'VALIDATION_FAILED');
    });
  });

  group('symptom1 — translated text translated text', () {
    test('listAccounts carries the short gate timeout', () async {
      final adapter = _StubAdapter({
        'GET /accounts': (200, {'ok': true, 'data': []})
      });
      await AccountService(_dioWith(adapter)).listAccounts();
      expect(adapter.lastOptions!.receiveTimeout, AccountService.kGateTimeout);
      expect(adapter.lastOptions!.sendTimeout, AccountService.kGateTimeout);
      // text 30s text translated text translated text text translated text text.
      expect(adapter.lastOptions!.receiveTimeout!.inSeconds, lessThan(30));
    });
  });

  group('symptom1 — text text text', () {
    test('primeFromCache(true) resolves the gate optimistically before load', () async {
      final p = AccountProvider(
        _dioWith(_StubAdapter({'GET /accounts': (200, {'ok': true, 'data': []})})),
        cache: _MemCache(true),
      );
      final primed = await p.primeFromCache();
      expect(primed, true);
      // translated text text text: screentext text text text translated text ready + hasAccounts.
      expect(p.gate, AccountGateState.ready);
      expect(p.isResolved, true);
      expect(p.hasAccounts, true);
    });

    test('load after optimistic prime never flickers back to loading', () async {
      final p = AccountProvider(
        _dioWith(_StubAdapter({
          'GET /accounts': (200, {
            'ok': true,
            'data': [
              {'account_id': 'a', 'email': 'a@b.c', 'provider': 'gmail', 'status': 'connected'}
            ]
          })
        })),
        cache: _MemCache(true),
      );
      await p.primeFromCache();
      final seen = <AccountGateState>[];
      p.addListener(() => seen.add(p.gate));
      await p.load();
      // translated text text loading(translated text)text translated text translated text.
      expect(seen, isNot(contains(AccountGateState.loading)));
      expect(p.gate, AccountGateState.ready);
      expect(p.hasAccounts, true);
    });

    test('load reconciles a stale "true" cache down to no-accounts + updates cache',
        () async {
      final cache = _MemCache(true);
      final p = AccountProvider(
        _dioWith(_StubAdapter({'GET /accounts': (200, {'ok': true, 'data': []})})),
        cache: cache,
      );
      await p.primeFromCache();
      expect(p.hasAccounts, true); // text(stale)
      await p.load();
      expect(p.hasAccounts, false); // translated text text → translated text
      expect(cache.value, false); // translated text refresh
    });

    test('successful load persists presence to the cache', () async {
      final cache = _MemCache();
      final p = AccountProvider(
        _dioWith(_StubAdapter({
          'GET /accounts': (200, {
            'ok': true,
            'data': [
              {'account_id': 'a', 'email': 'a@b.c', 'provider': 'imap', 'status': 'connected'}
            ]
          })
        })),
        cache: cache,
      );
      await p.load();
      expect(cache.value, true);
    });

    test('primeFromCache is a no-op when nothing cached', () async {
      final p = AccountProvider(
        _dioWith(_StubAdapter({'GET /accounts': (200, {'ok': true, 'data': []})})),
        cache: _MemCache(null),
      );
      expect(await p.primeFromCache(), false);
      expect(p.gate, AccountGateState.unknown);
    });

    test('optimistic view survives a transient reconcile failure (no blackout)',
        () async {
      final p = AccountProvider(
        _dioWith(_StubAdapter({'GET /accounts': (500, {'oops': true})})),
        cache: _MemCache(true),
      );
      await p.primeFromCache();
      await p.load(); // transient failure
      // text errortext text(stale) text screentext keeptext(translated text prohibited).
      expect(p.gate, AccountGateState.ready);
      expect(p.hasAccounts, true);
    });

    test('optimistic view still escalates a 401 to a session error', () async {
      final p = AccountProvider(
        _dioWith(_StubAdapter({
          'GET /accounts': (401, {
            'ok': false,
            'error': {'code': 'TOKEN_INVALID', 'message': 'unauthorized'}
          })
        })),
        cache: _MemCache(true),
      );
      await p.primeFromCache();
      await p.load();
      expect(p.gate, AccountGateState.error);
      expect(p.errorKind, AccountLoadErrorKind.session);
    });
  });
}
