import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/services/auth_refresh_interceptor.dart';
import 'package:file_forge_app/services/session_service.dart';

/// Multi-session management, client side (fileforge.default.0004 T3).
///
/// Two things worth pinning:
///   1. SessionService speaks the T2 contract (paths, epoch-seconds decoding,
///      `was_current` / `revoked`).
///   2. A 401 carrying `session_revoked` logs out immediately instead of burning
///      a rotation that cannot succeed (D0003 §7.5).

/// Minimal scriptable adapter: maps "METHOD /path" to a (status, body) pair and
/// records what was asked for.
class _StubAdapter implements HttpClientAdapter {
  final List<String> calls = [];
  final Map<String, (int, Object?)> responses = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    calls.add(key);
    final scripted = responses[key] ?? (404, {'detail': 'not_scripted'});
    return ResponseBody.fromString(
      jsonEncode(scripted.$2),
      scripted.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_StubAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost/fileforge'));
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  group('SessionService', () {
    test('list decodes the session list and the transition flag', () async {
      final adapter = _StubAdapter();
      adapter.responses['GET /auth/sessions'] = (
        200,
        {
          'sessions': [
            {
              'sid': 'aaa',
              'device_label': 'Windows PC',
              'client_type': 'dart/3',
              'ip_display': '203.0.113.9',
              'created_at': 1700000000,
              'last_used_at': 1700003600,
              'is_current': true,
            },
          ],
          'current_sid': 'aaa',
          'session_unavailable': false,
        }
      );

      final result = await SessionService(_dioWith(adapter)).list();

      expect(result.sessionUnavailable, isFalse);
      expect(result.sessions, hasLength(1));
      final session = result.sessions.single;
      expect(session.sid, 'aaa');
      expect(session.deviceLabel, 'Windows PC');
      expect(session.isCurrent, isTrue);
      // Server sends epoch SECONDS; a raw fromMillisecondsSinceEpoch would land in 1970.
      expect(session.lastUsedAt,
          DateTime.fromMillisecondsSinceEpoch(1700003600 * 1000));
    });

    test('a pre-session token reports session_unavailable, not an error', () async {
      final adapter = _StubAdapter();
      adapter.responses['GET /auth/sessions'] = (
        200,
        {'sessions': [], 'current_sid': null, 'session_unavailable': true}
      );

      final result = await SessionService(_dioWith(adapter)).list();

      expect(result.sessions, isEmpty);
      expect(result.sessionUnavailable, isTrue);
    });

    test('revoke targets the sid and surfaces was_current', () async {
      final adapter = _StubAdapter();
      adapter.responses['DELETE /auth/sessions/bbb'] =
          (200, {'revoked': 1, 'was_current': true});

      final wasCurrent = await SessionService(_dioWith(adapter)).revoke('bbb');

      expect(wasCurrent, isTrue);
      expect(adapter.calls, ['DELETE /auth/sessions/bbb']);
    });

    test('revokeOthers returns how many were ended', () async {
      final adapter = _StubAdapter();
      adapter.responses['POST /auth/sessions/revoke-others'] =
          (200, {'revoked': 3});

      final revoked = await SessionService(_dioWith(adapter)).revokeOthers();

      expect(revoked, 3);
    });
  });

  group('device label', () {
    test('is a non-empty ASCII string usable as an HTTP header value', () {
      final label = currentDeviceLabel();
      expect(label, isNotEmpty);
      expect(label.codeUnits.every((c) => c >= 0x20 && c < 0x7F), isTrue,
          reason: 'X-Device-Name travels as a header value');
    });
  });

  group('session_revoked handling', () {
    late _StubAdapter adapter;
    late Dio dio;
    late int rotations;
    late int logouts;

    AuthRefreshInterceptor buildInterceptor() => AuthRefreshInterceptor(
          getAccessToken: () => 'access-token',
          ensureFreshToken: () async {
            rotations++;
            return 'rotated-token';
          },
          isSessionExpired: () => false,
          onSessionExpired: () async {
            logouts++;
          },
        );

    setUp(() {
      adapter = _StubAdapter();
      dio = _dioWith(adapter);
      rotations = 0;
      logouts = 0;
      dio.interceptors.add(buildInterceptor()..dio = dio);
    });

    test('logs out at once and does not attempt a rotation', () async {
      adapter.responses['GET /files'] = (401, {'detail': 'session_revoked'});

      await expectLater(dio.get('/files'), throwsA(isA<DioException>()));

      expect(logouts, 1);
      expect(rotations, 0, reason: 'the refresh token died with the session');
      expect(adapter.calls, ['GET /files']);
    });

    test('an ordinary 401 still goes through the rotation path', () async {
      adapter.responses['GET /files'] = (401, {'detail': 'Token has expired'});

      await expectLater(dio.get('/files'), throwsA(isA<DioException>()));

      expect(rotations, 1);
      expect(logouts, 0);
      // Original call, then the one retry with the rotated token.
      expect(adapter.calls, ['GET /files', 'GET /files']);
    });
  });
}
