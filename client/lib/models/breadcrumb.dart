/// P003 § 2-3 — translated text path text
/// nodeUuid == null text text.
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
