import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/services/deep_link_service.dart';

/// R0001/NR0003/T0004 §Option C — guards against regression in the OAuth success deeplink
/// (fileforge://oauth/gmail/success) detection logic. It must match the scheme the server's
/// _oauth_result_page auto-redirects to, so the app reloads the account list on foreground return.
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
