import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:file_forge_app/config/app_config.dart';
import 'package:file_forge_app/providers/auth_provider.dart';

/// SecureBolt fileforge.securebolt.0002 / TR0005 요건 2 회귀 가드.
///
/// "비밀번호를 두 번 묻지 마라" — 신선 ID/PW 로그인 시 그 평문 비밀번호로 볼트
/// 마스터 키를 파생해 두어 SecureBolt 진입 시 두 번째 프롬프트가 뜨지 않게 한다.
/// 핵심(load-bearing): 콜백이 **확정된 user.username**(= _UnlockView 와 동일한
/// 키 파생 입력)과 입력 비번으로 정확히 1회 호출되어야 한다. 콜백이 안 불리면
/// (= 이 wiring 이 없으면) 사용자는 로그인 직후 다시 비번을 쳐야 한다.
class _LoginStub implements HttpClientAdapter {
  /// 'POST /login' 및 'POST /login/totp/verify' 응답 (status, jsonBody).
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
      // 입력 username 은 이메일이지만 서버가 돌려주는 user_name 은 'alice'.
      'POST /login': (200, _session('alice')),
    });

    final captured = <(String, String)>[];
    auth.setVaultUnlockCallback((u, p) async => captured.add((u, p)));

    final result = await auth.login('alice@example.com', 'pw-secret');
    // unlock 콜백은 fire-and-forget — microtask 가 돌도록 한 틱 양보.
    await Future<void>.delayed(Duration.zero);

    expect(result, LoginResult.success);
    // load-bearing: 정확히 1회, 확정된 user_name('alice')과 입력 비번으로.
    expect(captured.length, 1);
    expect(captured.single.$1, 'alice'); // raw 'alice@example.com' 아님
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
    // TOTP 단계에서는 아직 세션 미확정 → 키 파생 금지.
    expect(r1, LoginResult.totpRequired);
    expect(captured, isEmpty);

    await auth.verifyTotp('TT', '123456');
    await Future<void>.delayed(Duration.zero);
    // 확정 후 보관해 둔 비번으로 1회 파생.
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
