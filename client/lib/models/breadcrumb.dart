/// P003 § 2-3 — 빵부스러기 경로 항목
/// nodeUuid == null 이면 루트.
class Breadcrumb {
  final String? nodeUuid;
  final String name;

  const Breadcrumb({
    this.nodeUuid,
    required this.name,
  });

  factory Breadcrumb.fromJson(Map<String, dynamic> json) {
    return Breadcrumb(
      nodeUuid: json['node_uuid'] as String?,
      name: json['name'] as String? ?? '',
    );
  }
}
