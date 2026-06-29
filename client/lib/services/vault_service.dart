import 'package:dio/dio.dart';

import '../models/vault.dart';
import 'vault_crypto.dart';

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

/// SecureBolt vault transport + crypto orchestration (L0006 §2.4–§2.7).
///
/// Talks the absorbed P0005 contract on the FileForge `/fileforge` origin
/// (`/bolt/push`, `/bolt/pull`) using the session-authenticated file Dio, and
/// applies the locking/unlocking and category merge/clean rules. The server
/// only ever sees opaque blobs (zero-knowledge) — all encryption happens here
/// via [VaultCrypto].
class VaultService {
  final Dio _dio;
  static const String versionString = '3.0'; // L0006 §1.3 VERSION_STRING

  VaultService(this._dio);

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
  /// and returns the merged vault. A blob that fails to decrypt is skipped
  /// (L0006 §5-B). [localCategories] (if any) participate in the merge.
  Future<VaultData> pullVault(
    String masterHash, {
    List<VaultCategory>? localCategories,
  }) async {
    final blobs = await pullBlobs();
    if (blobs.isEmpty) {
      return VaultData.empty(); // new / empty vault (L0006 §5-C)
    }

    var passwords = <VaultPasswordEntry>[];
    var serverCategories = <VaultCategory>[];

    for (final b in blobs) {
      if (b.encryptedData.isEmpty) continue;
      final decoded = VaultCrypto.unlock(b.encryptedData, masterHash);
      if (decoded is! List) continue; // wrong key / corrupt → skip
      if (b.dataType == 'password') {
        passwords = decoded
            .whereType<Map>()
            .map((m) => VaultPasswordEntry.fromJson(m.cast<String, dynamic>()))
            .toList();
      } else if (b.dataType == 'category') {
        serverCategories = decoded
            .whereType<Map>()
            .map((m) => VaultCategory.fromJson(m.cast<String, dynamic>()))
            .toList();
      }
      // unknown data_type → ignored (forward-compat, L0006 §4.1)
    }

    final merged = mergeCategories(
      localCategories ?? List<VaultCategory>.from(kDefaultVaultCategories),
      serverCategories,
    );
    return VaultData(passwords: passwords, categories: merged);
  }

  /// push_vault (L0006 §2.4). Locks both bundles and pushes them as two
  /// independent requests; both must succeed (the caller treats a throw as
  /// PUSH_FAIL, L0006 §5-G).
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
  }

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
