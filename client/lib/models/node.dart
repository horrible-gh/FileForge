/// P003 § 2-3 — file/folder text text
/// type: 'file' | 'folder'
/// parentUuid: folder translated text text (get_directory_trees text)
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

  /// text text text. node_uuid == null.
  factory Node.root() => const Node(nodeUuid: null, name: 'Root', type: 'folder');
}
