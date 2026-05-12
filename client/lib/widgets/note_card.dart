import 'package:flutter/material.dart';
import '../models/node.dart';

/// 파일 이름에서 확장자를 제거한 노트 제목을 반환한다.
/// 이름이 점으로 시작하거나 확장자가 없으면 원본을 반환한다.
String getNoteName(String name) {
  final lastDot = name.lastIndexOf('.');
  return lastDot > 0 ? name.substring(0, lastDot) : name;
}

/// [T043] modifiedAt 기반 상대 시간 문자열 반환.
/// null 이면 빈 문자열 반환.
String formatRelativeDate(DateTime? modifiedAt) {
  if (modifiedAt == null) return '';
  final diff = DateTime.now().difference(modifiedAt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  return '${modifiedAt.month}/${modifiedAt.day}';
}

/// note 스토리지 전용 카드 위젯.
/// - type=file: 제목/preview/날짜 + 케밥(비선택모드) or 체크박스(선택모드)
/// - type=folder: 폴더 아이콘/폴더명/날짜 + 체크박스(선택모드)
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
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더: 제목 + 케밥(비선택모드) or 체크박스(선택모드)
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
        // 본문: preview 최대 3줄
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
        // 푸터: 상대 시간
        Text(
          formatRelativeDate(node.modifiedAt),
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildFolderContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더: 폴더 아이콘 + 폴더명 + 체크박스(선택모드)
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
        // 본문 없음
        const Spacer(),
        // 푸터: 수정일
        Text(
          formatRelativeDate(node.modifiedAt),
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
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        if (value == 'rename') onRename?.call();
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}
