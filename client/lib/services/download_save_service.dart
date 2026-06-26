import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'download_web_interop.dart'
    if (dart.library.io) 'download_web_interop_stub.dart';

// ── translated text save text ────────────────────────────────────────────────────────

/// translated text save text
/// - web: `dart:js_interop`text browser Blob download translated text
/// - Android: MethodChanneltext text translated text Downloads foldertext save
/// - non-web: `getApplicationDocumentsDirectory` + `dart:io File.writeAsBytes`
class DownloadSaveService {
  static const _channel =
      MethodChannel('com.fileforge.file_forge_app/downloads');

  /// bytestext translated text text translated text savetext.
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

  /// Content-Disposition translated text filetext translated text.
  /// RFC 5987 text text(`filename*=UTF-8''encoded`)text text translated text,
  /// translated text text text(`filename="name"`)text fallbacktext.
  /// parse failed text null text text null return.
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

    // text text: filename="name" text filename=name
    final simpleMatch =
        RegExp(r'''filename\s*=\s*["\']?([^"\';\r\n]+)["\']?''')
            .firstMatch(contentDisposition);
    return simpleMatch?.group(1)?.trim();
  }

  // ── text text ──────────────────────────────────────────────────────────────

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
