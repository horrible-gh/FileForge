import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'download_web_interop.dart'
    if (dart.library.io) 'download_web_interop_stub.dart';

// ── 플랫폼별 저장 헬퍼 ────────────────────────────────────────────────────────

/// 플랫폼별 저장 헬퍼
/// - web: `dart:js_interop`으로 브라우저 Blob 다운로드 트리거
/// - Android: MethodChannel을 통해 네이티브 Downloads 폴더에 저장
/// - non-web: `getApplicationDocumentsDirectory` + `dart:io File.writeAsBytes`
class DownloadSaveService {
  static const _channel =
      MethodChannel('com.fileforge.file_forge_app/downloads');

  /// 바이트를 플랫폼에 맞는 방식으로 저장한다.
  static Future<void> saveBytes({
    required List<int> bytes,
    required String filename,
  }) async {
    if (kIsWeb) {
      triggerBrowserDownload(bytes, filename);
    } else if (io.Platform.isAndroid) {
      await _saveToAndroidDownloads(bytes, filename);
    } else {
      await _saveToLocalFile(bytes, filename);
    }
  }

  /// Content-Disposition 헤더값에서 파일명을 추출한다.
  /// RFC 5987 확장 형식(`filename*=UTF-8''encoded`)을 우선 처리하고,
  /// 없으면 단순 형식(`filename="name"`)으로 fallback한다.
  /// 파싱 실패 또는 null 입력 시 null 반환.
  static String? extractFilename(String? contentDisposition) {
    if (contentDisposition == null || contentDisposition.isEmpty) return null;

    // RFC 5987: filename*=UTF-8''percent-encoded-name
    final extMatch =
        RegExp(r"filename\*\s*=\s*[Uu][Tt][Ff]-8''([^\s;]+)")
            .firstMatch(contentDisposition);
    if (extMatch != null) {
      final encoded = extMatch.group(1) ?? '';
      try {
        return Uri.decodeFull(encoded).trim();
      } catch (_) {
        return encoded.trim();
      }
    }

    // 단순 형식: filename="name" 또는 filename=name
    final simpleMatch =
        RegExp(r'''filename\s*=\s*["\']?([^"\';\r\n]+)["\']?''')
            .firstMatch(contentDisposition);
    return simpleMatch?.group(1)?.trim();
  }

  // ── 내부 구현 ──────────────────────────────────────────────────────────────

  static Future<void> _saveToAndroidDownloads(
      List<int> bytes, String filename) async {
    await _channel.invokeMethod<void>('saveToDownloads', {
      'filename': filename,
      'bytes': Uint8List.fromList(bytes),
    });
  }

  static Future<void> _saveToLocalFile(List<int> bytes, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = io.File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
  }
}
