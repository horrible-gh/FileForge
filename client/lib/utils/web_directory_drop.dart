// Flutter 웹 전용 — dart:library.io 환경에서는 web_directory_drop_stub.dart 사용
// DropzoneView 컨테이너에 캡처링 단계 drop 핸들러를 등록하여
// 디렉터리 드롭 시 재귀 순회 + relativePath 구성을 수행한다. (T057)

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

typedef WebDropFileInfo = ({
  String name,
  Uint8List bytes,
  String relativePath,
});

/// DropzoneView 컨테이너에 캡처링 단계 drop 핸들러를 등록한다.
///
/// - 디렉터리가 포함된 드롭: 재귀 순회 후 [onFilesReady] 호출. flutter_dropzone 버블 핸들러 차단.
/// - 순수 파일 드롭: 핸들러가 조기 반환하여 flutter_dropzone의 기존 흐름에 위임.
///
/// [viewId]는 [DropzoneViewController.viewId]와 동일하다.
void registerDirectoryCaptureDrop({
  required int viewId,
  required void Function(List<WebDropFileInfo>) onFilesReady,
}) {
  // addPostFrameCallback 이후 DOM 삽입이 완료된 시점에 실행
  Future.delayed(Duration.zero, () {
    final el = web.document.getElementById('dropzone-container-$viewId')
        as web.HTMLDivElement?;
    if (el == null) return;

    void onDrop(web.Event event) {
      final dragEvent = event as web.DragEvent;
      final items = dragEvent.dataTransfer?.items;
      if (items == null) return;

      // [NR028 C5] webkitGetAsEntry()는 반드시 drop 핸들러 동기 구간에서 호출
      final entries = <web.FileSystemEntry>[];
      bool hasDirectory = false;
      for (var i = 0; i < items.length; i++) {
        final entry = items[i].webkitGetAsEntry();
        if (entry != null) {
          entries.add(entry);
          if (entry.isDirectory) hasDirectory = true;
        }
      }

      // 디렉터리가 없으면 flutter_dropzone의 기존 onDropFiles 흐름에 위임
      if (!hasDirectory) return;

      // 디렉터리 포함: flutter_dropzone 버블 핸들러를 차단하고 직접 처리
      event.preventDefault();
      event.stopImmediatePropagation();

      // 비동기 순회 fire-and-forget (에러 무시)
      _processAllEntries(entries, onFilesReady).catchError((_) {});
    }

    el.addEventListener('drop', onDrop.toJS, true.toJS);
  });
}

Future<void> _processAllEntries(
  List<web.FileSystemEntry> entries,
  void Function(List<WebDropFileInfo>) onFilesReady,
) async {
  final results = <WebDropFileInfo>[];
  for (final entry in entries) {
    await _traverseEntry(entry, '', results);
  }
  if (results.isNotEmpty) {
    onFilesReady(results);
  }
}

Future<void> _traverseEntry(
  web.FileSystemEntry entry,
  String parentPath,
  List<WebDropFileInfo> results,
) async {
  // [NR028 C4] fullPath 대신 name 누적으로 relativePath 구성
  final relativePath =
      parentPath.isEmpty ? entry.name : '$parentPath/${entry.name}';

  if (entry.isFile) {
    try {
      final bytes = await _readFileEntry(entry as web.FileSystemFileEntry);
      results.add((
        name: entry.name,
        bytes: bytes,
        relativePath: relativePath,
      ));
    } catch (_) {
      // 읽기 실패 파일 건너뜀
    }
  } else if (entry.isDirectory) {
    await _traverseDirectory(
      entry as web.FileSystemDirectoryEntry,
      relativePath,
      results,
    );
  }
}

Future<void> _traverseDirectory(
  web.FileSystemDirectoryEntry dirEntry,
  String path,
  List<WebDropFileInfo> results,
) async {
  final reader = dirEntry.createReader();
  // [NR028 C3] 빈 배열 반환 시까지 반복 호출 (100개 배치 제한 대응)
  while (true) {
    final batch = await _readEntries(reader);
    if (batch.isEmpty) break;
    for (final entry in batch) {
      await _traverseEntry(entry, path, results);
    }
  }
}

Future<Uint8List> _readFileEntry(web.FileSystemFileEntry fileEntry) async {
  final completer = Completer<web.File>();
  fileEntry.file(
    ((web.File f) => completer.complete(f)).toJS,
    ((JSObject err) => completer.completeError(err)).toJS,
  );
  final file = await completer.future;
  final buffer = await file.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

Future<List<web.FileSystemEntry>> _readEntries(
  web.FileSystemDirectoryReader reader,
) async {
  final completer = Completer<List<web.FileSystemEntry>>();
  reader.readEntries(
    ((JSArray<web.FileSystemEntry> arr) {
      completer.complete(arr.toDart);
    }).toJS,
    ((JSObject err) => completer.completeError(err)).toJS,
  );
  return completer.future;
}
