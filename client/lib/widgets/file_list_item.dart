import 'package:flutter/material.dart';
import '../models/node.dart';

/// file/folder text translated text text
/// Phase 4: text text, selection text text, translated text text.
class FileListItem extends StatelessWidget {
  final Node node;

  /// folder text text text. filetext null.
  final VoidCallback? onFolderTap;

  /// file text text text (T039: ListTile.onTap text translated text).
  final VoidCallback? onFileTap;

  /// translated text text text text.
  final VoidCallback? onKebabTap;

  /// translated text text text.
  final VoidCallback? onLongPress;

  /// selection text text text text.
  final VoidCallback? onSelectionTap;

  /// selection text text.
  final bool isSelectionMode;

  /// selection text.
  final bool isSelected;

  const FileListItem({
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
    return ListTile(
      leading: isSelectionMode ? _buildCheckbox(context) : _buildIcon(context),
      title: Text(
        node.name,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: node.isFile && node.preview != null && node.preview!.isNotEmpty
          ? Text(
              node.preview!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            )
          : null,
      trailing: isSelectionMode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onKebabTap != null)
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onPressed: onKebabTap,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (node.isFolder && !isSelectionMode)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.chevron_right, size: 18),
                  ),
              ],
            ),
      onTap: isSelectionMode
          ? onSelectionTap
          : (node.isFolder ? onFolderTap : onFileTap),
      onLongPress: onLongPress,
    );
  }

  Widget _buildCheckbox(BuildContext context) {
    return Icon(
      isSelected ? Icons.check_box : Icons.check_box_outline_blank,
      color: isSelected ? Theme.of(context).colorScheme.primary : null,
    );
  }

  Widget _buildIcon(BuildContext context) {
    if (node.isFolder) {
      return Icon(Icons.folder_rounded, color: Colors.amber.shade700, size: 36);
    }
    return Icon(
      _fileIcon(node.name),
      color: Theme.of(context).colorScheme.secondary,
      size: 36,
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
