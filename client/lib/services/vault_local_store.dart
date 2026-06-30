import 'package:shared_preferences/shared_preferences.dart';

/// Device-local store for the SecureBolt vault's *locked* blobs (L0006 §1.2,
/// D0004 "local store" component).
///
/// The vault mirrors each pushed/pulled blob to local storage keyed by
/// [VaultCrypto.deviceVaultKey] so the vault can be opened **without the server**
/// (LOCAL_MODE — P0005 scenario 7 / L0006 §3.1). Only the opaque `Salted__…`
/// ciphertext is ever stored here — never plaintext and never the master hash —
/// so the zero-knowledge property holds on the device too.
abstract class VaultLocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Default implementation backed by [SharedPreferences]. `getInstance()` is
/// resolved lazily per call so constructing the store never touches the platform
/// channel (keeps provider/widget construction synchronous and test-safe).
class SharedPrefsVaultLocalStore implements VaultLocalStore {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _prefs).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await _prefs).setString(key, value);

  @override
  Future<void> remove(String key) async => (await _prefs).remove(key);
}

/// In-memory store for tests (and a safe fallback). Holds locked blobs only.
class InMemoryVaultLocalStore implements VaultLocalStore {
  final Map<String, String> _m = {};

  @override
  Future<String?> read(String key) async => _m[key];

  @override
  Future<void> write(String key, String value) async => _m[key] = value;

  @override
  Future<void> remove(String key) async => _m.remove(key);
}
