/// Mail body rendering helpers (R0001 / 0007 — "이미지 표시가 되지 않음").
///
/// The mail detail body used to be rendered by stripping **every** HTML tag,
/// which removed `<img>` too — so no picture ever showed. This splits an HTML
/// body into an ordered list of text + image segments so the detail screen can
/// render images inline (data: URIs decoded to bytes, http(s) URLs fetched)
/// while keeping the readable plain-text rendering for everything else.
///
/// Dependency-free on purpose (no HTML-renderer package): it targets the one
/// thing R0001 is about — making images appear — without a fidelity-heavy
/// renderer or a new pub dependency.
library;

import 'dart:typed_data';

/// A run of the rendered body: either readable [text] or an [imageSrc] picture.
class MailBodySegment {
  /// Stripped, entity-decoded plain text. Empty for image segments.
  final String text;

  /// `data:`/`http(s)` image source. `null` for text segments.
  final String? imageSrc;

  const MailBodySegment.text(this.text) : imageSrc = null;
  const MailBodySegment.image(this.imageSrc) : text = '';

  bool get isImage => imageSrc != null;

  /// For a `data:` image segment, the decoded bytes; otherwise `null`.
  Uint8List? get dataBytes {
    final src = imageSrc;
    if (src == null || !src.startsWith('data:')) return null;
    try {
      final data = Uri.parse(src).data;
      return data?.contentAsBytes();
    } catch (_) {
      return null;
    }
  }

  bool get isNetworkImage {
    final src = imageSrc;
    return src != null && (src.startsWith('http://') || src.startsWith('https://'));
  }
}

final RegExp _imgTagRe = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final RegExp _srcAttrRe = RegExp(
  r'''src\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
  caseSensitive: false,
);

/// Strip tags + decode the common entities — the readable plain-text fallback
/// (same rules the detail screen used before, kept identical for text runs).
String stripHtmlToText(String html) {
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

String? _extractImgSrc(String imgTag) {
  final m = _srcAttrRe.firstMatch(imgTag);
  if (m == null) return null;
  final src = (m.group(1) ?? m.group(2) ?? m.group(3) ?? '').trim();
  return src.isEmpty ? null : src;
}

/// Split an HTML body into ordered text/image segments.
///
/// Only `data:` and `http(s)` images are emitted (a leftover `cid:` that the
/// server could not inline is dropped — there is nothing fetchable to show).
/// Text runs are tag-stripped; empty runs are omitted so the caller can lay the
/// segments out without blank gaps.
List<MailBodySegment> parseMailHtmlBody(String html) {
  final segments = <MailBodySegment>[];
  var cursor = 0;

  void addText(String raw) {
    final text = stripHtmlToText(raw);
    if (text.isNotEmpty) segments.add(MailBodySegment.text(text));
  }

  for (final m in _imgTagRe.allMatches(html)) {
    addText(html.substring(cursor, m.start));
    final src = _extractImgSrc(m.group(0)!);
    if (src != null &&
        (src.startsWith('data:') ||
            src.startsWith('http://') ||
            src.startsWith('https://'))) {
      segments.add(MailBodySegment.image(src));
    }
    cursor = m.end;
  }
  addText(html.substring(cursor));
  return segments;
}
