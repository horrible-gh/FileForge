import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/services/account_cache.dart';
import 'package:file_forge_app/services/account_service.dart';
import 'package:file_forge_app/services/mail_envelope.dart';

/// TR0005 — 증상1(진입 지연: 게이트 타임아웃 + 캐시 낙관 렌더) / 증상2(브라우저
/// OAuth: 동의 URL 발급)의 로직을 네트워크 없이 stub 어댑터로 검증한다.
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

/// 인메모리 계정 유무 캐시 더블(SharedPreferences 플러그인 불필요).
class _MemCache implements AccountPresenceCache {
  bool? value;
  _MemCache([this.value]);
  @override
  Future<bool?> getHasAccounts() async => value;
  @override
  Future<void> setHasAccounts(bool v) async => value = v;
}

void main() {
  group('증상2 — authorize URL (브라우저 OAuth)', () {
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

  group('증상1 — 게이트 타임아웃', () {
    test('listAccounts carries the short gate timeout', () async {
      final adapter = _StubAdapter({
        'GET /accounts': (200, {'ok': true, 'data': []})
      });
      await AccountService(_dioWith(adapter)).listAccounts();
      expect(adapter.lastOptions!.receiveTimeout, AccountService.kGateTimeout);
      expect(adapter.lastOptions!.sendTimeout, AccountService.kGateTimeout);
      // 전역 30s 가 아니라 게이트용으로 짧게 끊어야 한다.
      expect(adapter.lastOptions!.receiveTimeout!.inSeconds, lessThan(30));
    });
  });

  group('증상1 — 캐시 낙관 렌더', () {
    test('primeFromCache(true) resolves the gate optimistically before load', () async {
      final p = AccountProvider(
        _dioWith(_StubAdapter({'GET /accounts': (200, {'ok': true, 'data': []})})),
        cache: _MemCache(true),
      );
      final primed = await p.primeFromCache();
      expect(primed, true);
      // 네트워크 응답 전: 화면을 즉시 그릴 수 있도록 ready + hasAccounts.
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
      // 재조정 동안 loading(스피너)로 돌아가지 않는다.
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
      expect(p.hasAccounts, true); // 낙관(stale)
      await p.load();
      expect(p.hasAccounts, false); // 실로드로 정정 → 온보딩
      expect(cache.value, false); // 캐시도 갱신
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
      // 일시 오류면 직전(stale) 낙관 화면을 유지한다(블랙아웃 금지).
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
