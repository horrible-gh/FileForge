import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/providers/account_provider.dart';
import 'package:file_forge_app/services/account_service.dart';

/// 계정 서비스/Provider — TS0006 시나리오 1~3(목록 게이트·연결·해제).
///
/// 네트워크 없이 서버 응답을 흉내내는 stub HttpClientAdapter 로 실 봉투 파싱과
/// 에러 코드 분기를 그대로 검증한다(http_mock_adapter 의존성 미추가).
class _StubAdapter implements HttpClientAdapter {
  /// (METHOD path) → (status, jsonBody). path 는 쿼리 제외.
  final Map<String, (int, Object?)> routes;
  final List<String> calls = [];

  _StubAdapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    calls.add(key);
    final entry = routes[key];
    if (entry == null) {
      return ResponseBody.fromString('{"ok":false,"error":{"code":"MAIL_NOT_FOUND","message":"no route"}}', 404,
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

void main() {
  group('AccountService', () {
    test('listAccounts parses the §3.6 wire shape', () async {
      final svc = AccountService(_dioWith(_StubAdapter({
        'GET /accounts': (200, {
          'ok': true,
          'data': [
            {
              'account_id': 'acc_1',
              'email': 'me@example.com',
              'provider': 'gmail',
              'status': 'connected',
              'connected_at': '2026-06-22T00:00:00Z'
            }
          ]
        })
      })));
      final list = await svc.listAccounts();
      expect(list, hasLength(1));
      expect(list.first.email, 'me@example.com');
      expect(list.first.provider, 'gmail');
      expect(list.first.isConnected, true);
    });

    test('connectAccount maps oauth-not-configured error code', () async {
      final svc = AccountService(_dioWith(_StubAdapter({
        'POST /accounts': (503, {
          'ok': false,
          'error': {
            'code': 'UPSTREAM_UNAVAILABLE',
            'message': 'unavailable',
            'details': {'reason': 'oauth not configured'}
          }
        })
      })));
      // 봉투 에러는 던지지 않고 받아 MailApiException 으로 환원되어야 한다.
      expect(
        () => svc.connectAccount(provider: 'gmail', authCode: 'x'),
        throwsA(isA<Object>().having((e) => '$e', 'msg', contains('UPSTREAM_UNAVAILABLE'))),
      );
    });
  });

  group('AccountProvider gate', () {
    test('load with ≥1 account → ready + hasAccounts', () async {
      final p = AccountProvider(_dioWith(_StubAdapter({
        'GET /accounts': (200, {
          'ok': true,
          'data': [
            {'account_id': 'a', 'email': 'a@b.c', 'provider': 'imap', 'status': 'connected'}
          ]
        })
      })));
      await p.load();
      expect(p.gate, AccountGateState.ready);
      expect(p.isResolved, true);
      expect(p.hasAccounts, true);
    });

    test('load with 0 accounts → ready but no accounts (onboarding)', () async {
      final p = AccountProvider(_dioWith(_StubAdapter({
        'GET /accounts': (200, {'ok': true, 'data': []})
      })));
      await p.load();
      expect(p.gate, AccountGateState.ready);
      expect(p.hasAccounts, false);
    });

    test('load transport failure → error gate (distinct from no-account)', () async {
      final p = AccountProvider(_dioWith(_StubAdapter({
        // 5xx without an ok-envelope body → real failure path.
        'GET /accounts': (500, {'oops': true})
      })));
      await p.load();
      expect(p.gate, AccountGateState.error);
      expect(p.isResolved, false);
      expect(p.error, isNotNull);
      // NR0004 §4: a 5xx/network failure is transient, not a session problem.
      expect(p.errorKind, AccountLoadErrorKind.transient);
    });

    test('load 401 → error gate classified as session (NR0004 §4·§2)', () async {
      // Bridge OFF / expired token → RequireAuth 401. Must read as "re-login",
      // not as "mail account read failure" — kept distinct from transient.
      final p = AccountProvider(_dioWith(_StubAdapter({
        'GET /accounts': (401, {
          'ok': false,
          'error': {'code': 'TOKEN_INVALID', 'message': 'unauthorized'}
        })
      })));
      await p.load();
      expect(p.gate, AccountGateState.error);
      expect(p.errorKind, AccountLoadErrorKind.session);
    });

    test('load 403 → error gate classified as session', () async {
      final p = AccountProvider(_dioWith(_StubAdapter({
        'GET /accounts': (403, {
          'ok': false,
          'error': {'code': 'FORBIDDEN', 'message': 'forbidden'}
        })
      })));
      await p.load();
      expect(p.gate, AccountGateState.error);
      expect(p.errorKind, AccountLoadErrorKind.session);
    });

    test('reset clears the error kind', () async {
      final p = AccountProvider(_dioWith(_StubAdapter({
        'GET /accounts': (500, {'oops': true})
      })));
      await p.load();
      expect(p.errorKind, isNotNull);
      p.reset();
      expect(p.errorKind, isNull);
      expect(p.gate, AccountGateState.unknown);
    });

    test('connect success appends the account and returns null', () async {
      final p = AccountProvider(_dioWith(_StubAdapter({
        'POST /accounts': (201, {
          'ok': true,
          'data': {'account_id': 'new', 'email': 'new@x.io', 'provider': 'outlook', 'status': 'connected'}
        })
      })));
      final err = await p.connect(provider: 'outlook', authCode: 'code');
      expect(err, isNull);
      expect(p.hasAccounts, true);
      expect(p.accounts.single.email, 'new@x.io');
    });

    test('connect conflict returns the classified exception, no append', () async {
      final p = AccountProvider(_dioWith(_StubAdapter({
        'POST /accounts': (409, {
          'ok': false,
          'error': {'code': 'ACCOUNT_DUPLICATE', 'message': 'dup', 'details': {'email': 'dup@x.io'}}
        })
      })));
      final err = await p.connect(provider: 'gmail', authCode: 'code');
      expect(err, isNotNull);
      expect(err!.code, 'ACCOUNT_DUPLICATE');
      expect(p.hasAccounts, false);
    });

    test('remove deletes the account on 204', () async {
      final adapter = _StubAdapter({
        'GET /accounts': (200, {
          'ok': true,
          'data': [
            {'account_id': 'gone', 'email': 'g@x.io', 'provider': 'imap', 'status': 'connected'}
          ]
        }),
        'DELETE /accounts/gone': (204, null),
      });
      final p = AccountProvider(_dioWith(adapter));
      await p.load();
      expect(p.hasAccounts, true);
      final ok = await p.remove('gone');
      expect(ok, true);
      expect(p.hasAccounts, false);
    });
  });
}
