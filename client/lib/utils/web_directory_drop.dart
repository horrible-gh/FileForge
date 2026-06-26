// Flutter text text — dart:library.io translated text web_directory_drop_stub.dart text
// DropzoneView translated text translated text stage drop translated text registertext
// directory text text text text + relativePath translated text translated text. (T057)

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

typedef WebDropFileInfo = ({
  String name,
  Uint8List bytes,
  String relativePath,
});

/// DropzoneView translated text translated text stage drop translated text registertext.
///
/// - directorytext translated text text: text text text [onFilesReady] text. flutter_dropzone text translated text text.
/// - text file text: translated text text returntext flutter_dropzonetext text translated text text.
///
/// [viewId]text [DropzoneViewController.viewId]text translated text.
void registerDirectoryCaptureDrop({
  required int viewId,
  required void Function(List<WebDropFileInfo>) onFilesReady,
}) {
  // addPostFrameCallback text DOM translated text completetext translated text text
  Future.delayed(Duration.zero, () {
    final el = web.document.getElementById('dropzone-container-$viewId')
        as web.HTMLDivElement?;
    if (el == null) return;

    void onDrop(web.Event event) {
      final dragEvent = event as web.DragEvent;
      final items = dragEvent.dataTransfer?.items;
      if (items == null) return;

      // [NR028 C5] webkitGetAsEntry()text translated text drop translated text text translated text text
      final entries = <web.FileSystemEntry>[];
      bool hasDirectory = false;
      for (var i = 0; i < items.length; i++) {
        final entry = items[i].webkitGetAsEntry();
        if (entry != null) {
          entries.add(entry);
          if (entry.isDirectory) hasDirectory = true;
        }
      }

      // directorytext translated text flutter_dropzonetext text onDropFiles translated text text
      if (!hasDirectory) return;

      // directory text: flutter_dropzone text translated text translated text text text
      event.preventDefault();
      event.stopImmediatePropagation();

      // translated text text fire-and-forget (error text)
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
  // [NR028 C4] fullPath text name translated text relativePath text
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
      // text failed file translated text
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
  // [NR028 C3] empty text return translated text text text (100text text text text)
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
