import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/storage.dart';
import '../providers/storage_provider.dart';

/// bytes text text text text stringtext convert
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

/// Per-type leading glyph so a mail box / SecureBolt vault is visually distinct
/// from a plain file storage in the switcher (NR0004 §3 — previously every type
/// shared `storage_rounded`, erasing the distinction). All `_rounded` to match
/// the house style.
IconData _storageTypeIcon(String storageType) {
  switch (storageType) {
    case 'mail':
      return Icons.mark_email_unread_rounded;
    case 'password':
      return Icons.lock_rounded;
    case 'file':
    default:
      return Icons.storage_rounded;
  }
}

/// Drawer text storage selection text
/// L002 ST-02 Row2: storage text text file translated text FileProvidertext initializetext.
class StorageSelector extends StatelessWidget {
  /// storage selection text text (FileProvider initialize text text navigate translated text translated text text)
  final void Function(Storage storage) onStorageSelected;

  const StorageSelector({super.key, required this.onStorageSelected});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
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
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(t.storageNone, style: const TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            t.storageSectionLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
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
                  _storageTypeIcon(s.storageType),
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
                        Icons.star_rounded,
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
