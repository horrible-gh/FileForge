/// P003 § 2-3 — 파일/폴더 노드 모델
/// type: 'file' | 'folder'
/// parentUuid: 폴더 트리에서 사용 (get_directory_trees 응답)
class Node {
  final String? nodeUuid;
  final String name;
  final String type;
  final String? preview;
  final String? parentUuid;
  final DateTime? modifiedAt;

  const Node({
    this.nodeUuid,
    required this.name,
    required this.type,
    this.preview,
    this.parentUuid,
    this.modifiedAt,
  });

  bool get isFolder => type == 'folder';
  bool get isFile => type == 'file';

  factory Node.fromJson(Map<String, dynamic> json) {
    return Node(
      nodeUuid: json['node_uuid'] as String?,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'file',
      preview: json['preview'] as String?,
      parentUuid: json['parent_uuid'] as String?,
      modifiedAt: json['modified_at'] != null ? DateTime.tryParse(json['modified_at']) : null,
    );
  }

  /// 루트 노드 표현. node_uuid == null.
  factory Node.root() => const Node(nodeUuid: null, name: 'Root', type: 'folder');
}
