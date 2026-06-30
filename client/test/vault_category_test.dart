import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/models/vault.dart';
import 'package:file_forge_app/providers/vault_provider.dart';
import 'package:file_forge_app/services/vault_local_store.dart';
import 'package:file_forge_app/services/vault_service.dart';

/// SecureBolt fileforge.securebolt.0004 / R0001 — category (분류) add/manage +
/// category-based viewing. Guards the provider behaviors the new UI relies on:
/// category CRUD, count badges, the active filter, and (legacy parity) re-homing
/// a deleted category's entries to the 'personal' default rather than losing them.
class _FakeBoltAdapter implements HttpClientAdapter {
  final Map<String, Map<String, String>> store = {};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
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

VaultProvider _harness() {
  final dio = Dio(BaseOptions(baseUrl: 'http://x/fileforge'))
    ..httpClientAdapter = _FakeBoltAdapter();
  return VaultProvider.withService(
      VaultService(dio, localStore: InMemoryVaultLocalStore()));
}

void main() {
  const custom = VaultCategory(
      id: 'cat_1', name: 'Banking', icon: '🏦', color: '#38b2ac');

  test('default counts: three defaults present, all-zero on an empty vault',
      () async {
    final p = _harness();
    await p.unlock(_user, _pw);
    final counts = p.categoryCounts;
    expect(counts[VaultProvider.allCategoryFilter], 0);
    expect(counts['work'], 0);
    expect(counts['personal'], 0);
    expect(counts['entertainment'], 0);
  });

  test('addCategory adds a custom category; rejects default/duplicate ids',
      () async {
    final p = _harness();
    await p.unlock(_user, _pw);

    expect(await p.addCategory(custom), isTrue);
    expect(p.categories.any((c) => c.id == 'cat_1'), isTrue);
    expect(p.categoryCounts['cat_1'], 0);

    // reserved default id
    expect(
        await p.addCategory(
            const VaultCategory(id: 'work', name: 'X')),
        isFalse);
    // duplicate custom id
    expect(await p.addCategory(custom), isFalse);
    // empty name
    expect(
        await p.addCategory(const VaultCategory(id: 'cat_2', name: '  ')),
        isFalse);
  });

  test('category filter scopes the list; counts reflect the full vault',
      () async {
    final p = _harness();
    await p.unlock(_user, _pw);
    await p.addCategory(custom);
    await p.savePassword(
        const VaultPasswordEntry(id: 1, title: 'Bank A', category: 'cat_1'));
    await p.savePassword(
        const VaultPasswordEntry(id: 2, title: 'Job', category: 'work'));

    expect(p.categoryCounts[VaultProvider.allCategoryFilter], 2);
    expect(p.categoryCounts['cat_1'], 1);
    expect(p.categoryCounts['work'], 1);

    // unfiltered shows both
    expect(p.passwords.length, 2);
    // filtered to the custom category shows only its entry
    p.setCategoryFilter('cat_1');
    expect(p.passwords.single.title, 'Bank A');
    // back to all
    p.setCategoryFilter(VaultProvider.allCategoryFilter);
    expect(p.passwords.length, 2);
  });

  test('updateCategory renames a custom category (id stable → entries intact)',
      () async {
    final p = _harness();
    await p.unlock(_user, _pw);
    await p.addCategory(custom);
    await p.savePassword(
        const VaultPasswordEntry(id: 1, title: 'Bank A', category: 'cat_1'));

    final ok = await p.updateCategory(const VaultCategory(
        id: 'cat_1', name: 'Finance', icon: '💰', color: '#9f7aea'));
    expect(ok, isTrue);
    expect(p.categories.firstWhere((c) => c.id == 'cat_1').name, 'Finance');
    // the entry still references cat_1 and still counts under it
    expect(p.categoryCounts['cat_1'], 1);

    // default categories cannot be edited
    expect(
        await p.updateCategory(
            const VaultCategory(id: 'work', name: 'Renamed')),
        isFalse);
  });

  test('deleteCategory re-homes its entries to personal and resets the filter',
      () async {
    final p = _harness();
    await p.unlock(_user, _pw);
    await p.addCategory(custom);
    await p.savePassword(
        const VaultPasswordEntry(id: 1, title: 'Bank A', category: 'cat_1'));
    await p.savePassword(
        const VaultPasswordEntry(id: 2, title: 'Bank B', category: 'cat_1'));
    p.setCategoryFilter('cat_1');

    final ok = await p.deleteCategory('cat_1');
    expect(ok, isTrue);
    // category gone
    expect(p.categories.any((c) => c.id == 'cat_1'), isFalse);
    // entries kept, re-homed to personal (NOT lost)
    expect(p.categoryCounts['personal'], 2);
    expect(p.categoryCounts[VaultProvider.allCategoryFilter], 2);
    // filter fell back to all (was pointing at the deleted category)
    expect(p.categoryFilter, VaultProvider.allCategoryFilter);
    expect(p.passwords.length, 2);
  });

  test('default categories are undeletable', () async {
    final p = _harness();
    await p.unlock(_user, _pw);
    expect(await p.deleteCategory('personal'), isFalse);
    expect(await p.deleteCategory('work'), isFalse);
    expect(p.categories.length, kDefaultVaultCategories.length);
  });
}
