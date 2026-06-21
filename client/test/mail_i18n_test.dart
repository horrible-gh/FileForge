import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';

/// i18n(mailanchor.ui.0002) — gen-l10n 으로 생성된 AppLocalizations 가
/// ko/ja/en 을 각각 올바르게 내려주고, 플레이스홀더 메시지를 보간하는지 검증.
void main() {
  test('en/ko/ja deliver distinct localized mail strings', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));

    expect(en.labelDrafts, 'Drafts');
    expect(ko.labelDrafts, '임시보관함');
    expect(ja.labelDrafts, '下書き');

    // 세 로케일이 같은 키에서 서로 다른 문자열을 내려준다(번역 누락 방지).
    expect({en.mailListEmpty, ko.mailListEmpty, ja.mailListEmpty}.length, 3);
  });

  test('placeholder messages interpolate per locale', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));

    expect(en.sendFailed('SMTP_DOWN'), 'Send failed: SMTP_DOWN');
    expect(en.attachFailed('photo.png'), 'Failed to attach photo.png');
    expect(ko.invalidAddress('a@b'), '잘못된 주소: a@b');
  });

  test('supportedLocales cover en/ko/ja', () {
    final codes =
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
    expect(codes.containsAll({'en', 'ko', 'ja'}), isTrue);
  });
}
