import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';

/// i18n (fileforge.default.0003) — guards the i18n pass that lifted the
/// hardcoded Korean (SecureBolt vault) and hardcoded English (file management,
/// login, settings, share, preview) strings into the gen-l10n pipeline.
///
/// Two guarantees:
///   1. ARB key parity — ko/ja translate EVERY key the en template defines, so
///      no locale silently falls back to English/Korean.
///   2. The newly extracted keys are actually translated (distinct per locale)
///      and placeholder messages interpolate.
void main() {
  Map<String, dynamic> readArb(String locale) {
    final f = File('lib/l10n/app_$locale.arb');
    return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  }

  // Message keys only: drop gen-l10n metadata (`@@locale`, `@key` descriptions).
  Set<String> messageKeys(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  test('ARB key parity: ko and ja translate every en key', () {
    final en = messageKeys(readArb('en'));
    final ko = messageKeys(readArb('ko'));
    final ja = messageKeys(readArb('ja'));

    expect(en.difference(ko), isEmpty,
        reason: 'keys present in en but missing from ko');
    expect(en.difference(ja), isEmpty,
        reason: 'keys present in en but missing from ja');
    // No stray keys in the translations that the template doesn't define.
    expect(ko.difference(en), isEmpty, reason: 'ko has keys en lacks');
    expect(ja.difference(en), isEmpty, reason: 'ja has keys en lacks');
  });

  test('no message value is empty in any locale', () {
    for (final locale in ['en', 'ko', 'ja']) {
      final arb = readArb(locale);
      for (final k in messageKeys(arb)) {
        expect((arb[k] as String).trim(), isNotEmpty,
            reason: '$locale.$k is empty');
      }
    }
  });

  test('vault (previously Korean-hardcoded) strings are now per-locale', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));

    expect(en.vaultUnlockTitle, 'Unlock vault');
    expect(ko.vaultUnlockTitle, '볼트 잠금 해제');
    expect(ja.vaultUnlockTitle, 'ボルトのロックを解除');

    // Three genuinely different translations (no fallthrough to one language).
    expect({en.vaultEmpty, ko.vaultEmpty, ja.vaultEmpty}.length, 3);
    expect({en.vaultMsgDecryptBanner, ko.vaultMsgDecryptBanner,
            ja.vaultMsgDecryptBanner}.length, 3);
  });

  test('file-management (previously English-hardcoded) strings are localized',
      () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));

    expect(en.filesEmpty, 'No files');
    expect({en.filesEmpty, ko.filesEmpty, ja.filesEmpty}.length, 3);
    expect({en.navLogout, ko.navLogout, ja.navLogout}.length, 3);
    expect({en.securityEnable2fa, ko.securityEnable2fa, ja.securityEnable2fa}
        .length, 3);
  });

  test('placeholder messages interpolate per locale', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));

    expect(en.deleteConfirmName('report.pdf'), "Delete 'report.pdf'?");
    expect(en.bulkDeleteConfirmCount(3), 'Delete 3 items?');
    expect(en.vaultDeleteConfirm('GitHub'), "Delete entry 'GitHub'?");
    expect(en.shareCreateLinkFailed('500'), 'Failed to create link: 500');
    // ko still interpolates the argument.
    expect(ko.shareDeleteLinkBody('photo').contains('photo'), isTrue);
  });
}
