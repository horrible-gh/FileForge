import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/vault.dart';
import '../services/vault_crypto.dart';
import '../services/vault_service.dart';

/// Vault session state (L0006 §3.1). The Flutter app delegates token/session
/// lifecycle to AuthProvider, so the two states that matter here are LOCKED
/// (no master hash in memory) and UNLOCKED (master hash present). `syncing` is
/// surfaced as a transient flag rather than a distinct state.
enum VaultState { locked, unlocked }

/// SecureBolt vault state management (L0006 §3).
///
/// Holds the in-memory MASTER_HASH (never persisted), the decrypted vault, and
/// drives pull/push through [VaultService]. Locking clears the master hash and
/// the decrypted data so nothing sensitive survives a lock/logout.
class VaultProvider extends ChangeNotifier {
  final VaultService _service;

  VaultProvider(Dio dio) : _service = VaultService(dio);

  // master hash lives ONLY in memory (L0006 §2.1) — cleared on lock/reset.
  String? _masterHash;
  VaultState _state = VaultState.locked;
  VaultData _data = VaultData.empty();
  bool _isSyncing = false;
  String? _error;
  String _query = '';

  VaultState get state => _state;
  bool get isUnlocked => _state == VaultState.unlocked;
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  String get query => _query;

  List<VaultCategory> get categories => List.unmodifiable(_data.categories);

  /// Password entries filtered by the current search query (title/username/url).
  List<VaultPasswordEntry> get passwords {
    if (_query.isEmpty) return List.unmodifiable(_data.passwords);
    final q = _query.toLowerCase();
    return _data.passwords
        .where((p) =>
            p.title.toLowerCase().contains(q) ||
            p.username.toLowerCase().contains(q) ||
            p.url.toLowerCase().contains(q))
        .toList();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  /// Unlock the vault from FileForge login credentials (L0006 §2.1, §3.2).
  /// Derives the master hash in memory and pulls+decrypts the server vault.
  Future<bool> unlock(String username, String password) async {
    _masterHash = VaultCrypto.deriveMasterHash(username, password);
    _state = VaultState.unlocked;
    _error = null;
    notifyListeners();
    await refresh();
    return true;
  }

  /// Lock the vault — wipe the master hash and decrypted data (L0006 §3.2).
  void lock() {
    _masterHash = null;
    _state = VaultState.locked;
    _data = VaultData.empty();
    _query = '';
    _error = null;
    notifyListeners();
  }

  /// Logout/session-expired hook (mirrors other providers' reset()).
  void reset() => lock();

  /// pull_vault (L0006 §2.5): re-download and decrypt, merging with the local
  /// category set so custom categories survive.
  Future<void> refresh() async {
    final hash = _masterHash;
    if (hash == null) return;
    _isSyncing = true;
    _error = null;
    notifyListeners();
    try {
      _data = await _service.pullVault(hash, localCategories: _data.categories);
    } on DioException catch (e) {
      _error = _humanError(e);
    } catch (e) {
      _error = '$e';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Add or replace a password entry, then push the whole bundle (L0006 §2.4).
  Future<bool> savePassword(VaultPasswordEntry entry) async {
    final next = [..._data.passwords];
    final idx = next.indexWhere((p) => p.id == entry.id);
    if (idx >= 0) {
      next[idx] = entry;
    } else {
      next.add(entry);
    }
    return _commit(_data.copyWith(passwords: next));
  }

  Future<bool> deletePassword(int id) async {
    final next = _data.passwords.where((p) => p.id != id).toList();
    return _commit(_data.copyWith(passwords: next));
  }

  /// Add a custom category (default ids are reserved), then push.
  Future<bool> addCategory(VaultCategory category) async {
    if (kDefaultVaultCategories.any((d) => d.id == category.id)) return false;
    final next = [..._data.categories, category];
    return _commit(_data.copyWith(categories: next));
  }

  Future<bool> deleteCategory(String id) async {
    if (kDefaultVaultCategories.any((d) => d.id == id)) return false; // undeletable
    final next = _data.categories.where((c) => c.id != id).toList();
    return _commit(_data.copyWith(categories: next));
  }

  /// Apply a new local state and push it; rolls the UI error on failure.
  Future<bool> _commit(VaultData next) async {
    final hash = _masterHash;
    if (hash == null) return false;
    final previous = _data;
    _data = next;
    _isSyncing = true;
    _error = null;
    notifyListeners();
    try {
      await _service.pushVault(next, hash);
      return true;
    } on DioException catch (e) {
      _data = previous; // L0006 §5-G: push failed → don't keep local change
      _error = _humanError(e);
      return false;
    } catch (e) {
      _data = previous;
      _error = '$e';
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  String _humanError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401) return '세션이 만료되었습니다. 다시 로그인해 주세요.';
    final msg = e.response?.data is Map ? e.response?.data['message'] : null;
    return msg?.toString() ?? '볼트 동기화에 실패했습니다.';
  }
}
