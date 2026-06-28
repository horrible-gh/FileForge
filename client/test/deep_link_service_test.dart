import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/services/deep_link_service.dart';

/// R0001/NR0003/T0004 §Option C — OAuth 성공 딥링크(fileforge://oauth/gmail/success)
/// 식별 로직 회귀 방지. 서버 _oauth_result_page 가 자동 리다이렉트하는 스킴과
/// 일치해야 앱이 foreground 복귀 시 계정 목록을 재로딩한다.
void main() {
  group('DeepLinkService.isOAuthSuccessUri', () {
    test('matches the canonical gmail success deeplink', () {
      expect(
        DeepLinkService.isOAuthSuccessUri(
            Uri.parse('fileforge://oauth/gmail/success')),
        isTrue,
      );
    });

    test('matches with trailing query params (email)', () {
      expect(
        DeepLinkService.isOAuthSuccessUri(
            Uri.parse('fileforge://oauth/gmail/success?email=a@b.com')),
        isTrue,
      );
    });

    test('rejects a different scheme', () {
      expect(
        DeepLinkService.isOAuthSuccessUri(
            Uri.parse('https://oauth/gmail/success')),
        isFalse,
      );
    });

    test('rejects a different provider/path', () {
      expect(
        DeepLinkService.isOAuthSuccessUri(
            Uri.parse('fileforge://oauth/outlook/success')),
        isFalse,
      );
      expect(
        DeepLinkService.isOAuthSuccessUri(
            Uri.parse('fileforge://oauth/gmail/failure')),
        isFalse,
      );
    });

    test('rejects an unrelated deeplink', () {
      expect(
        DeepLinkService.isOAuthSuccessUri(Uri.parse('fileforge://home')),
        isFalse,
      );
    });
  });
}
