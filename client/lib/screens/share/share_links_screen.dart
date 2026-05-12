import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/share_link_provider.dart';
import '../../models/share_link.dart';
import '../../config/env.dart';
import '../../widgets/app_toast.dart';

/// D004 §2-2 — 공유 링크 목록 화면
/// - 진입 시 ShareLinkProvider.fetchList() 호출
/// - 로딩 / 빈 상태 / 목록 상태 분기
/// - 각 항목: nodeType 아이콘, nodeName, createdAt, hasPassword 자물쇠,
///   복사 버튼(2초 피드백), 삭제 버튼(확인 다이얼로그)
class ShareLinksScreen extends StatefulWidget {
  const ShareLinksScreen({super.key});

  @override
  State<ShareLinksScreen> createState() => _ShareLinksScreenState();
}

class _ShareLinksScreenState extends State<ShareLinksScreen> {
  // 항목 단위 복사 피드백을 위한 token 추적
  String? _copiedToken;

  @override
  void initState() {
    super.initState();
    // 화면 진입 시 목록 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ShareLinkProvider>().fetchList();
    });
  }

  /// P005 §1 기준: Env.shareBaseUrl에 /share/{token} 조합
  String _buildShareUrl(String token) {
    return '${Env.shareBaseUrl}/share/$token';
  }

  Future<void> _copyLink(ShareLink link) async {
    final url = _buildShareUrl(link.token);
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copiedToken = link.token);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _copiedToken = null);
  }

  Future<void> _deleteLink(ShareLink link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Share Link'),
        content: Text('Delete link for ${link.nodeName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final provider = context.read<ShareLinkProvider>();
    await provider.deleteLink(link.token);
    if (!mounted) return;
    if (provider.error != null) {
      AppToast.error(context, 'Failed to delete link');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShareLinkProvider>();
    return _buildBody(provider);
  }

  Widget _buildBody(ShareLinkProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null && provider.links.isEmpty) {
      return Center(child: Text(provider.error!));
    }
    if (provider.links.isEmpty) {
      return const Center(child: Text('No shared links'));
    }
    return ListView.separated(
      itemCount: provider.links.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final link = provider.links[index];
        return _ShareLinkTile(
          link: link,
          isCopied: _copiedToken == link.token,
          onCopy: () => _copyLink(link),
          onDelete: () => _deleteLink(link),
        );
      },
    );
  }
}

class _ShareLinkTile extends StatelessWidget {
  final ShareLink link;
  final bool isCopied;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _ShareLinkTile({
    required this.link,
    required this.isCopied,
    required this.onCopy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final icon = link.nodeType == 'folder'
        ? Icons.folder_rounded
        : Icons.insert_drive_file_rounded;

    return ListTile(
      leading: Icon(icon),
      title: Row(
        children: [
          Expanded(
            child: Text(
              link.nodeName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (link.hasPassword)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.lock_rounded, size: 14),
            ),
        ],
      ),
      subtitle: Text(link.createdAt),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              isCopied ? Icons.check_rounded : Icons.copy_rounded,
              size: 20,
            ),
            tooltip: 'Copy',
            onPressed: onCopy,
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, size: 20),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

