import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/models/vault.dart';
import 'package:file_forge_app/providers/vault_provider.dart';
import 'package:file_forge_app/services/vault_crypto.dart';
import 'package:file_forge_app/services/vault_local_store.dart';
import 'package:file_forge_app/services/vault_service.dart';

/// A fake bolt server that can also simulate a server outage (transport error).
class _FakeBoltAdapter implements HttpClientAdapter {
  final Map<String, Map<String, String>> store = {};
  bool offline = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    if (offline) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.connectionError);
    }
    if (options.path.endsWith('/bolt/push')) {
      final body = options.data as Map;
      store['${body['data_type']}'] = {
        'content': '${body['content']}',
        'version': '${body['version']}',
      };
      return ResponseBody.fromString('{"status":"success"}', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    }
    if (options.path.endsWith('/bolt/pull')) {
      final items = store.entries
          .map((e) =>
              '{"data_type":"${e.key}","encrypted_data":"${e.value['content']}","version":"${e.value['version']}"}')
          .join(',');
      return ResponseBody.fromString('{"status":"success","data":[$items]}', 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    }
    return ResponseBody.fromString('{}', 404);
  }
}

const _user = 'fileforge';
const _pw = 'P@ssw0rd!';
const _masterHash =
    'dc52268b24cd260ca6bd96da088d5e52cdc8ffc1b212b1e67bbe6150f59c0f03';

({VaultProvider provider, _FakeBoltAdapter adapter, InMemoryVaultLocalStore local})
    _harness() {
  final adapter = _FakeBoltAdapter();
  final local = InMemoryVaultLocalStore();
  final dio = Dio(BaseOptions(baseUrl: 'http://x/fileforge'))
    ..httpClientAdapter = adapter;
  final provider = VaultProvider.withService(VaultService(dio, localStore: local));
  return (provider: provider, adapter: adapter, local: local);
}

void main() {
  test('unlock with the correct password opens the vault (no decrypt error)',
      () async {
    final h = _harness();
    final ok = await h.provider.unlock(_user, _pw);
    expect(ok, isTrue);
    expect(h.provider.isUnlocked, isTrue);
    expect(h.provider.hasDecryptError, isFalse);
    expect(h.provider.isLocalMode, isFalse);
  });

  test('wrong password on an existing vault is flagged and blocks save (anti-clobber, §5-B)',
      () async {
    final h = _harness();
    // server already holds a real blob (locked with the CORRECT key)
    h.adapter.store['password'] = {
      'content': VaultCrypto.lock([
        {'id': 1, 'title': 'real'}
      ], _masterHash),
      'version': '3.0',
    };
    final blobBefore = h.adapter.store['password']!['content'];

    // unlock with the WRONG password → master hash mismatch
    final ok = await h.provider.unlock(_user, 'WRONG-PASSWORD');
    expect(ok, isFalse);
    expect(h.provider.hasDecryptError, isTrue);
    expect(h.provider.error, VaultProvider.decryptBannerMessage);
    // it must NOT look like a clean empty vault to overwrite
    expect(h.provider.passwords, isEmpty);

    // attempting to save is refused — server blob stays intact
    final saved = await h.provider
        .savePassword(const VaultPasswordEntry(id: 2, title: 'oops'));
    expect(saved, isFalse);
    expect(h.provider.error, VaultProvider.decryptBlockedSaveMessage);
    expect(h.adapter.store['password']!['content'], blobBefore);
  });

  test('re-unlocking with the correct password clears the decrypt-error guard',
      () async {
    final h = _harness();
    h.adapter.store['password'] = {
      'content': VaultCrypto.lock([
        {'id': 1, 'title': 'real'}
      ], _masterHash),
      'version': '3.0',
    };
    await h.provider.unlock(_user, 'WRONG-PASSWORD');
    expect(h.provider.hasDecryptError, isTrue);

    final ok = await h.provider.unlock(_user, _pw);
    expect(ok, isTrue);
    expect(h.provider.hasDecryptError, isFalse);
    expect(h.provider.passwords.single.title, 'real');
  });

  test('server unreachable falls back to LOCAL_MODE from the device mirror',
      () async {
    final h = _harness();
    // 1) online: unlock + save → mirrors the blob to the device
    await h.provider.unlock(_user, _pw);
    final saved = await h.provider
        .savePassword(const VaultPasswordEntry(id: 5, title: 'Cached'));
    expect(saved, isTrue);
    expect(h.provider.isLocalMode, isFalse);

    // 2) server goes down → refresh falls back to local store
    h.adapter.offline = true;
    await h.provider.refresh();
    expect(h.provider.isLocalMode, isTrue);
    expect(h.provider.state, VaultState.localMode);
    expect(h.provider.passwords.single.title, 'Cached');
  });

  test('editing while offline saves to the device only, then syncs when online',
      () async {
    final h = _harness();
    await h.provider.unlock(_user, _pw); // empty server vault, online

    // go offline and add an entry → kept on-device (LOCAL_MODE)
    h.adapter.offline = true;
    final saved = await h.provider
        .savePassword(const VaultPasswordEntry(id: 8, title: 'Offline'));
    expect(saved, isTrue);
    expect(h.provider.isLocalMode, isTrue);
    expect(h.adapter.store.containsKey('password'), isFalse); // never reached server

    // back online: an explicit push reconciles the server
    h.adapter.offline = false;
    final synced = await h.provider
        .savePassword(const VaultPasswordEntry(id: 8, title: 'Offline'));
    expect(synced, isTrue);
    expect(h.adapter.store['password']!['content']!.startsWith('U2FsdGVk'),
        isTrue);
  });
}
