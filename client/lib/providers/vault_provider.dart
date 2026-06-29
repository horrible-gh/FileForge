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

/// SecureBolt vault state management (L0006 §3).
///
/// Holds the in-memory MASTER_HASH (never persisted), the decrypted vault, and
/// drives pull/push through [VaultService]. Locking clears the master hash and
/// the decrypted data so nothing sensitive survives a lock/logout.
class VaultProvider extends ChangeNotifier {
  final VaultService _service;

  VaultProvider(Dio dio, {VaultLocalStore? localStore})
      : _service = VaultService(dio, localStore: localStore);

  /// Test seam: inject a pre-built service (with a fake Dio + in-memory store).
  @visibleForTesting
  VaultProvider.withService(this._service);

  // On a wrong-key pull the existing server vault must not be mistaken for an
  // empty one and overwritten; these messages drive that guard (L0006 §5-B).
  static const String decryptBannerMessage =
      '볼트 복호화에 실패했습니다. 로그인 비밀번호가 올바른지 확인한 뒤 다시 잠금 해제하세요. '
      '(보호: 이 상태에서는 변경 사항을 서버에 저장하지 않습니다)';
  static const String decryptBlockedSaveMessage =
      '복호화 실패 상태에서는 저장할 수 없습니다. 기존 볼트를 덮어쓰지 않도록 막았습니다 — '
      '비밀번호를 확인해 다시 잠금 해제하세요.';
  static const String offlineModeMessage =
      '오프라인 모드: 기기에 저장된 볼트를 표시합니다. 온라인이 되면 동기화됩니다.';
  static const String offlineSavedMessage =
      '오프라인: 변경 사항을 기기에만 저장했습니다. 온라인이 되면 서버와 동기화됩니다.';

  // master hash lives ONLY in memory (L0006 §2.1) — cleared on lock/reset.
  String? _masterHash;
  VaultState _state = VaultState.locked;
  VaultData _data = VaultData.empty();
  bool _isSyncing = false;
  bool _localMode = false;
  bool _decryptError = false;
  String? _error;
  String _query = '';

  VaultState get state => _state;
  bool get isUnlocked => _state != VaultState.locked;
  bool get isLocalMode => _localMode;

  /// True after a pull/load where a non-empty blob could not be decrypted — a
  /// wrong-password signal. While set, saves are blocked (anti-clobber, §5-B).
  bool get hasDecryptError => _decryptError;
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
  /// Returns `false` if the pull surfaced a decrypt failure (wrong password).
  Future<bool> unlock(String username, String password) async {
    _masterHash = VaultCrypto.deriveMasterHash(username, password);
    _state = VaultState.unlocked;
    _localMode = false;
    _decryptError = false;
    _error = null;
    notifyListeners();
    await refresh();
    return !_decryptError;
  }

  /// Open the vault from device-stored blobs only — LOCAL_MODE, no server call
  /// (P0005 시나리오 7 / L0006 §3.1). Returns `false` on decrypt failure.
  Future<bool> unlockLocal(String username, String password) async {
    _masterHash = VaultCrypto.deriveMasterHash(username, password);
    _state = VaultState.localMode;
    _localMode = true;
    _decryptError = false;
    _error = null;
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
    _localMode = false;
    _decryptError = false;
    _error = null;
    notifyListeners();
  }

  /// Logout/session-expired hook (mirrors other providers' reset()).
  void reset() => lock();

  /// pull_vault (L0006 §2.5): re-download and decrypt. On a wrong-key blob the
  /// vault is flagged (anti-clobber, §5-B); if the server is unreachable it
  /// falls back to the device-stored vault (LOCAL_MODE, P0005 시나리오 7).
  Future<void> refresh() async {
    final hash = _masterHash;
    if (hash == null) return;
    _isSyncing = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _service.pullVault(hash);
      _data = res.data;
      _decryptError = res.decryptFailed;
      _localMode = false;
      _state = VaultState.unlocked;
      _error = _decryptError ? decryptBannerMessage : null;
    } on DioException catch (e) {
      if (_isConnectionError(e)) {
        await _loadLocal(hash, offline: true); // server down → LOCAL_MODE
      } else {
        _error = _humanError(e);
      }
    } catch (e) {
      _error = '$e';
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
    // Anti-clobber (L0006 §5-B): never push over an existing vault we could not
    // decrypt — that would replace the real server blob with a wrong-key/empty
    // re-lock. Require a successful re-unlock first.
    if (_decryptError) {
      _error = decryptBlockedSaveMessage;
      notifyListeners();
      return false;
    }
    final previous = _data;
    _data = next;
    _isSyncing = true;
    _error = null;
    notifyListeners();
    try {
      // Always attempt the server push; a success also reconciles a prior
      // LOCAL_MODE session back online (P0005 시나리오 7: 이후 온라인 시 push).
      await _service.pushVault(next, hash);
      _localMode = false;
      _state = VaultState.unlocked;
      return true;
    } on DioException catch (e) {
      if (_isConnectionError(e)) {
        // server unreachable → keep the change on-device, enter LOCAL_MODE
        // (P0005 시나리오 7: 변경분은 로컬에 보관, 이후 온라인 시 push).
        await _service.saveLocal(next, hash);
        _localMode = true;
        _state = VaultState.localMode;
        _error = offlineSavedMessage;
        return true;
      }
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
    if (code == 401) return '세션이 만료되었습니다. 다시 로그인해 주세요.';
    final msg = e.response?.data is Map ? e.response?.data['message'] : null;
    return msg?.toString() ?? '볼트 동기화에 실패했습니다.';
  }
}
