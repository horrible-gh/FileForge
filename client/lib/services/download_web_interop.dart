// Web-only JS interop bindings for DownloadSaveService.
// Imported conditionally: download_save_service.dart uses
//   import '…_web_interop.dart' if (dart.library.io) '…_stub.dart'
// This file is only compiled when targeting JS/Wasm (web).
import 'dart:js_interop';
import 'dart:typed_data';

@JS('Blob')
extension type _JsBlob._(JSObject _) implements JSObject {
  external factory _JsBlob(JSArray<JSUint8Array> parts);
}

extension type _JsAnchor._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
  external void remove();
}

@JS('URL.createObjectURL')
external String _jsCreateObjectUrl(_JsBlob blob);

@JS('URL.revokeObjectURL')
external void _jsRevokeObjectUrl(String url);

@JS('document.createElement')
external JSObject _jsCreateElement(String tag);

@JS('document.body.appendChild')
external void _jsBodyAppendChild(JSObject el);

/// browser Blob download translated text (text text).
void triggerBrowserDownload(List<int> bytes, String filename) {
  // bytes.toList() text fresh copytext detached ArrayBuffer text text (T036)
  final uint8 = Uint8List.fromList(bytes.toList());
  final blob = _JsBlob([uint8.toJS].toJS);
  final url = _jsCreateObjectUrl(blob);
  final anchor = _JsAnchor._(_jsCreateElement('a'));
  anchor.href = url;
  anchor.download = filename;
  _jsBodyAppendChild(anchor);
  anchor.click();
  anchor.remove();
  _jsRevokeObjectUrl(url);
}
