/// D004 Phase 5 — text text text
class ShareLink {
  final String token;
  final String nodeUuid;
  final String nodeType;
  final String nodeName;
  final String createdAt;
  final bool hasPassword;

  const ShareLink({
    required this.token,
    required this.nodeUuid,
    required this.nodeType,
    required this.nodeName,
    required this.createdAt,
    required this.hasPassword,
  });

  factory ShareLink.fromJson(Map<String, dynamic> json) {
    return ShareLink(
      token: json['token'] as String? ?? '',
      nodeUuid: json['node_uuid'] as String? ?? '',
      nodeType: json['node_type'] as String? ?? '',
      nodeName: json['node_name'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      hasPassword: json['has_password'] as bool? ?? false,
    );
  }
}
