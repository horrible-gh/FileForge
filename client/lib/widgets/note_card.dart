import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/node.dart';

/// file nametext translated text translated text text translated text returntext.
/// nametext translated text translated text translated text translated text translated text returntext.
String getNoteName(String name) {
  final lastDot = name.lastIndexOf('.');
  return lastDot > 0 ? name.substring(0, lastDot) : name;
}

/// [T043] modifiedAt text text text string return.
/// null text empty string return.
String formatRelativeDate(DateTime? modifiedAt, AppLocalizations t) {
  if (modifiedAt == null) return '';
  final diff = DateTime.now().difference(modifiedAt);
  if (diff.inMinutes < 1) return t.relativeJustNow;
  if (diff.inMinutes < 60) return t.relativeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return t.relativeHoursAgo(diff.inHours);
  return '${modifiedAt.month}/${modifiedAt.day}';
}

/// note storage text text text.
/// - type=file: text/preview/text + text(textselectiontext) or translated text(selectiontext)
/// - type=folder: folder translated text/foldertext/text + translated text(selectiontext)
class NoteCard extends StatelessWidget {
  final Node node;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const NoteCard({
    super.key,
    required this.node,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: node.isFolder
              ? _buildFolderContent(context)
              : _buildFileContent(context),
        ),
      ),
    );
  }

  Widget _buildFileContent(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // text: text + text(textselectiontext) or translated text(selectiontext)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                getNoteName(node.name),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (isSelectionMode)
              _SelectionCheckbox(isSelected: isSelected)
            else
              _KebabMenu(onRename: onRename, onDelete: onDelete),
          ],
        ),
        const SizedBox(height: 4),
        // Body: preview text 3text
        Expanded(
          child: node.preview != null && node.preview!.isNotEmpty
              ? Text(
                  node.preview!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 4),
        // text: text text
        Text(
          formatRelativeDate(node.modifiedAt, t),
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildFolderContent(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // text: folder translated text + foldertext + translated text(selectiontext)
        Row(
          children: [
            Icon(Icons.folder_rounded, size: 18, color: colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (isSelectionMode) _SelectionCheckbox(isSelected: isSelected),
          ],
        ),
        // Body None
        const Spacer(),
        // text: updatetext
        Text(
          formatRelativeDate(node.modifiedAt, t),
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _SelectionCheckbox extends StatelessWidget {
  final bool isSelected;

  const _SelectionCheckbox({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: SizedBox(
        width: 20,
        height: 20,
        child: Checkbox(
          value: isSelected,
          onChanged: (_) {},
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _KebabMenu extends StatelessWidget {
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const _KebabMenu({this.onRename, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        if (value == 'rename') onRename?.call();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'rename', child: Text(t.commonRename)),
        PopupMenuItem(value: 'delete', child: Text(t.commonDelete)),
      ],
    );
  }
}
