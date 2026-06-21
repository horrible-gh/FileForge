import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/storage_provider.dart';
import '../file/file_list_screen.dart';
import '../mail/mail_list_screen.dart';

/// 스토리지 타입 분기 진입점 — NR0003 §1.1.
///
/// CH0002 권고("mail을 file/note의 if-분기에 욱여넣지 말고 전용 모듈로,
/// storage_type은 라우팅 진입점으로만")에 따라, `/:storageUuid` 라우트에서
/// 스토리지 타입을 보고 mail이면 MailListScreen, 아니면 FileListScreen으로
/// 분기한다. FileListScreen 내부를 오염시키지 않는다.
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

    // 타입을 아직 모르면(목록 로딩 중) 스피너. 알 수 없으면 파일 화면으로 폴백.
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
    return FileListScreen(
      storageUuid: widget.storageUuid,
      nodeUuid: widget.nodeUuid,
    );
  }
}
