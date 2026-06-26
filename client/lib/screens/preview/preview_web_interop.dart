// Web-only JS interop bindings for FilePreviewScreen.
// Imported conditionally: file_preview_screen.dart uses
//   import '…_web_interop.dart' if (dart.library.io) '…_stub.dart'
// This file is only compiled when targeting JS/Wasm (web).
import 'dart:js_interop';
import 'dart:typed_data';

@JS()
@anonymous
extension type _BlobPropertyBag._(JSObject _) implements JSObject {
  external factory _BlobPropertyBag({String type});
}

@JS('Blob')
extension type _PreviewJsBlob._(JSObject _) implements JSObject {
  external factory _PreviewJsBlob(
      JSArray<JSUint8Array> parts, _BlobPropertyBag options);
}

@JS('URL.createObjectURL')
external String _previewCreateObjectUrl(_PreviewJsBlob blob);

@JS('URL.revokeObjectURL')
external void _previewRevokeObjectUrl(String url);

/// bytes + mimeTypetranslated text Blob URLtext createtext (text text).
String previewCreateBlobUrl(List<int> bytes, String mimeType) {
  // bytes.toList() text fresh copytext detached ArrayBuffer text text (T036)
  final uint8 = Uint8List.fromList(bytes.toList());
  final blob =
      _PreviewJsBlob([uint8.toJS].toJS, _BlobPropertyBag(type: mimeType));
  return _previewCreateObjectUrl(blob);
}

/// Blob URLtext translated text (text text).
void previewRevokeBlobUrl(String url) => _previewRevokeObjectUrl(url);
