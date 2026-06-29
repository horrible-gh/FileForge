import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/services/vault_crypto.dart';

/// CryptoJS 4.1.1 byte-compatibility vectors (L0006 §6.4).
///
/// These were generated from the REAL crypto-js@4.1.1 library (not from this
/// Dart implementation), so they are an independent ground truth. If the Dart
/// EVP_BytesToKey / AES-CBC / Salted__ container ever drifts from CryptoJS,
/// these assertions go RED — proving the absorption's #1 risk (existing vault
/// blobs must decrypt unchanged) stays closed.
const _username = 'fileforge';
const _password = 'P@ssw0rd!';
const _masterHash =
    'dc52268b24cd260ca6bd96da088d5e52cdc8ffc1b212b1e67bbe6150f59c0f03';
// fixed salt 00 01 02 03 04 05 06 07
final _fixedSalt = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);

// CryptoJS.AES.encrypt(JSON.stringify([]), masterHash) with the fixed salt.
const _detEmptyArray = 'U2FsdGVkX18AAQIDBAUGB/mrPnW9G0Jg74FnQXj6omA=';
// CryptoJS.AES.encrypt(JSON.stringify(<pw bundle>), masterHash) with fixed salt.
const _detPwBundle =
    'U2FsdGVkX18AAQIDBAUGB3CvfHT352UFO/7yz8CsCw3IpBH4m7R+MxLJLtyL5pSNaWZLnD7VQHyTRxg7irdspVRtFKZLTxCNHzACC8dPwpLKVqLhw3xC0xC9JoVXwt/qgfEnM4IWcGqIHOq60co90RcM2lTdSpwYp7EPwfo/Qowp4yBmbFv8YuLNM84q8XhJ8biq9YlXY6CuX3+0uaS08Nekh+ABYl+xeJAn8Rfn7O0=';
const _pwBundleJson =
    '[{"id":1719630000000,"title":"Google","username":"me@gmail.com","password":"g00gle!pw","url":"https://google.com","category":"work","notes":""}]';
// CryptoJS.AES.encrypt(JSON.stringify([]), masterHash) with a RANDOM salt.
const _randEmptyArray = 'U2FsdGVkX190beHTTk7B5yMo4IH5GFsI1jhMDeyN3lw=';

void main() {
  group('master hash (L0006 §2.1)', () {
    test('SHA-256(username+password) lowercase hex matches CryptoJS', () {
      expect(VaultCrypto.deriveMasterHash(_username, _password), _masterHash);
    });
  });

  group('lock — byte-for-byte CryptoJS compatibility (L0006 §6.4)', () {
    test('empty array with fixed salt == CryptoJS output', () {
      final out = VaultCrypto.lock(<dynamic>[], _masterHash, salt: _fixedSalt);
      expect(out, _detEmptyArray);
    });

    test('password bundle with fixed salt == CryptoJS output', () {
      final bundle = jsonDecode(_pwBundleJson);
      final out = VaultCrypto.lock(bundle, _masterHash, salt: _fixedSalt);
      expect(out, _detPwBundle);
    });

    test('output container is base64("Salted__" || salt || ciphertext)', () {
      final out = VaultCrypto.lock(<dynamic>[], _masterHash, salt: _fixedSalt);
      final raw = base64.decode(out);
      expect(utf8.decode(raw.sublist(0, 8)), 'Salted__');
      expect(raw.sublist(8, 16), _fixedSalt);
    });
  });

  group('unlock — decrypts genuine CryptoJS blobs', () {
    test('deterministic (fixed-salt) CryptoJS blob → []', () {
      expect(VaultCrypto.unlock(_detEmptyArray, _masterHash), <dynamic>[]);
    });

    test('deterministic CryptoJS pw bundle blob → original array', () {
      final got = VaultCrypto.unlock(_detPwBundle, _masterHash);
      expect(got, jsonDecode(_pwBundleJson));
      expect(got[0]['title'], 'Google');
    });

    test('random-salt CryptoJS blob → [] (salt read from container)', () {
      expect(VaultCrypto.unlock(_randEmptyArray, _masterHash), <dynamic>[]);
    });
  });

  group('round-trip (Dart lock → Dart unlock, random salt)', () {
    test('empty array', () {
      final blob = VaultCrypto.lock(<dynamic>[], _masterHash);
      expect(VaultCrypto.unlock(blob, _masterHash), <dynamic>[]);
    });

    test('rich object array survives round-trip', () {
      final data = [
        {'id': 1, 'title': 'A', 'notes': 'unicode ✓ 한글 🏦'},
        {'id': 2, 'title': 'B'},
      ];
      final blob = VaultCrypto.lock(data, _masterHash);
      expect(VaultCrypto.unlock(blob, _masterHash), data);
    });

    test('two locks of same data differ (random salt) but both decrypt', () {
      final a = VaultCrypto.lock(<dynamic>[], _masterHash);
      final b = VaultCrypto.lock(<dynamic>[], _masterHash);
      expect(a, isNot(b)); // salt randomized
      expect(VaultCrypto.unlock(a, _masterHash), <dynamic>[]);
      expect(VaultCrypto.unlock(b, _masterHash), <dynamic>[]);
    });
  });

  group('unlock failure modes (L0006 §2.3 / §5-B)', () {
    test('wrong master hash → null', () {
      final blob = VaultCrypto.lock(<dynamic>[], _masterHash);
      final wrong = VaultCrypto.deriveMasterHash('fileforge', 'WRONG');
      expect(VaultCrypto.unlock(blob, wrong), isNull);
    });

    test('missing Salted__ magic → null', () {
      final notSalted = base64.encode(utf8.encode('hello world not salted'));
      expect(VaultCrypto.unlock(notSalted, _masterHash), isNull);
    });

    test('garbage / non-base64 → null', () {
      expect(VaultCrypto.unlock('!!!not base64!!!', _masterHash), isNull);
      expect(VaultCrypto.unlock('', _masterHash), isNull);
    });
  });
}
