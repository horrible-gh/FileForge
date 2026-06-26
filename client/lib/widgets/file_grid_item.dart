import 'package:flutter/material.dart';
import '../models/node.dart';

/// translated text text file/folder text text (T052, T054)
/// text: Card(clipBehavior) → InkWell → Padding → Column (NoteCard text)
class FileGridItem extends StatelessWidget {
  final Node node;

  /// folder text text text. filetext null.
  final VoidCallback? onFolderTap;

  /// file text text text.
  final VoidCallback? onFileTap;

  /// text text text text text.
  final VoidCallback? onKebabTap;

  /// translated text text text.
  final VoidCallback? onLongPress;

  /// selection text text text text.
  final VoidCallback? onSelectionTap;

  /// selection text text.
  final bool isSelectionMode;

  /// selection text.
  final bool isSelected;

  const FileGridItem({
    super.key,
    required this.node,
    this.onFolderTap,
    this.onFileTap,
    this.onKebabTap,
    this.onLongPress,
    this.onSelectionTap,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final onTap = isSelectionMode
        ? onSelectionTap
        : (node.isFolder ? onFolderTap : onFileTap);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            // ── text translated text ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // translated text (selection translated text text translated text text)
                  if (isSelectionMode)
                    _SelectionCheckbox(isSelected: isSelected)
                  else
                    _buildIcon(context),
                  const SizedBox(height: 6),
                  // filetext — text 2text ellipsis
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      node.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            // ── text text (translated text text, textselection text) ─────────────────
            if (!isSelectionMode && onKebabTap != null)
              Positioned(
                  top: 0,
                  right: 0,
                  child: InkWell(
                    onTap: onKebabTap,
                    borderRadius: BorderRadius.circular(14),
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                        child: Icon(Icons.more_vert, size: 16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    if (node.isFolder) {
      return Icon(Icons.folder_rounded, color: Colors.amber.shade700, size: 40);
    }
    return Icon(
      _fileIcon(node.name),
      color: Theme.of(context).colorScheme.secondary,
      size: 40,
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.video_file_rounded;
      case 'mp3':
      case 'aac':
      case 'wav':
        return Icons.audio_file_rounded;
      case 'zip':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_rounded;
      case 'txt':
      case 'md':
      case 'log':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}

/// NoteCard._SelectionCheckbox translated text translated text translated text text (T054)
class _SelectionCheckbox extends StatelessWidget {
  final bool isSelected;

  const _SelectionCheckbox({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Checkbox(
            value: isSelected,
            onChanged: (_) {},
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}

