import 'package:dio/dio.dart';

import '../models/vault.dart';
import 'vault_crypto.dart';
import 'vault_local_store.dart';

/// One stored vault blob as returned by GET /bolt/pull (P0005 §3).
class BoltBlob {
  final String dataType; // 'password' | 'category'
  final String encryptedData; // opaque Base64 Salted__… (or '' if absent)
  final String version;

  const BoltBlob({
    required this.dataType,
    required this.encryptedData,
    this.version = '3.0',
  });
}

/// Outcome of a pull/local-load (L0006 §2.5, §3.1, §5-B).
///
/// [decryptFailed] is `true` when at least one **non-empty** blob existed but
/// could not be decrypted with the current master hash — the strong signal of a
/// wrong login password. The caller must surface this (L0006 §5-B: "사용자에
/// 복호화 실패 안내") and must NOT treat the (possibly empty) [data] as a clean
/// vault to push over, or it would clobber the real server blob with a
/// wrong-key / empty re-lock.
class VaultPullResult {
  final VaultData data;
  final bool decryptFailed;

  const VaultPullResult(this.data, {this.decryptFailed = false});
}

/// SecureBolt vault transport + crypto orchestration (L0006 §2.4–§2.7).
///
/// Talks the absorbed P0005 contract on the FileForge `/fileforge` origin
/// (`/bolt/push`, `/bolt/pull`) using the session-authenticated file Dio, and
/// applies the locking/unlocking and category merge/clean rules. The server
/// only ever sees opaque blobs (zero-knowledge) — all encryption happens here
/// via [VaultCrypto].
class VaultService {
  final Dio _dio;
  final VaultLocalStore _local;
  static const String versionString = '3.0'; // L0006 §1.3 VERSION_STRING
  static const String _catSuffix = '_categories'; // L0006 §1.2 CATEGORY_SUFFIX

  VaultService(this._dio, {VaultLocalStore? localStore})
      : _local = localStore ?? SharedPrefsVaultLocalStore();

  // ── transport ───────────────────────────────────────────────────────────────

  /// GET /bolt/pull → the caller's stored blobs (≤ 2). Identity is resolved
  /// server-side from the token; no query is sent (P0005 §3).
  Future<List<BoltBlob>> pullBlobs() async {
    final resp = await _dio.get('/bolt/pull');
    final body = resp.data;
    final list = (body is Map && body['data'] is List)
        ? body['data'] as List
        : const [];
    return [
      for (final e in list)
        if (e is Map)
          BoltBlob(
            dataType: '${e['data_type']}',
            encryptedData: '${e['encrypted_data'] ?? ''}',
            version: '${e['version'] ?? versionString}',
          ),
    ];
  }

  /// POST /bolt/push — store one opaque blob (upsert by (user, data_type)).
  Future<void> pushBlob(String dataType, String content,
      {String version = versionString}) async {
    await _dio.post('/bolt/push', data: {
      'data_type': dataType,
      'content': content,
      'version': version,
    });
  }

  // ── high-level pull/push (L0006 §2.4–§2.5) ────────────────────────────────────

  /// pull_vault (L0006 §2.5). Downloads blobs, unlocks them with [masterHash],
  /// merges categories with the local-stored set, and **mirrors the result to
  /// local storage** so the vault can later be opened offline (LOCAL_MODE).
  ///
  /// A non-empty blob that fails to decrypt is skipped (L0006 §5-B) and reported
  /// via [VaultPullResult.decryptFailed]. On any decrypt failure the local
  /// mirror is **not** rewritten, so a wrong password never clobbers the good
  /// on-device blob.
  Future<VaultPullResult> pullVault(String masterHash) async {
    final blobs = await pullBlobs();
    final localCategories = await loadLocalCategories(masterHash);

    if (blobs.isEmpty) {
      // new / empty server vault (L0006 §5-C): keep local custom categories.
      return VaultPullResult(VaultData(
        passwords: const [],
        categories: mergeCategories(localCategories, const []),
      ));
    }

    var passwords = <VaultPasswordEntry>[];
    var serverCategories = <VaultCategory>[];
    var decryptFailed = false;

    for (final b in blobs) {
      if (b.encryptedData.isEmpty) continue;
      final decoded = VaultCrypto.unlock(b.encryptedData, masterHash);
      if (decoded is! List) {
        decryptFailed = true; // wrong key / corrupt → skip but signal (§5-B)
        continue;
      }
      if (b.dataType == 'password') {
        passwords = _toPasswords(decoded);
      } else if (b.dataType == 'category') {
        serverCategories = _toCategories(decoded);
      }
      // unknown data_type → ignored (forward-compat, L0006 §4.1)
    }

    final merged = mergeCategories(localCategories, serverCategories);
    if (!decryptFailed) {
      // mirror to device only when fully decrypted (avoid wrong-key re-lock).
      await _saveLocal(masterHash, passwords, merged);
    }
    return VaultPullResult(
      VaultData(passwords: passwords, categories: merged),
      decryptFailed: decryptFailed,
    );
  }

