/// Detecting URLs inside a **plain-text** mail body so they can be rendered as
/// tappable links (R0001 / 0031, NR0003 root cause B).
///
/// Plain-text bodies were rendered with a bare [Text], so a `https://…` in the
/// message was just glyphs — not openable. This splits the text into ordered
/// runs of plain text and links; the detail screen turns link runs into tappable
/// spans. Pure and dependency-free so it is unit-testable.
library;

/// One run of a linkified plain-text body: either [url] is null (plain text) or
/// non-null (a link whose visible label is [text]).
class MailTextRun {
  final String text;
  final String? url;

  const MailTextRun.text(this.text) : url = null;
  const MailTextRun.link(this.text, this.url);

  bool get isLink => url != null;
}

// http(s) URLs and bare `www.` hosts. Stops at whitespace and the angle
// brackets / quotes that commonly *wrap* a URL; trailing sentence punctuation is
// trimmed back out below so "see https://x.test." doesn't swallow the period.
final RegExp _urlRe = RegExp(
  r'((?:https?://|www\.)[^\s<>()\[\]"]+)',
  caseSensitive: false,
);

/// Characters that are valid mid-URL but, when trailing, are almost always
/// sentence punctuation rather than part of the link.
const String _trailingTrim = '.,;:!?\'"';

/// Split [text] into ordered plain/link runs. Adjacent plain text is preserved
/// verbatim (whitespace included) so the rendered body is byte-identical to the
/// original except that links become tappable.
List<MailTextRun> linkifyPlainText(String text) {
  final runs = <MailTextRun>[];
  var cursor = 0;

  for (final m in _urlRe.allMatches(text)) {
    var raw = m.group(0)!;
    var start = m.start;
    var end = m.end;

    // Trim trailing punctuation back into the following plain run.
    while (raw.isNotEmpty && _trailingTrim.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
      end--;
    }
    if (raw.isEmpty) continue;

    if (start > cursor) {
      runs.add(MailTextRun.text(text.substring(cursor, start)));
    }
    final url = raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw;
    runs.add(MailTextRun.link(raw, url));
    cursor = end;
  }

  if (cursor < text.length) {
    runs.add(MailTextRun.text(text.substring(cursor)));
  }
  // A body with no URLs still yields a single plain run.
  if (runs.isEmpty) runs.add(MailTextRun.text(text));
  return runs;
}
