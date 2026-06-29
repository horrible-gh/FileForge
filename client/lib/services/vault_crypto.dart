import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// CryptoJS 4.1.1-compatible vault cryptography for the absorbed SecureBolt
/// module (fileforge.securebolt.0001 / L0006 §1, §6).
///
/// The legacy SecureBolt web client locks each vault bundle with
/// `CryptoJS.AES.encrypt(JSON.stringify(data), masterPasswordHash)` where
/// `masterPasswordHash = CryptoJS.SHA256(username + password)` (hex). CryptoJS's
/// passphrase mode is exactly OpenSSL's salted format: the output is
/// `base64("Salted__" || salt(8) || AES-256-CBC/PKCS7(ciphertext))` and the
/// key/iv are derived by `EVP_BytesToKey(passphrase, salt, MD5, iter=1)`.
///
/// This class reproduces that byte-for-byte so vault blobs written by the old
/// web client decrypt unchanged in Flutter (the absorption's #1 compatibility
/// risk — NR0003 §3-D). **None of these constants may change**: doing so breaks
/// decryption of every existing blob. See the test vectors in
/// test/vault_crypto_test.dart (generated from real crypto-js).
class VaultCrypto {
  VaultCrypto._();

  // --- fixed parameters (L0006 §1.1) — do NOT change ---
  static const int _saltLen = 8; // OpenSSL Salted__ salt
  static const int _keyLen = 32; // AES-256
  static const int _ivLen = 16; // CBC IV
  static final Uint8List _magic =
      Uint8List.fromList(utf8.encode('Salted__')); // 53 61 6C 74 65 64 5F 5F

  /// MASTER_HASH = lowercase hex of SHA-256(username + password) (L0006 §2.1).
  /// The returned 64-char hex string is itself fed to AES as the passphrase
  /// (NOT hex-decoded) — matching CryptoJS, which receives the string verbatim.
  static String deriveMasterHash(String username, String password) {
    return crypto.sha256.convert(utf8.encode(username + password)).toString();
  }

  /// EVP_BytesToKey (OpenSSL, MD5, iter=1) — L0006 §6.1.
  /// D1=MD5(pass‖salt), Dn=MD5(Dn-1‖pass‖salt); key=D1‖D2, iv=D3.
  static (Uint8List key, Uint8List iv) _evpBytesToKey(
      Uint8List passphrase, Uint8List salt) {
    final material = BytesBuilder();
    Uint8List dPrev = Uint8List(0);
    while (material.length < _keyLen + _ivLen) {
      final input = Uint8List.fromList([...dPrev, ...passphrase, ...salt]);
      dPrev = Uint8List.fromList(crypto.md5.convert(input).bytes);
      material.add(dPrev);
    }
    final mat = material.toBytes();
    return (
      Uint8List.sublistView(mat, 0, _keyLen),
      Uint8List.sublistView(mat, _keyLen, _keyLen + _ivLen),
    );
  }

  static Uint8List _aesCbc(
      bool forEncryption, Uint8List data, Uint8List key, Uint8List iv) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      forEncryption,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );
    return cipher.process(data);
  }

  static Uint8List _randomSalt() {
    final rnd = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(_saltLen, (_) => rnd.nextInt(256)));
  }

  /// lock / encrypt (L0006 §2.2). Serializes [plainValue] to JSON (UTF-8),
  /// encrypts with the passphrase [masterHash], and returns the opaque Base64
  /// `Salted__…` string the server stores as `content`.
  ///
  /// [salt] is injectable only for deterministic tests; production uses a fresh
  /// CSPRNG salt (matching CryptoJS, which always randomizes the salt).
  static String lock(Object? plainValue, String masterHash, {Uint8List? salt}) {
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(plainValue)));
    final s = salt ?? _randomSalt();
    final pass = Uint8List.fromList(utf8.encode(masterHash));
    final (key, iv) = _evpBytesToKey(pass, s);
    final ct = _aesCbc(true, plaintext, key, iv);
    final blob = Uint8List.fromList([..._magic, ...s, ...ct]);
    return base64.encode(blob);
  }

  /// unlock / decrypt (L0006 §2.3). Returns the decoded JSON value, or `null`
  /// on any failure (bad format, wrong key → padding/UTF-8/JSON error, empty
  /// result) — preserving CryptoJS's "wrong key ⇒ empty string ⇒ null"
  /// semantics (crypto.js:33-36). Callers treat `null` as DECRYPT_FAIL
  /// (L0006 §5-B) and skip the item.
  static dynamic unlock(String opaqueString, String masterHash) {
    try {
      final raw = base64.decode(opaqueString);
      if (raw.length < 16) return null;
      if (!_constEq(Uint8List.sublistView(raw, 0, 8), _magic)) return null;
      final salt = Uint8List.sublistView(raw, 8, 16);
      final ct = Uint8List.sublistView(raw, 16);
      if (ct.isEmpty || ct.length % 16 != 0) return null;
      final pass = Uint8List.fromList(utf8.encode(masterHash));
      final (key, iv) = _evpBytesToKey(pass, salt);
      final plain = _aesCbc(false, Uint8List.fromList(ct), key, iv);
      final text = utf8.decode(plain); // PKCS7 already stripped by the cipher
      if (text.isEmpty) return null;
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static bool _constEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
