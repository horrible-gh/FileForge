import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/models/vault.dart';
import 'package:file_forge_app/services/vault_crypto.dart';
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

VaultService _service(_FakeBoltAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://x/fileforge'));
  dio.httpClientAdapter = adapter;
  return VaultService(dio);
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
      expect(merged.firstWhere((c) => c.id == 'work').name, '업무');
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
      final data = await svc.pullVault(_masterHash);
      expect(data.passwords, isEmpty);
      expect(data.categories.map((c) => c.id),
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
      expect(back.passwords.length, 1);
      expect(back.passwords.first.title, 'Google');
      expect(back.passwords.first.password, 'pw');
    });

    test('blob encrypted with a different key is skipped on pull (L0006 §5-B)',
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
      final data = await svc.pullVault(_masterHash);
      expect(data.passwords, isEmpty); // undecryptable → skipped, not crashed
    });
  });
}
