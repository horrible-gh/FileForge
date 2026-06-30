import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// D003 §2-4 — folder create, name change, delete text, text delete text translated text text

class FileOperationDialogs {
  /// folder create translated text — text text folder name return, cancel text null.
  static Future<String?> showCreateFolderDialog(BuildContext context) {
    final t = AppLocalizations.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.folderNew),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: t.folderName,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final name = v.trim();
            if (name.isNotEmpty) Navigator.of(ctx).pop(name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.of(ctx).pop(name);
            },
            child: Text(t.commonOk),
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
    final t = AppLocalizations.of(context);
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
        title: Text(t.commonRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: t.renameNewName,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final name = v.trim();
            if (name.isNotEmpty) Navigator.of(ctx).pop(name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.of(ctx).pop(name);
            },
            child: Text(t.commonOk),
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
    final t = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.commonDelete),
        content: Text(t.deleteConfirmName(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.commonDelete),
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
    final t = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.bulkDeleteTitle),
        content: Text(t.bulkDeleteConfirmCount(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.commonDelete),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
