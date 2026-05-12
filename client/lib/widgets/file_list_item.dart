import 'package:flutter/material.dart';
import '../models/node.dart';

/// 파일/폴더 목록 아이템 위젯
/// Phase 4: 케밥 버튼, 선택 모드 체크, 롱프레스 진입.
class FileListItem extends StatelessWidget {
  final Node node;

  /// 폴더 탭 시 호출. 파일은 null.
  final VoidCallback? onFolderTap;

  /// 파일 탭 시 호출 (T039: ListTile.onTap 직접 연결용).
  final VoidCallback? onFileTap;

  /// 케밥메뉴 탭 시 호출.
  final VoidCallback? onKebabTap;

  /// 롱프레스 시 호출.
  final VoidCallback? onLongPress;

  /// 선택 모드 탭 시 호출.
  final VoidCallback? onSelectionTap;

  /// 선택 모드 여부.
  final bool isSelectionMode;

  /// 선택 여부.
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
