import 'package:flutter/material.dart';
import '../models/node.dart';

/// Drawer 내 계층형 폴더 트리 위젯
/// L002 ST-02 Row10: 서버 get_directory_trees 응답은 폴더만 포함하므로 필터 없이 사용.
/// parent_uuid 기준으로 트리를 구성한다.
class FolderTreeView extends StatelessWidget {
  final List<Node> nodes;
  final String? currentNodeUuid;

  /// 폴더 탭 시 호출. 해당 폴더의 nodeUuid를 전달.
  final void Function(Node node) onFolderTapped;

  const FolderTreeView({
    super.key,
    required this.nodes,
    this.currentNodeUuid,
    required this.onFolderTapped,
  });

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();

    // 루트 노드(parentUuid == null)부터 렌더링
    final rootNodes = nodes.where((n) => n.parentUuid == null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rootNodes
          .map((n) => _FolderTreeNode(
                node: n,
                allNodes: nodes,
                depth: 0,
                currentNodeUuid: currentNodeUuid,
                onFolderTapped: onFolderTapped,
              ))
          .toList(),
    );
  }
}

class _FolderTreeNode extends StatefulWidget {
  final Node node;
  final List<Node> allNodes;
  final int depth;
  final String? currentNodeUuid;
  final void Function(Node node) onFolderTapped;

  const _FolderTreeNode({
    required this.node,
    required this.allNodes,
    required this.depth,
    this.currentNodeUuid,
    required this.onFolderTapped,
  });

  @override
  State<_FolderTreeNode> createState() => _FolderTreeNodeState();
}

class _FolderTreeNodeState extends State<_FolderTreeNode> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final children = widget.allNodes
        .where((n) => n.parentUuid == widget.node.nodeUuid)
        .toList();
    final isSelected = widget.currentNodeUuid == widget.node.nodeUuid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: 16.0 + widget.depth * 16.0,
            top: 4,
            bottom: 4,
            right: 8,
          ),
          child: Row(
            children: [
              if (children.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: Icon(
                        _expanded ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(width: 32),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  onTap: () => widget.onFolderTapped(widget.node),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_rounded,
                        size: 18,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.amber.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.node.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_expanded)
          ...children.map(
            (child) => _FolderTreeNode(
              node: child,
              allNodes: widget.allNodes,
              depth: widget.depth + 1,
              currentNodeUuid: widget.currentNodeUuid,
              onFolderTapped: widget.onFolderTapped,
            ),
          ),
      ],
    );
  }
}
