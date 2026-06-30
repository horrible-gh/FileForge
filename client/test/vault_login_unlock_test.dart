import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:file_forge_app/config/app_config.dart';
import 'package:file_forge_app/providers/auth_provider.dart';

/// SecureBolt fileforge.securebolt.0002 / TR0005 requirement-2 regression guard.
///
/// "Don't ask for the password twice" — on a fresh ID/PW login, derive the vault master
/// key from that plaintext password up front so no second prompt appears on entering SecureBolt.
/// load-bearing: the callback must be invoked exactly once with the **resolved user.username**
/// (= the same key-derivation input as _UnlockView) and the entered password. If the callback
/// is not called (= this wiring is missing), the user has to retype the password right after login.
class _LoginStub implements HttpClientAdapter {
  /// Responses for 'POST /login' and 'POST /login/totp/verify' (status, jsonBody).
  final Map<String, (int, Object?)> routes;
  final List<String> calls = [];

  _LoginStub(this.routes);

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
      return ResponseBody.fromString('{"detail":"no route"}', 404,
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

/// flutter_secure_storage in-memory mock (AuthProvider persistence under test).
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

Map<String, dynamic> _session(String userName) => {
      'access_token': 'AX',
      'refresh_token': 'RX',
      'token_type': 'bearer',
      'user': {
        'user_id': 'fileforge',
        'user_name': userName,
        'user_uuid': 'uuid-1',
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockSecureStore store;
  setUp(() => store = _MockSecureStore()..install());

  test('fresh login primes the vault key once, with resolved username + password',
      () async {
    final auth = AuthProvider();
    auth.dio.httpClientAdapter = _LoginStub({
      // The entered username is an email, but the user_name the server returns is 'alice'.
      'POST /login': (200, _session('alice')),
    });

    final captured = <(String, String)>[];
    auth.setVaultUnlockCallback((u, p) async => captured.add((u, p)));

    final result = await auth.login('alice@example.com', 'pw-secret');
    // The unlock callback is fire-and-forget — yield one tick so the microtask runs.
    await Future<void>.delayed(Duration.zero);

    expect(result, LoginResult.success);
    // load-bearing: exactly once, with the resolved user_name ('alice') and the entered password.
    expect(captured.length, 1);
    expect(captured.single.$1, 'alice'); // not the raw 'alice@example.com'
    expect(captured.single.$2, 'pw-secret');
    expect(store.data[AppConfig.keyUsername], 'alice');
  });

  test('login succeeds even when no vault-unlock callback is registered',
      () async {
    final auth = AuthProvider();
    auth.dio.httpClientAdapter = _LoginStub({
      'POST /login': (200, _session('bob')),
    });

    final result = await auth.login('bob', 'pw');
    await Future<void>.delayed(Duration.zero);
    expect(result, LoginResult.success);
  });

  test('TOTP: key is primed only after verifyTotp, with the stashed password',
      () async {
    final auth = AuthProvider();
    auth.dio.httpClientAdapter = _LoginStub({
      'POST /login': (200, {'totp_required': true, 'temp_token': 'TT'}),
      'POST /login/totp/verify': (200, _session('carol')),
    });

    final captured = <(String, String)>[];
    auth.setVaultUnlockCallback((u, p) async => captured.add((u, p)));

    final r1 = await auth.login('carol', 'pw-2fa');
    await Future<void>.delayed(Duration.zero);
    // At the TOTP step the session is not yet confirmed → no key derivation.
    expect(r1, LoginResult.totpRequired);
    expect(captured, isEmpty);

    await auth.verifyTotp('TT', '123456');
    await Future<void>.delayed(Duration.zero);
    // After confirmation, derive once with the stashed password.
    expect(captured.length, 1);
    expect(captured.single.$1, 'carol');
    expect(captured.single.$2, 'pw-2fa');
  });

  test('TOTP: a failed verify never primes the key (stashed password dropped)',
      () async {
    final auth = AuthProvider();
    auth.dio.httpClientAdapter = _LoginStub({
      'POST /login': (200, {'totp_required': true, 'temp_token': 'TT'}),
      'POST /login/totp/verify': (401, {'detail': 'invalid_code'}),
    });

    final captured = <(String, String)>[];
    auth.setVaultUnlockCallback((u, p) async => captured.add((u, p)));

    await auth.login('dave', 'pw');
    await expectLater(
      auth.verifyTotp('TT', '000000'),
      throwsA(anything),
    );
    await Future<void>.delayed(Duration.zero);
    expect(captured, isEmpty);
  });
}
