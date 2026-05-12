/// Phase 6 파일 미리보기 — 확장자 기반 previewType 판별 유틸리티
/// D006 §2, §8-3, P007 §1 기준
///
/// 확장자 매핑 테이블:
///   image:       jpg, jpeg, png, gif, webp, bmp
///   text:        txt, md, json, yaml, yml, xml, csv, log, js, ts, css, html, py, java, dart
///   pdf:         pdf
///   video:       mp4, webm, ogg, mov  (ogg: 비디오 우선 — D006 §2)
///   audio:       mp3, wav, flac, m4a
///   unsupported: 그 외 (svg 포함, 확장자 없는 파일 포함)
enum PreviewType { image, text, pdf, video, audio, unsupported }

class FileTypeHelper {
  FileTypeHelper._();

  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  static const _textExts = {
    'txt', 'md', 'json', 'yaml', 'yml', 'xml', 'csv', 'log',
    'js', 'ts', 'css', 'html', 'py', 'java', 'dart',
  };
  static const _pdfExts = {'pdf'};
  // ogg: 비디오/오디오 중복 → 비디오 우선 매핑 (D006 §2, 웹 FilePreviewModal.vue 동일 처리)
  static const _videoExts = {'mp4', 'webm', 'ogg', 'mov'};
  static const _audioExts = {'mp3', 'wav', 'flac', 'm4a'};

  /// [fileName]에서 확장자를 추출하고 [PreviewType]을 반환한다.
  ///
  /// - 확장자 없는 파일 → [PreviewType.unsupported]
  /// - svg → [PreviewType.unsupported] (D006 §8-3: Flutter Image.memory SVG 미지원)
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

  /// [fileName]에서 확장자를 소문자로 추출한다.
  /// 마지막 '.' 이후 문자열. '.' 없거나 끝에 '.'인 경우 빈 문자열 반환.
  static String _extractExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) return '';
    return fileName.substring(dotIndex + 1).toLowerCase();
  }
}
