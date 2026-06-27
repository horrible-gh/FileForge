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

    // 0008 R0001: CSS inside <style> must not surface as body text.
    test('drops <style> block content (no CSS leak)', () {
      const html = '<style>.sup{vertical-align:1px !important;}'
          '\n@media all and (max-width:480px){.pad0{padding:0;}}</style>'
          '<p>本文テキスト</p>';
      final out = stripHtmlToText(html);
      expect(out.contains('本文テキスト'), true);
      expect(out.contains('vertical-align'), false);
      expect(out.contains('@media'), false);
      expect(out.contains('.sup'), false);
    });

    test('drops <script>, <head> metadata and HTML comments', () {
      const html = '<head><title>hidden</title>'
          '<style>body{font-size:12px;}</style></head>'
          '<!-- tracking pixel comment -->'
          '<script>var x = 1; alert(x);</script>'
          '<div>visible</div>';
      final out = stripHtmlToText(html);
      expect(out, 'visible');
      expect(out.contains('font-size'), false);
      expect(out.contains('alert'), false);
      expect(out.contains('hidden'), false);
      expect(out.contains('tracking pixel'), false);
    });
  });

  group('parseMailHtmlBody — style hygiene (R0001)', () {
    test('text segments never carry leaked <style> CSS', () {
      const html = '<style>.x{color:red;}</style>'
          '<div>before <img src="https://x.test/a.png"> after</div>';
      final segs = parseMailHtmlBody(html);
      final text = segs.where((s) => !s.isImage).map((s) => s.text).join(' ');
      expect(text.contains('color:red'), false);
      expect(text.contains('.x{'), false);
      expect(segs.any((s) => s.isNetworkImage), true);
    });
  });
}
