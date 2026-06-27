import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/utils/mail_body_render.dart';

void main() {
  group('parseMailHtmlBody', () {
    test('splits text and a data: image into ordered segments', () {
      const b64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
      final html = '<div>hello <img src="data:image/png;base64,$b64"> world</div>';
      final segs = parseMailHtmlBody(html);
      expect(segs.length, 3);
      expect(segs[0].isImage, false);
      expect(segs[0].text, 'hello');
      expect(segs[1].isImage, true);
      expect(segs[1].dataBytes, isNotNull);
      expect(segs[1].dataBytes, base64Decode(b64));
      expect(segs[2].text, 'world');
    });

    test('classifies a remote image as a network segment', () {
      final segs = parseMailHtmlBody('<p><img src="https://x.test/p.png"></p>');
      expect(segs.length, 1);
      expect(segs.first.isImage, true);
      expect(segs.first.isNetworkImage, true);
      expect(segs.first.dataBytes, isNull);
    });

    test('drops an unresolved cid: image (nothing fetchable)', () {
      final segs = parseMailHtmlBody('<div>txt <img src="cid:leftover"> end</div>');
      // cid image dropped; the two text runs survive.
      expect(segs.every((s) => !s.isImage), true);
      expect(segs.map((s) => s.text).join(' '), 'txt end');
    });

    test('text-only HTML yields a single stripped text segment', () {
      final segs = parseMailHtmlBody('<p>just&nbsp;text</p>');
      expect(segs.length, 1);
      expect(segs.first.isImage, false);
      expect(segs.first.text, 'just text');
    });

    test('handles single-quoted src and uppercase IMG', () {
      final segs = parseMailHtmlBody("<IMG SRC='https://x.test/a.gif'>");
      expect(segs.length, 1);
      expect(segs.first.isNetworkImage, true);
    });
  });

  group('stripHtmlToText', () {
    test('strips tags and decodes entities, br/p to newlines', () {
      final out = stripHtmlToText('<p>a&amp;b<br>c</p><p>d</p>');
      expect(out.contains('a&b'), true);
      expect(out.contains('\n'), true);
      expect(out.contains('<'), false);
    });
  });
}
