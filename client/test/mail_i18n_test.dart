import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';

/// i18n(mailanchor.ui.0002) — gen-l10n text createtext AppLocalizations text
/// ko/ja/en text text translated text translated text, translated text translated text translated text verify.
void main() {
  test('en/ko/ja deliver distinct localized mail strings', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));

    expect(en.labelDrafts, 'Drafts');
    expect(ko.labelDrafts, '\uC784\uC2DC\uBCF4\uAD00\uD568');
    expect(ja.labelDrafts, '下書き');

    // text translated text text translated text text text stringtext translated text(text text text).
    expect({en.mailListEmpty, ko.mailListEmpty, ja.mailListEmpty}.length, 3);
  });

  test('placeholder messages interpolate per locale', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));

    expect(en.sendFailed('SMTP_DOWN'), 'Send failed: SMTP_DOWN');
    expect(en.attachFailed('photo.png'), 'Failed to attach photo.png');
    expect(ko.invalidAddress('a@b'), '\uC798\uBABB\uB41C \uC8FC\uC18C: a@b');
  });

  test('supportedLocales cover en/ko/ja', () {
    final codes =
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
    expect(codes.containsAll({'en', 'ko', 'ja'}), isTrue);
  });
}
