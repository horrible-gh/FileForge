import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/vault.dart';
import '../services/vault_crypto.dart';
import '../services/vault_local_store.dart';
import '../services/vault_service.dart';

/// Vault session state (L0006 §3.1). The Flutter app delegates token/session
/// lifecycle to AuthProvider; the [VaultState.localMode] entry is surfaced when
/// the vault is opened from device-stored blobs without the server. `syncing` is
/// a transient flag rather than a distinct state.
enum VaultState { locked, unlocked, localMode }

/// Stable, locale-independent code for the status/error message the vault wants
/// to surface. The UI layer maps each code to a localized string (i18n,
/// fileforge.default.0003); [VaultProvider.error] still carries the raw text for
/// backward compatibility and for unexpected exceptions ([VaultMessage.none]).
enum VaultMessage {
  none,
  decryptBanner,
  decryptBlockedSave,
  offlineMode,
  offlineSaved,
  sessionExpired,
  syncFailed,
}

/// SecureBolt vault state management (L0006 §3).
///
/// Holds the in-memory MASTER_HASH (never persisted), the decrypted vault, and
/// drives pull/push through [VaultService]. Locking clears the master hash and
/// the decrypted data so nothing sensitive survives a lock/logout.
class VaultProvider extends ChangeNotifier {
  final VaultService _service;

  /// Sentinel for "show all categories" in [categoryFilter] / [categoryCounts].
  static const String allCategoryFilter = 'all';

  /// Where entries of a deleted category are re-homed (legacy parity: the
  /// 'personal' default is always present and never deletable).
  static const String _orphanFallbackCategory = 'personal';

  VaultProvider(Dio dio, {VaultLocalStore? localStore})
      : _service = VaultService(dio, localStore: localStore);

  /// Test seam: inject a pre-built service (with a fake Dio + in-memory store).
  @visibleForTesting
  VaultProvider.withService(this._service);

  // Internal (non-displayed) status sentinels. These drive the anti-clobber
  // guard on a wrong-key pull (L0006 §5-B) and back the `error != null` banner
  // visibility gate; the user-facing text is rendered from [messageCode] via
  // localizedVaultMessage() (t.vaultMsg*), so these values are never shown and
  // are kept in English as locale-independent sentinels / test guards.
  static const String decryptBannerMessage =
      'vault decrypt failed — verify your login password and unlock again '
      '(protected: changes are not saved to the server in this state)';
  static const String decryptBlockedSaveMessage =
      'cannot save while decryption is failing — blocked to avoid overwriting '
      'the existing vault; verify your password and unlock again';
  static const String offlineModeMessage =
      'offline mode: showing the device-stored vault; will sync when online';
  static const String offlineSavedMessage =
      'offline: changes saved to this device only; will sync with the server '
      'when online';
  static const String sessionExpiredMessage =
      'session expired — please sign in again';
  static const String syncFailedMessage = 'vault sync failed';

  // master hash lives ONLY in memory (L0006 §2.1) — cleared on lock/reset.
  String? _masterHash;
  VaultState _state = VaultState.locked;
  VaultData _data = VaultData.empty();
  bool _isSyncing = false;
  bool _localMode = false;
  bool _decryptError = false;
  String? _error;
  VaultMessage _messageCode = VaultMessage.none;
  String _query = '';
  // Category-based viewing (R0001): 'all' shows every entry, otherwise the
  // selected category id scopes the list. Reset on lock.
  String _categoryFilter = allCategoryFilter;

  VaultState get state => _state;
  bool get isUnlocked => _state != VaultState.locked;
  bool get isLocalMode => _localMode;

  /// True after a pull/load where a non-empty blob could not be decrypted — a
  /// wrong-password signal. While set, saves are blocked (anti-clobber, §5-B).
  bool get hasDecryptError => _decryptError;
  bool get isSyncing => _isSyncing;
  String? get error => _error;

  /// Locale-independent code for the current status/error message; the UI maps
  /// it to a localized string. [VaultMessage.none] means "use [error] verbatim".
  VaultMessage get messageCode => _messageCode;
  String get query => _query;

  List<VaultCategory> get categories => List.unmodifiable(_data.categories);

  /// The active category filter id, or [allCategoryFilter] for "show all".
  String get categoryFilter => _categoryFilter;

