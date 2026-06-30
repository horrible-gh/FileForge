import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/models/vault.dart';
import 'package:file_forge_app/services/vault_crypto.dart';
import 'package:file_forge_app/services/vault_local_store.dart';
import 'package:file_forge_app/services/vault_service.dart';

/// A minimal in-memory bolt server that honors (user, data_type) upsert and the
/// {status, data:[{data_type, encrypted_data, version}]} envelope (P0005).
class _FakeBoltAdapter implements HttpClientAdapter {
  final Map<String, Map<String, String>> store = {}; // data_type -> {content, version}

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    if (options.path.endsWith('/bolt/push')) {
      final body = options.data as Map;
      store['${body['data_type']}'] = {
        'content': '${body['content']}',
        'version': '${body['version']}',
      };
      return ResponseBody.fromString(
          '{"status":"success","message":"Data pushed successfully"}', 200,
          headers: {
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

const _masterHash =
    'dc52268b24cd260ca6bd96da088d5e52cdc8ffc1b212b1e67bbe6150f59c0f03';

VaultService _service(_FakeBoltAdapter adapter, {VaultLocalStore? local}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://x/fileforge'));
  dio.httpClientAdapter = adapter;
  return VaultService(dio, localStore: local ?? InMemoryVaultLocalStore());
}

void main() {
  group('mergeCategories (L0006 §2.6)', () {
    test('defaults always present and preserved', () {
      final merged = VaultService.mergeCategories(const [], const []);
      expect(merged.map((c) => c.id),
          containsAll(['work', 'personal', 'entertainment']));
    });

    test('default ids are never overwritten by server', () {
      final server = [
        const VaultCategory(id: 'work', name: 'HACKED', isDefault: false),
      ];
      final merged = VaultService.mergeCategories(const [], server);
      // The default category's canonical (non-localized) name resists the
      // server value; display names are localized in the UI by id (i18n 0003).
      expect(merged.firstWhere((c) => c.id == 'work').name, 'Work');
    });

    test('server custom category wins over local custom on id collision', () {
      final local = [const VaultCategory(id: 'bank', name: 'local-bank')];
      final server = [const VaultCategory(id: 'bank', name: 'server-bank')];
      final merged = VaultService.mergeCategories(local, server);
      expect(merged.firstWhere((c) => c.id == 'bank').name, 'server-bank');
    });
  });

  group('cleanCategories (L0006 §2.7)', () {
    test('drops malformed custom categories, keeps defaults', () {
      final cats = [
        const VaultCategory(id: '', name: 'no-id'),
        const VaultCategory(id: 'x', name: ''),
        const VaultCategory(id: 'bank', name: '은행', icon: '🏦'),
      ];
      final cleaned = VaultService.cleanCategories(cats);
      final ids = cleaned.map((c) => c.id).toSet();
      expect(ids.contains('bank'), isTrue);
      expect(ids.contains('x'), isFalse);
      expect(ids, containsAll(['work', 'personal', 'entertainment']));
    });
  });

  group('pull/push round-trip through the (fake) server', () {
    test('empty server vault → defaults, no passwords', () async {
      final svc = _service(_FakeBoltAdapter());
      final res = await svc.pullVault(_masterHash);
      expect(res.decryptFailed, isFalse);
      expect(res.data.passwords, isEmpty);
      expect(res.data.categories.map((c) => c.id),
          containsAll(['work', 'personal', 'entertainment']));
    });

    test('pushVault then pullVault recovers the same passwords (zero-knowledge)',
        () async {
      final adapter = _FakeBoltAdapter();
      final svc = _service(adapter);
      final data = VaultData(
        passwords: const [
          VaultPasswordEntry(
              id: 1, title: 'Google', username: 'me@x.com', password: 'pw'),
        ],
        categories: List.of(kDefaultVaultCategories),
      );
      await svc.pushVault(data, _masterHash);

      // server stored only opaque Salted__ blobs (never plaintext)
      final stored = adapter.store['password']!['content']!;
      expect(stored.startsWith('U2FsdGVk'), isTrue); // base64("Salted__")
      expect(stored.contains('pw'), isFalse);

      final back = await svc.pullVault(_masterHash);
      expect(back.data.passwords.length, 1);
      expect(back.data.passwords.first.title, 'Google');
      expect(back.data.passwords.first.password, 'pw');
    });

    test('blob encrypted with a different key is skipped AND flagged (L0006 §5-B)',
        () async {
      final adapter = _FakeBoltAdapter();
      // seed a password blob locked with the WRONG key
      final wrong = VaultCrypto.deriveMasterHash('fileforge', 'WRONG');
      adapter.store['password'] = {
        'content': VaultCrypto.lock([
          {'id': 1, 'title': 'ghost'}
        ], wrong),
        'version': '3.0',
      };
      final svc = _service(adapter);
      final res = await svc.pullVault(_masterHash);
      expect(res.data.passwords, isEmpty); // undecryptable → skipped, not crashed
      expect(res.decryptFailed, isTrue); // …and signalled to the caller (notify)
    });
  });

  group('local storage / LOCAL_MODE (L0006 §1.2/§2.4/§2.5/§3.1, P0005 시나리오 7)', () {
    test('deviceVaultKey matches legacy generateVaultKey shape', () {
      final key = VaultCrypto.deviceVaultKey(_masterHash);
      expect(key.startsWith('vault_'), isTrue);
      // "vault_" + SHA256(master hash hex) → 6 + 64 chars
      expect(key.length, 6 + 64);
    });

    test('pushVault mirrors locked blobs to the device store', () async {
      final local = InMemoryVaultLocalStore();
      final svc = _service(_FakeBoltAdapter(), local: local);
      await svc.pushVault(
        VaultData(
          passwords: const [VaultPasswordEntry(id: 7, title: 'Bank')],
          categories: List.of(kDefaultVaultCategories),
        ),
        _masterHash,
      );
      final key = VaultCrypto.deviceVaultKey(_masterHash);
      expect((await local.read(key))!.startsWith('U2FsdGVk'), isTrue);
      expect((await local.read('${key}_categories'))!.startsWith('U2FsdGVk'),
          isTrue);
    });

    test('loadLocalVault opens the device-mirrored vault without the server',
        () async {
      final local = InMemoryVaultLocalStore();
      // push (online) populates the local mirror …
      final svc = _service(_FakeBoltAdapter(), local: local);
      await svc.pushVault(
        VaultData(
          passwords: const [
            VaultPasswordEntry(id: 9, title: 'Mail', password: 'secret')
          ],
          categories: List.of(kDefaultVaultCategories),
        ),
        _masterHash,
      );
      // … now open from local store only (fresh service, no shared adapter state)
      final offline = VaultService(
        Dio(BaseOptions(baseUrl: 'http://x/fileforge')),
        localStore: local,
      );
      final res = await offline.loadLocalVault(_masterHash);
      expect(res.decryptFailed, isFalse);
      expect(res.data.passwords.single.title, 'Mail');
      expect(res.data.passwords.single.password, 'secret');
    });

    test('loadLocalVault with nothing stored → empty vault', () async {
      final svc = _service(_FakeBoltAdapter(), local: InMemoryVaultLocalStore());
      final res = await svc.loadLocalVault(_masterHash);
      expect(res.decryptFailed, isFalse);
      expect(res.data.passwords, isEmpty);
      expect(res.data.categories.map((c) => c.id),
          containsAll(['work', 'personal', 'entertainment']));
    });

    test('loadLocalVault flags decrypt failure on a wrong-key local blob',
        () async {
      final local = InMemoryVaultLocalStore();
      final wrong = VaultCrypto.deriveMasterHash('fileforge', 'WRONG');
      await local.write(VaultCrypto.deviceVaultKey(_masterHash),
          VaultCrypto.lock([{'id': 1}], wrong));
      final svc = _service(_FakeBoltAdapter(), local: local);
      final res = await svc.loadLocalVault(_masterHash);
      expect(res.decryptFailed, isTrue);
    });

    test('pull does NOT mirror locally when a blob fails to decrypt (anti-clobber)',
        () async {
      final local = InMemoryVaultLocalStore();
      final adapter = _FakeBoltAdapter();
      final wrong = VaultCrypto.deriveMasterHash('fileforge', 'WRONG');
      adapter.store['password'] = {
        'content': VaultCrypto.lock([{'id': 1, 'title': 'ghost'}], wrong),
        'version': '3.0',
      };
      final svc = _service(adapter, local: local);
      final res = await svc.pullVault(_masterHash);
      expect(res.decryptFailed, isTrue);
      // the wrong-key re-lock must NOT have been written over local storage
      expect(await local.read(VaultCrypto.deviceVaultKey(_masterHash)), isNull);
    });
  });
}