  /// load_local_vault (L0006 §3.1, P0005 시나리오 7). Opens the vault from the
  /// device-stored locked blobs **without any server call**. Returns an empty
  /// vault if nothing is stored locally, and flags [VaultPullResult.decryptFailed]
  /// if a stored blob cannot be decrypted with [masterHash].
  Future<VaultPullResult> loadLocalVault(String masterHash) async {
    final key = VaultCrypto.deviceVaultKey(masterHash);
    final encPw = await _local.read(key);
    final encCat = await _local.read(key + _catSuffix);

    final hasPw = encPw != null && encPw.isNotEmpty;
    final hasCat = encCat != null && encCat.isNotEmpty;
    if (!hasPw && !hasCat) {
      return VaultPullResult(VaultData.empty()); // nothing cached yet
    }

    var passwords = <VaultPasswordEntry>[];
    var categories = List<VaultCategory>.from(kDefaultVaultCategories);
    var decryptFailed = false;

    if (hasPw) {
      final d = VaultCrypto.unlock(encPw, masterHash);
      if (d is List) {
        passwords = _toPasswords(d);
      } else {
        decryptFailed = true;
      }
    }
    if (hasCat) {
      final d = VaultCrypto.unlock(encCat, masterHash);
      if (d is List) {
        categories = mergeCategories(_toCategories(d), const []);
      } else {
        decryptFailed = true;
      }
    }
    return VaultPullResult(
      VaultData(passwords: passwords, categories: categories),
      decryptFailed: decryptFailed,
    );
  }

  /// push_vault (L0006 §2.4). Locks both bundles and pushes them as two
  /// independent requests; both must succeed (the caller treats a throw as
  /// PUSH_FAIL, L0006 §5-G). On success the locked blobs are **mirrored to local
  /// storage** so the same content is available offline (LOCAL_MODE).
  Future<void> pushVault(VaultData data, String masterHash) async {
    final cleaned = cleanCategories(data.categories);
    final encPw = VaultCrypto.lock(
      [for (final p in data.passwords) p.toJson()],
      masterHash,
    );
    final encCat = VaultCrypto.lock(
      [for (final c in cleaned) c.toJson()],
      masterHash,
    );
    await pushBlob('password', encPw);
    await pushBlob('category', encCat);
    // both requests succeeded → mirror the exact locked blobs to the device.
    final key = VaultCrypto.deviceVaultKey(masterHash);
    await _local.write(key, encPw);
    await _local.write(key + _catSuffix, encCat);
  }

  /// Persist the locked vault offline (LOCAL_MODE write path, L0006 §3.1). Used
  /// when changes are made while the server is unreachable — only the device
  /// mirror is updated; the next online push reconciles the server.
  Future<void> saveLocal(VaultData data, String masterHash) async {
    final cleaned = cleanCategories(data.categories);
    await _saveLocal(masterHash, data.passwords, cleaned);
  }

  // ── local store helpers (L0006 §1.2 / §2.4 / §2.5) ───────────────────────────

  /// Load and decrypt the locally-mirrored category bundle for [masterHash], or
  /// the defaults if nothing is stored / it cannot be decrypted (L0006 §2.5
  /// local_load_categories).
  Future<List<VaultCategory>> loadLocalCategories(String masterHash) async {
    final raw =
        await _local.read(VaultCrypto.deviceVaultKey(masterHash) + _catSuffix);
    if (raw == null || raw.isEmpty) {
      return List<VaultCategory>.from(kDefaultVaultCategories);
    }
    final decoded = VaultCrypto.unlock(raw, masterHash);
    if (decoded is! List) {
      return List<VaultCategory>.from(kDefaultVaultCategories);
    }
    return _toCategories(decoded);
  }

  Future<void> _saveLocal(
    String masterHash,
    List<VaultPasswordEntry> passwords,
    List<VaultCategory> categories,
  ) async {
    final key = VaultCrypto.deviceVaultKey(masterHash);
    await _local.write(
        key, VaultCrypto.lock([for (final p in passwords) p.toJson()], masterHash));
    await _local.write(key + _catSuffix,
        VaultCrypto.lock([for (final c in categories) c.toJson()], masterHash));
  }

  static List<VaultPasswordEntry> _toPasswords(List decoded) => decoded
      .whereType<Map>()
      .map((m) => VaultPasswordEntry.fromJson(m.cast<String, dynamic>()))
      .toList();

  static List<VaultCategory> _toCategories(List decoded) => decoded
      .whereType<Map>()
      .map((m) => VaultCategory.fromJson(m.cast<String, dynamic>()))
      .toList();

  // ── pure merge/clean rules (L0006 §2.6/§2.7) — static for direct testing ───────

  /// merge_categories (L0006 §2.6): defaults always win; then local custom; then
  /// server custom (server wins on custom-id collision; default ids never
  /// overwritten).
  static List<VaultCategory> mergeCategories(
    List<VaultCategory> local,
    List<VaultCategory> server,
  ) {
    final defaultIds = kDefaultVaultCategories.map((c) => c.id).toSet();
    final map = <String, VaultCategory>{};
    for (final c in kDefaultVaultCategories) {
      map[c.id] = c; // 1) defaults first, always preserved
    }
    for (final c in local) {
      if (!c.isDefault) map[c.id] = c; // 2) local custom
    }
    for (final c in server) {
      if (!defaultIds.contains(c.id)) map[c.id] = c; // 3) server custom wins
    }
    return map.values.toList();
  }

  /// clean_categories (L0006 §2.7): guarantee defaults, keep only well-formed
  /// custom categories (id and name present), normalize icon/color.
  static List<VaultCategory> cleanCategories(List<VaultCategory> categories) {
    final defaultIds = kDefaultVaultCategories.map((c) => c.id).toSet();
    final map = <String, VaultCategory>{};
    for (final c in kDefaultVaultCategories) {
      map[c.id] = c;
    }
    for (final c in categories) {
      if (!defaultIds.contains(c.id) && c.id.isNotEmpty && c.name.isNotEmpty) {
        map[c.id] = VaultCategory(
          id: c.id,
          name: c.name,
          icon: c.icon.isNotEmpty ? c.icon : '📁',
          color: c.color.isNotEmpty ? c.color : '#718096',
          isDefault: false,
        );
      }
    }
    return map.values.toList();
  }
}