  /// Entry counts per category over the FULL (unfiltered) vault, plus an
  /// [allCategoryFilter] total — drives the category chip-bar count badges
  /// (R0001: "view entries by category"). Every known category id is present (0 when
  /// empty); entries whose category id no longer exists are not counted under
  /// any chip (delete re-homes them, so this is the orphan-free common case).
  Map<String, int> get categoryCounts {
    final counts = <String, int>{allCategoryFilter: _data.passwords.length};
    for (final c in _data.categories) {
      counts[c.id] = 0;
    }
    for (final p in _data.passwords) {
      if (counts.containsKey(p.category)) {
        counts[p.category] = counts[p.category]! + 1;
      }
    }
    return counts;
  }

  /// Password entries scoped by the active category filter, then narrowed by
  /// the current search query (title/username/url).
  List<VaultPasswordEntry> get passwords {
    Iterable<VaultPasswordEntry> list = _data.passwords;
    if (_categoryFilter != allCategoryFilter) {
      list = list.where((p) => p.category == _categoryFilter);
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((p) =>
          p.title.toLowerCase().contains(q) ||
          p.username.toLowerCase().contains(q) ||
          p.url.toLowerCase().contains(q));
    }
    return List.unmodifiable(list.toList());
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  /// Scope the list to a single category id, or [allCategoryFilter] for all.
  void setCategoryFilter(String id) {
    _categoryFilter = id;
    notifyListeners();
  }

  /// Unlock the vault from FileForge login credentials (L0006 §2.1, §3.2).
  /// Derives the master hash in memory and pulls+decrypts the server vault.
  /// Returns `false` if the pull surfaced a decrypt failure (wrong password).
  Future<bool> unlock(String username, String password) async {
    _masterHash = VaultCrypto.deriveMasterHash(username, password);
    _state = VaultState.unlocked;
    _localMode = false;
    _decryptError = false;
    _error = null;
    _messageCode = VaultMessage.none;
    notifyListeners();
    await refresh();
    return !_decryptError;
  }

  /// Open the vault from device-stored blobs only — LOCAL_MODE, no server call
  /// (P0005 scenario 7 / L0006 §3.1). Returns `false` on decrypt failure.
  Future<bool> unlockLocal(String username, String password) async {
    _masterHash = VaultCrypto.deriveMasterHash(username, password);
    _state = VaultState.localMode;
    _localMode = true;
    _decryptError = false;
    _error = null;
    _messageCode = VaultMessage.none;
    notifyListeners();
    await _loadLocal(_masterHash!);
    return !_decryptError;
  }

  /// Lock the vault — wipe the master hash and decrypted data (L0006 §3.2).
  void lock() {
    _masterHash = null;
    _state = VaultState.locked;
    _data = VaultData.empty();
    _query = '';
    _categoryFilter = allCategoryFilter;
    _localMode = false;
    _decryptError = false;
    _error = null;
    _messageCode = VaultMessage.none;
    notifyListeners();
  }

  /// Logout/session-expired hook (mirrors other providers' reset()).
  void reset() => lock();

  /// pull_vault (L0006 §2.5): re-download and decrypt. On a wrong-key blob the
  /// vault is flagged (anti-clobber, §5-B); if the server is unreachable it
  /// falls back to the device-stored vault (LOCAL_MODE, P0005 scenario 7).
  Future<void> refresh() async {
    final hash = _masterHash;
    if (hash == null) return;
    _isSyncing = true;
    _error = null;
    _messageCode = VaultMessage.none;
    notifyListeners();
    try {
      final res = await _service.pullVault(hash);
      _data = res.data;
      _decryptError = res.decryptFailed;
      _localMode = false;
      _state = VaultState.unlocked;
      _error = _decryptError ? decryptBannerMessage : null;
      _messageCode =
          _decryptError ? VaultMessage.decryptBanner : VaultMessage.none;
    } on DioException catch (e) {
      if (_isConnectionError(e)) {
        await _loadLocal(hash, offline: true); // server down → LOCAL_MODE
      } else {
        _error = _humanError(e);
      }
    } catch (e) {
      _error = '$e';
      _messageCode = VaultMessage.none;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Load the device-stored vault (LOCAL_MODE read path, L0006 §3.1).
  Future<void> _loadLocal(String hash, {bool offline = false}) async {
    _isSyncing = true;
    notifyListeners();
    try {
      final res = await _service.loadLocalVault(hash);
      _data = res.data;
      _decryptError = res.decryptFailed;
      _localMode = true;
      _state = VaultState.localMode;
      _error = _decryptError
          ? decryptBannerMessage
          : (offline ? offlineModeMessage : null);
      _messageCode = _decryptError
          ? VaultMessage.decryptBanner
          : (offline ? VaultMessage.offlineMode : VaultMessage.none);
    } catch (e) {
      _error = '$e';
      _messageCode = VaultMessage.none;
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

  /// Add a custom category (default ids are reserved, no duplicate id), push.
  Future<bool> addCategory(VaultCategory category) async {
    if (category.id.isEmpty || category.name.trim().isEmpty) return false;
    if (kDefaultVaultCategories.any((d) => d.id == category.id)) return false;
    if (_data.categories.any((c) => c.id == category.id)) return false;
    final next = [..._data.categories, category];
    return _commit(_data.copyWith(categories: next));
  }

  /// Rename / recolor an existing custom category (id is immutable, so entries
  /// keep referencing it). Default categories cannot be edited (R0001 parity).
  Future<bool> updateCategory(VaultCategory updated) async {
    if (kDefaultVaultCategories.any((d) => d.id == updated.id)) return false;
    if (updated.name.trim().isEmpty) return false;
    final next = [..._data.categories];
    final idx = next.indexWhere((c) => c.id == updated.id);
    if (idx < 0) return false;
    next[idx] = updated;
    return _commit(_data.copyWith(categories: next));
  }

  /// Delete a custom category and re-home its entries to the 'personal' default
  /// (legacy SecureBolt parity — entries are kept, not lost). Default categories
  /// are undeletable. Clears the filter if it pointed at the deleted category.
  Future<bool> deleteCategory(String id) async {
    if (kDefaultVaultCategories.any((d) => d.id == id)) return false; // undeletable
    if (!_data.categories.any((c) => c.id == id)) return false;
    final nextCategories = _data.categories.where((c) => c.id != id).toList();
    final nextPasswords = _data.passwords
        .map((p) =>
            p.category == id ? p.copyWith(category: _orphanFallbackCategory) : p)
        .toList();
    if (_categoryFilter == id) _categoryFilter = allCategoryFilter;
    return _commit(
        _data.copyWith(categories: nextCategories, passwords: nextPasswords));
  }

  /// Apply a new local state and push it; rolls the UI error on failure.
  Future<bool> _commit(VaultData next) async {
    final hash = _masterHash;
    if (hash == null) return false;
    // Anti-clobber (L0006 §5-B): never push over an existing vault we could not
    // decrypt — that would replace the real server blob with a wrong-key/empty
    // re-lock. Require a successful re-unlock first.
    if (_decryptError) {
      _error = decryptBlockedSaveMessage;
      _messageCode = VaultMessage.decryptBlockedSave;
      notifyListeners();
      return false;
    }
    final previous = _data;
    _data = next;
    _isSyncing = true;
    _error = null;
    _messageCode = VaultMessage.none;
    notifyListeners();
    try {
      // Always attempt the server push; a success also reconciles a prior
      // LOCAL_MODE session back online (P0005 scenario 7: push later when back online).
      await _service.pushVault(next, hash);
      _localMode = false;
      _state = VaultState.unlocked;
      return true;
    } on DioException catch (e) {
      if (_isConnectionError(e)) {
        // server unreachable → keep the change on-device, enter LOCAL_MODE
        // (P0005 scenario 7: keep the change on-device, push later when back online).
        await _service.saveLocal(next, hash);
        _localMode = true;
        _state = VaultState.localMode;
        _error = offlineSavedMessage;
        _messageCode = VaultMessage.offlineSaved;
        return true;
      }
      _data = previous; // L0006 §5-G: push failed → don't keep local change
      _error = _humanError(e);
      return false;
    } catch (e) {
      _data = previous;
      _error = '$e';
      _messageCode = VaultMessage.none;
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// A transport-level failure (no HTTP response) means the server is
  /// unreachable → fall back to LOCAL_MODE rather than erroring out. A real HTTP
  /// status (e.g. 401/400/500) is NOT a connection error.
  static bool _isConnectionError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      default:
        return e.response == null;
    }
  }

  String _humanError(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401) {
      _messageCode = VaultMessage.sessionExpired;
      return sessionExpiredMessage;
    }
    final msg = e.response?.data is Map ? e.response?.data['message'] : null;
    if (msg != null) {
      // Server supplied a specific message — surface it verbatim (no l10n code).
      _messageCode = VaultMessage.none;
      return msg.toString();
    }
    _messageCode = VaultMessage.syncFailed;
    return syncFailedMessage;
  }
}
