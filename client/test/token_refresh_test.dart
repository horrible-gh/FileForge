import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/config/app_config.dart';
import 'package:file_forge_app/providers/auth_provider.dart';
import 'package:file_forge_app/services/auth_service.dart';
import 'package:file_forge_app/services/mail_api_client.dart';

/// R0001 "팅김?" / NR0003 (F1 in-memory refresh desync, F2 dual-Dio concurrent
/// rotation race) / L0004 (3rd-gen token manager). These tests pin the fix:
///   - F1: every rotation replaces BOTH the in-memory and stored refresh token,
///         so the next rotation sends the *rotated* token (not the retired one).
///   - F2: both Dios (file + mail) share ONE coalesced in-flight rotation, so a
///         simultaneous 401 on each POSTs /login/refresh exactly once.
///   - L0004 §2.4: a real 401 ends the session; a transient network error keeps
///         it (and retries), failing only the one request.
///   - end-to-end: a protected 401 is transparently refreshed-and-retried.

/// Capturing stub adapter. Records the refresh_token sent on each
/// POST /login/refresh and serves scriptable responses. A single instance can be
/// shared by several Dios to prove cross-client coalescing.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter();

  /// refresh_token strings seen on POST /login/refresh, in order.
  final List<String> sentRefreshTokens = [];

  /// Count of every request path hit (for assertions on call counts).
  final List<String> calls = [];

  /// Sequence of rotation behaviours, popped per /login/refresh call.
  /// Each entry returns a (status, jsonBody-or-null). A null entry throws a
  /// connection-style DioException (no response) to simulate a network blip.
  final List<(int, Object?)?> refreshScript = [];

  /// Optional artificial delay so concurrent callers overlap the in-flight call.
  Duration refreshDelay = Duration.zero;

  /// Per-path scripted responses for protected endpoints (e.g. GET /files).
  /// Each path maps to a queue of (status, body) consumed in order.
  final Map<String, List<(int, Object?)>> pathScript = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    calls.add(key);

    if (options.path.contains('/login/refresh')) {
      // Decode the request body to capture which refresh token was sent.
      final bodyBytes = <int>[];
      if (requestStream != null) {
        await for (final chunk in requestStream) {
          bodyBytes.addAll(chunk);
        }
      }
      try {
        final decoded = jsonDecode(utf8.decode(bodyBytes)) as Map;
        sentRefreshTokens.add(decoded['refresh_token'] as String);
      } catch (_) {
        sentRefreshTokens.add('<unparseable>');
      }
      if (refreshDelay > Duration.zero) {
        await Future<void>.delayed(refreshDelay);
      }
      final next = refreshScript.isNotEmpty
          ? refreshScript.removeAt(0)
          : (200, _rotation());
      if (next == null) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'simulated network blip',
        );
      }
      return _json(next.$1, next.$2);
    }

    // Protected-endpoint script.
    final queue = pathScript[options.path];
    if (queue != null && queue.isNotEmpty) {
      final (status, body) = queue.removeAt(0);
      if (status == 401) {
        throw DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 401, data: body),
          type: DioExceptionType.badResponse,
        );
      }
      return _json(status, body);
    }
    return _json(404, {'detail': 'no route'});
  }

  int _rot = 0;
  Map<String, Object?> _rotation() {
    _rot++;
    return {
      'access_token': 'A$_rot',
      'refresh_token': 'R$_rot',
      'token_type': 'bearer',
    };
  }

  ResponseBody _json(int status, Object? body) {
    final text = body == null ? '' : jsonEncode(body);
    return ResponseBody.fromString(text, status,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

/// In-memory mock for flutter_secure_storage so AuthProvider persistence works
/// under flutter_test without a platform.
class _MockSecureStore {
  final Map<String, String> data = {};

  void install() {
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'write':
          data[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return data[args['key'] as String];
        case 'delete':
          data.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          data.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(data);
        case 'containsKey':
          return data.containsKey(args['key'] as String);
      }
      return null;
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService.rotateToken (F1 wire + error classification)', () {
    Dio dioWith(_StubAdapter a) {
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.httpClientAdapter = a;
      return dio;
    }

    test('parses rotated access+refresh pair', () async {
      final a = _StubAdapter()..refreshScript.add((200, {
            'access_token': 'AX',
            'refresh_token': 'RX',
            'token_type': 'bearer',
          }));
      final pair = await AuthService(dioWith(a)).rotateToken('R0');
      expect(pair.accessToken, 'AX');
      expect(pair.refreshToken, 'RX');
      expect(a.sentRefreshTokens, ['R0']);
    });

    test('HTTP 401 → RefreshExpiredException', () async {
      final a = _StubAdapter()..refreshScript.add((401, {'detail': 'expired'}));
      expect(
        () => AuthService(dioWith(a)).rotateToken('R0'),
        throwsA(isA<RefreshExpiredException>()),
      );
    });

    test('network blip → RefreshNetworkException', () async {
      final a = _StubAdapter()..refreshScript.add(null); // connection error
      expect(
        () => AuthService(dioWith(a)).rotateToken('R0'),
        throwsA(isA<RefreshNetworkException>()),
      );
    });

    test('5xx → RefreshNetworkException (transient, not expiry)', () async {
      final a = _StubAdapter()..refreshScript.add((503, {'detail': 'down'}));
      expect(
        () => AuthService(dioWith(a)).rotateToken('R0'),
        throwsA(isA<RefreshNetworkException>()),
      );
    });
  });

  group('AuthProvider rotation persistence + coalescing', () {
    late _MockSecureStore store;

    setUp(() {
      store = _MockSecureStore()..install();
    });

    test('F1: in-memory refresh is replaced — 2nd rotation sends rotated token',
        () async {
      store.data[AppConfig.keyRefreshToken] = 'R0';
      final auth = AuthProvider();
      final adapter = _StubAdapter();
      auth.dio.httpClientAdapter = adapter; // AuthService shares this dio

      final t1 = await auth.ensureFreshToken();
      final t2 = await auth.ensureFreshToken();

      expect(t1, 'A1');
      expect(t2, 'A2');
      // The retired R0 is sent once; the SECOND call must send the rotated R1,
      // not R0 again. This is the exact desync that was NR0003 F1.
      expect(adapter.sentRefreshTokens, ['R0', 'R1']);
      expect(auth.refreshToken, 'R2');
      expect(store.data[AppConfig.keyRefreshToken], 'R2');
      expect(store.data[AppConfig.keyAccessToken], 'A2');
    });

    test('F2: concurrent callers coalesce into ONE rotation', () async {
      store.data[AppConfig.keyRefreshToken] = 'R0';
      final auth = AuthProvider();
      final adapter = _StubAdapter()..refreshDelay = const Duration(milliseconds: 30);
      auth.dio.httpClientAdapter = adapter;

      // Fire two rotations in the same microtask — they must share one future.
      final results = await Future.wait([
        auth.ensureFreshToken(),
        auth.ensureFreshToken(),
      ]);

      expect(results, ['A1', 'A1']); // same access token from one rotation
      expect(adapter.sentRefreshTokens, ['R0']); // exactly one POST
    });

    test('F2: file Dio + mail Dio 401 simultaneously → single rotation',
        () async {
      store.data[AppConfig.keyRefreshToken] = 'R0';
      store.data[AppConfig.keyAccessToken] = 'A0';
      final auth = AuthProvider();

      // Shared stub adapter across BOTH Dios so we count rotations globally.
      final shared = _StubAdapter()..refreshDelay = const Duration(milliseconds: 30);
      shared.pathScript['/files'] = [(401, {'detail': 'expired access'}), (200, {'ok': true})];
      shared.pathScript['/mail/list'] = [(401, {'detail': 'expired access'}), (200, {'ok': true})];

      auth.dio.httpClientAdapter = shared;
      final mail = MailApiClient()
        ..configure(
          getAccessToken: () => auth.accessToken,
          ensureFreshToken: auth.ensureFreshToken,
          isSessionExpired: () => auth.lastRefreshWasExpired,
          onSessionExpired: auth.handleSessionExpired,
        );
      mail.dio.httpClientAdapter = shared;

      // Both Dios hit a 401 on their first protected call; each interceptor
      // funnels into the shared coalesced rotation, which must POST once.
      final fileReq = auth.dio.get('/files');
      final mailReq = mail.dio.get('/mail/list');
      final responses = await Future.wait([fileReq, mailReq]);

      expect(responses[0].statusCode, 200);
      expect(responses[1].statusCode, 200);
      // Both 401s funneled through one coalesced rotation: exactly one refresh.
      expect(shared.sentRefreshTokens.length, 1);
      expect(shared.sentRefreshTokens.single, 'R0');
    });

    test('L0004 §2.4: real 401 ends session', () async {
      store.data[AppConfig.keyRefreshToken] = 'R0';
      final auth = AuthProvider();
      final adapter = _StubAdapter()..refreshScript.add((401, {'detail': 'revoked'}));
      auth.dio.httpClientAdapter = adapter;

      final token = await auth.ensureFreshToken();
      expect(token, isNull);
      expect(auth.lastRefreshWasExpired, isTrue);
    });

    test('L0004 §2.4: transient network error keeps session (retries then gives up)',
        () async {
      store.data[AppConfig.keyRefreshToken] = 'R0';
      final auth = AuthProvider();
      // initial + 2 retries all blip → transient, not expiry.
      final adapter = _StubAdapter()..refreshScript.addAll([null, null, null]);
      auth.dio.httpClientAdapter = adapter;

      final token = await auth.ensureFreshToken();
      expect(token, isNull);
      expect(auth.lastRefreshWasExpired, isFalse); // session NOT torn down
      expect(adapter.sentRefreshTokens.length, 3); // initial + 2 retries
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
