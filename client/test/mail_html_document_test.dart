import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/utils/mail_html_document.dart';

void main() {
  test('mail is base64 data, never executable template markup', () {
    const raw = '</script><script>window.senderRan=true</script>'
        '<p onclick="attack()">한국어 日本語 café</p>';
    final doc = MailHtmlDocument(raw);
    expect(doc.html, isNot(contains(raw)));
    final payload = RegExp(r"atob\('([^']+)'\)").firstMatch(doc.html)!.group(1)!;
    expect(utf8.decode(base64Decode(payload)), raw);
    expect(RegExp(r'<script(?:\s|>)').allMatches(doc.html).length, 1);
    expect(doc.html, isNot(contains('__FF_TOKEN__')));
    expect(doc.html, isNot(contains('__FF_PAYLOAD__')));
    expect(doc.html, isNot(contains('__FF_SCRIPT__')));
  });

  test('each document has its own cryptographic channel / CSP nonce', () {
    final docs = List.generate(20, (_) => MailHtmlDocument('<p>same</p>'));
    expect(docs.map((d) => d.token).toSet().length, docs.length);
    for (final doc in docs) {
      expect(doc.token, matches(RegExp(r'^[A-Za-z0-9_-]{32}$')));
      expect(doc.html, contains("script-src 'nonce-${doc.token}'"));
      expect(doc.html, contains('nonce="${doc.token}"'));
      expect(doc.html, isNot(contains("'unsafe-eval'")));
      expect(doc.html.indexOf('Content-Security-Policy'),
          lessThan(doc.html.indexOf('<script')));
    }
  });

  test('CSP blocks active content and local-file access', () {
    final html = MailHtmlDocument('<table><tr><td>data</td></tr></table>').html;
    for (final policy in [
      "default-src 'none'", "script-src-attr 'none'", "connect-src 'none'",
      "frame-src 'none'", "object-src 'none'", "base-uri 'none'", "form-action 'none'",
    ]) {
      expect(html, contains(policy));
    }
    expect(html, contains('img-src https: http: data:'));
    expect(html, isNot(contains('img-src file:')));
    expect(html, isNot(contains("display': 'block'")));
  });
}
