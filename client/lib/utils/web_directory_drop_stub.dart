// Non-web stub — dart.library.io text(Android, iOS, Desktop)text text
// all translated text no-optext text translated text web_directory_drop.darttext text.

import 'dart:typed_data';

typedef WebDropFileInfo = ({
  String name,
  Uint8List bytes,
  String relativePath,
});

void registerDirectoryCaptureDrop({
  required int viewId,
  required void Function(List<WebDropFileInfo>) onFilesReady,
}) {
  // no-op on non-web platforms
}
