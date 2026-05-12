// Non-web stub — dart.library.io 환경(Android, iOS, Desktop)에서 사용
// 모든 함수는 no-op이며 실제 구현은 web_directory_drop.dart에 있다.

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
