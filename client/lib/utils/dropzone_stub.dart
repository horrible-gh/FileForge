// Non-web stub for flutter_dropzone — provides empty type placeholders
// so that dart.library.io platforms compile without errors.
// Actual dropzone functionality is web-only (kIsWeb guard required).

import 'package:flutter/material.dart';

enum DragOperation { copy }
// ignore: constant_identifier_names
enum CursorType { Default }

class DropzoneViewController {
  int viewId = 0;
  Future<String> getFilename(dynamic file) async => '';
  Future<List<int>> getFileData(dynamic file) async => [];
}

class DropzoneView extends StatelessWidget {
  final DragOperation operation;
  final CursorType cursor;
  final void Function(DropzoneViewController)? onCreated;
  final void Function()? onHover;
  final void Function()? onLeave;
  final void Function(List<dynamic>?)? onDropFiles;

  const DropzoneView({
    super.key,
    this.operation = DragOperation.copy,
    this.cursor = CursorType.Default,
    this.onCreated,
    this.onHover,
    this.onLeave,
    this.onDropFiles,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
