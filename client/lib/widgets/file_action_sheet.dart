import 'package:flutter/material.dart';
import '../models/node.dart';

/// D003 §2-3 — 케밥메뉴 (BottomSheet)
/// 파일: 다운로드, 이름 변경, 공유 (disabled), 미리보기 (disabled), 삭제
/// 폴더: 다운로드, 이름 변경, 공유 (disabled), 삭제
/// note 스토리지: 다운로드 미노출
enum FileAction { download, rename, share, preview, delete }

class FileActionSheet extends StatelessWidget {
  final Node node;
  final String storageType;
  final void Function(FileAction action) onAction;

  const FileActionSheet({
    super.key,
    required this.node,
    required this.storageType,
    required this.onAction,
  });

  static Future<FileAction?> show(
    BuildContext context, {
    required Node node,
    required String storageType,
  }) {
    return showModalBottomSheet<FileAction>(
      context: context,
      builder: (_) => FileActionSheet(
        node: node,
        storageType: storageType,
        onAction: (action) => Navigator.of(context).pop(action),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFile = node.isFile;
    final isFileStorage = storageType == 'file';

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              node.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          // Download — file storage only
          if (isFileStorage)
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Download'),
              onTap: () => onAction(FileAction.download),
            ),
          // Rename
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('Rename'),
            onTap: () => onAction(FileAction.rename),
          ),
          // Share — file storage only, Phase 5
          if (isFileStorage)
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Share'),
              onTap: () => onAction(FileAction.share),
            ),
          // Preview — files only, file storage only (D006 §1-3, §13-1)
          if (isFile && isFileStorage)
            ListTile(
              leading: const Icon(Icons.visibility_rounded),
              title: const Text('Preview'),
              onTap: () => onAction(FileAction.preview),
            ),
          // Delete
          ListTile(
            leading: const Icon(Icons.delete_rounded, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () => onAction(FileAction.delete),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
