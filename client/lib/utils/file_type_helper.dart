/// Phase 6 file translated text — translated text text previewType text translated text
/// D006 §2, §8-3, P007 §1 text
///
/// translated text text translated text:
///   image:       jpg, jpeg, png, gif, webp, bmp
///   text:        txt, md, json, yaml, yml, xml, csv, log, js, ts, css, html, py, java, dart
///   pdf:         pdf
///   video:       mp4, webm, ogg, mov  (ogg: translated text text — D006 §2)
///   audio:       mp3, wav, flac, m4a
///   unsupported: text text (svg text, translated text text file text)
enum PreviewType { image, text, pdf, video, audio, unsupported }

class FileTypeHelper {
  FileTypeHelper._();

  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  static const _textExts = {
    'txt', 'md', 'json', 'yaml', 'yml', 'xml', 'csv', 'log',
    'js', 'ts', 'css', 'html', 'py', 'java', 'dart',
  };
  static const _pdfExts = {'pdf'};
  // ogg: translated text/translated text text → translated text text text (D006 §2, text FilePreviewModal.vue text text)
  static const _videoExts = {'mp4', 'webm', 'ogg', 'mov'};
  static const _audioExts = {'mp3', 'wav', 'flac', 'm4a'};

  /// [fileName]text translated text translated text [PreviewType]text returntext.
  ///
  /// - translated text text file → [PreviewType.unsupported]
  /// - svg → [PreviewType.unsupported] (D006 §8-3: Flutter Image.memory SVG translated text)
  static PreviewType getPreviewType(String fileName) {
    final ext = _extractExtension(fileName);
    if (ext.isEmpty) return PreviewType.unsupported;
    if (_imageExts.contains(ext)) return PreviewType.image;
    if (_textExts.contains(ext)) return PreviewType.text;
    if (_pdfExts.contains(ext)) return PreviewType.pdf;
    if (_videoExts.contains(ext)) return PreviewType.video;
    if (_audioExts.contains(ext)) return PreviewType.audio;
    return PreviewType.unsupported;
  }

  /// [fileName]text translated text translated text translated text.
  /// translated text '.' text string. '.' translated text text '.'text text empty string return.
  static String _extractExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) return '';
    return fileName.substring(dotIndex + 1).toLowerCase();
  }
}
