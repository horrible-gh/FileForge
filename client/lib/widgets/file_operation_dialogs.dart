import 'package:flutter/material.dart';

/// D003 §2-4 — folder create, name change, delete text, text delete text translated text text

class FileOperationDialogs {
  /// folder create translated text — text text folder name return, cancel text null.
  static Future<String?> showCreateFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final name = v.trim();
            if (name.isNotEmpty) Navigator.of(ctx).pop(name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.of(ctx).pop(name);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// name change translated text — text text text name return, cancel text null.
  static Future<String?> showRenameDialog(
    BuildContext context, {
    required String currentName,
  }) {
    final controller = TextEditingController(text: currentName);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: currentName.contains('.')
          ? currentName.lastIndexOf('.')
          : currentName.length,
    );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'New name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final name = v.trim();
            if (name.isNotEmpty) Navigator.of(ctx).pop(name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.of(ctx).pop(name);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// delete text translated text — text text true, cancel text false.
  static Future<bool> showDeleteConfirmDialog(
    BuildContext context, {
    required String name,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text("Delete '$name'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// text delete text translated text
  static Future<bool> showBulkDeleteConfirmDialog(
    BuildContext context, {
    required int count,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Delete'),
        content: Text('Delete $count items?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
