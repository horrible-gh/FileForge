import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/storage.dart';
import '../providers/storage_provider.dart';

/// 바이트 값을 읽기 쉬운 단위 문자열로 변환
String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  } else if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  } else if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

/// Drawer 내 스토리지 선택 위젯
/// L002 ST-02 Row2: 스토리지 전환 시 파일 목록은 FileProvider가 초기화한다.
class StorageSelector extends StatelessWidget {
  /// 스토리지 선택 후 호출 (FileProvider 초기화 및 루트 이동 처리를 호출부에서 담당)
  final void Function(Storage storage) onStorageSelected;

  const StorageSelector({super.key, required this.onStorageSelected});

  @override
  Widget build(BuildContext context) {
    final storageProvider = context.watch<StorageProvider>();
    final storages = storageProvider.storages;
    final current = storageProvider.currentStorage;

    if (storageProvider.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (storages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('No Storage', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Storage',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
        ),
        ...storages.map((s) {
          final isSelected = current?.storageUuid == s.storageUuid;
          final hasQuota = s.quotaLimit != null;
          final usedBytes = s.usedSize ?? 0;
          final ratio = hasQuota
              ? (usedBytes / s.quotaLimit!).clamp(0.0, 1.0)
              : 0.0;

          return Column(
            children: [
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.storage_rounded,
                  color: isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(
                  s.storageName,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
                subtitle: hasQuota
                    ? Text(
                        '${_formatBytes(usedBytes)} / ${_formatBytes(s.quotaLimit!)}',
                        style: const TextStyle(fontSize: 11),
                      )
                    : null,
                trailing: s.isDefault
                    ? Icon(
                        Icons.star,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                selected: isSelected,
                onTap: () => onStorageSelected(s),
              ),
              if (hasQuota)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 3,
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}
