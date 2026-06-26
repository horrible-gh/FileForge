import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/providers/mail_provider.dart';
import 'package:file_forge_app/services/mail_service.dart';

/// R0001 — 수신 동기화 트리거(TR0005). 근본원인: 클라이언트가 `POST /sync`를 전혀
/// 호출하지 않아(서버에도 백그라운드 워커 없음) 받은편지함이 영영 비어 있었다.
/// 이 테스트는 (1) MailService.triggerSync 파싱, (2) MailProvider.syncInbox 가
/// inbox에서 sync→list 순으로 호출하고 그 외 라벨에선 sync를 건너뛰며, (3) sync 실패가
/// best-effort(로컬 목록은 그대로 로드)임을 고정한다.
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
  });
}
