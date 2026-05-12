import 'package:flutter/material.dart';
import '../models/node.dart';

/// 그리드 뷰용 파일/폴더 셀 위젯 (T052, T054)
/// 구조: Card(clipBehavior) → InkWell → Padding → Column (NoteCard 패턴)
class FileGridItem extends StatelessWidget {
  final Node node;

  /// 폴더 탭 시 호출. 파일은 null.
  final VoidCallback? onFolderTap;

  /// 파일 탭 시 호출.
  final VoidCallback? onFileTap;

  /// 케밥 메뉴 탭 시 호출.
  final VoidCallback? onKebabTap;

  /// 롱프레스 시 호출.
  final VoidCallback? onLongPress;

  /// 선택 모드 탭 시 호출.
  final VoidCallback? onSelectionTap;

  /// 선택 모드 여부.
  final bool isSelectionMode;

  /// 선택 여부.
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
            // ── 메인 콘텐츠 ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 아이콘 (선택 모드일 때 체크박스로 교체)
                  if (isSelectionMode)
                    _SelectionCheckbox(isSelected: isSelected)
                  else
                    _buildIcon(context),
                  const SizedBox(height: 6),
                  // 파일명 — 최대 2줄 ellipsis
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
            // ── 케밥 버튼 (오른쪽 상단, 비선택 모드) ─────────────────
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

/// NoteCard._SelectionCheckbox 패턴과 동일한 체크박스 위젯 (T054)
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

