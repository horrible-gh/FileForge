import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/storage_provider.dart';
import '../file/file_list_screen.dart';
import '../mail/mail_list_screen.dart';
import '../vault/vault_screen.dart';

/// storage text branch translated text — NR0003 §1.1.
///
/// CH0002 text("mailtext file/notetext if-branchtext translated text text text translated text,
/// storage_typetext translated text translated text")text text, `/:storageUuid` translated text
/// storage translated text text mailtext MailListScreen, translated text FileListScreentext
/// branchtext. FileListScreen translated text translated text translated text.
class StorageDispatcher extends StatefulWidget {
  final String storageUuid;
  final String? nodeUuid;

  const StorageDispatcher({
    super.key,
    required this.storageUuid,
    this.nodeUuid,
  });

  @override
  State<StorageDispatcher> createState() => _StorageDispatcherState();
}

class _StorageDispatcherState extends State<StorageDispatcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureStorages());
  }

  Future<void> _ensureStorages() async {
    final storageProvider = context.read<StorageProvider>();
    if (storageProvider.storages.isEmpty && !storageProvider.isLoading) {
      final userUuid = context.read<AuthProvider>().user?.userUuid ?? '';
      await storageProvider.loadStorages(userUuid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storageProvider = context.watch<StorageProvider>();
    final matches = storageProvider.storages
        .where((s) => s.storageUuid == widget.storageUuid);
    final target = matches.isEmpty ? null : matches.first;

    // translated text text translated text(text loading text) translated text. text text translated text file screentext text.
    if (target == null) {
      if (storageProvider.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return FileListScreen(
        storageUuid: widget.storageUuid,
        nodeUuid: widget.nodeUuid,
      );
    }

    if (target.storageType == 'mail') {
      return MailListScreen(storageUuid: widget.storageUuid);
    }
    // SecureBolt is a 'password'-type storage (fileforge.securebolt.0003 /
    // NR0003): open it like any other storage and render the vault inline.
    if (target.storageType == 'password') {
      return const VaultStorageView();
    }
    return FileListScreen(
      storageUuid: widget.storageUuid,
      nodeUuid: widget.nodeUuid,
    );
  }
}
