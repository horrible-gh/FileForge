/// P003 § 1 — 스토리지 정보 모델
class Storage {
  final String storageUuid;
  final String storageName;
  final String? storagePath;
  final String storageType;
  final int? quotaLimit;
  final int? usedSize;
  final bool isDefault;

  const Storage({
    required this.storageUuid,
    required this.storageName,
    this.storagePath,
    this.storageType = 'file',
    this.quotaLimit,
    this.usedSize,
    this.isDefault = false,
  });

  factory Storage.fromJson(Map<String, dynamic> json) {
    return Storage(
      storageUuid: json['storage_uuid'] as String? ?? '',
      storageName: json['storage_name'] as String? ?? '',
      storagePath: json['storage_path'] as String?,
      storageType: json['storage_type'] as String? ?? 'file',
      quotaLimit: json['quota_limit'] as int?,
      usedSize: json['used_size'] as int?,
      isDefault: (json['is_default'] ?? 0) == 1,
    );
  }
}
