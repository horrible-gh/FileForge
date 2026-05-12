import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../providers/share_page_provider.dart';

/// D004 §2-3 — 공개 공유 링크 진입 화면.
/// - SharePageProvider를 위젯 내부에서 직접 생성 (전역 등록 금지 — L004 ST-L4-02).
/// - 상태별 5개 화면 분기: loading | password | file | folder | error
class SharePage extends StatelessWidget {
  final String token;

  const SharePage({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SharePageProvider()..loadMeta(token),
      child: const _SharePageContent(),
    );
  }
}

class _SharePageContent extends StatelessWidget {
  const _SharePageContent();

  @override
  Widget build(BuildContext context) {
    final state = context.select<SharePageProvider, SharePageState>(
      (p) => p.state,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Shared File')),
      body: switch (state) {
        SharePageState.loading => const Center(child: CircularProgressIndicator()),
        SharePageState.password => const _PasswordView(),
        SharePageState.file => const _FileView(),
        SharePageState.folder => const _FolderView(),
        SharePageState.error => const _ErrorView(),
      },
    );
  }
}

// ── 비밀번호 입력 화면 ────────────────────────────────────────────────────────

class _PasswordView extends StatefulWidget {
  const _PasswordView();

  @override
  State<_PasswordView> createState() => _PasswordViewState();
}

class _PasswordViewState extends State<_PasswordView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errorMsg = context.select<SharePageProvider, String?>(
      (p) => p.errorMessage,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, size: 48),
            const SizedBox(height: 16),
            const Text(
              'FileForge',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('This link is password protected'),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                errorText: errorMsg,
              ),
              onSubmitted: (_) => _submit(context),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _submit(context),
                child: const Text('Confirm'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit(BuildContext context) {
    final pw = _controller.text;
    if (pw.isEmpty) return;
    context.read<SharePageProvider>().submitPassword(pw);
  }
}

// ── 파일 공유 화면 ────────────────────────────────────────────────────────────

class _FileView extends StatelessWidget {
  const _FileView();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SharePageProvider>();
    final fileInfo = provider.fileInfo;
    if (fileInfo == null) return const SizedBox.shrink();

    final sizeText = fileInfo.fileSize != null
        ? _formatSize(fileInfo.fileSize!)
        : '';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_rounded, size: 64),
            const SizedBox(height: 16),
            Text(
              fileInfo.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (sizeText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(sizeText, style: const TextStyle(color: Colors.grey)),
            ],
            const SizedBox(height: 24),
            // T075: 비밀번호 없는 공유에서만 링크 복사 버튼 표시
            if (!provider.isPasswordProtected) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  final url = '${AppConfig.baseUrl}/share/${provider.token}';
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  }
                },
                icon: const Icon(Icons.link_rounded),
                label: const Text('Copy Link'),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: () => _download(context),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }

  void _download(BuildContext context) {
    context.read<SharePageProvider>().downloadFile(
      onToast: (msg) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg))),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ── 폴더 공유 화면 ────────────────────────────────────────────────────────────

class _FolderView extends StatelessWidget {
  const _FolderView();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SharePageProvider>();
    final breadcrumbs = provider.breadcrumbs;
    final items = provider.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 빵부스러기
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (int i = 0; i < breadcrumbs.length; i++) ...[
                if (i > 0)
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                GestureDetector(
                  onTap: i < breadcrumbs.length - 1
                      ? () => context
                          .read<SharePageProvider>()
                          .clickBreadcrumb(i)
                      : null,
                  child: Text(
                    breadcrumbs[i],
                    style: TextStyle(
                      fontWeight: i == breadcrumbs.length - 1
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: i < breadcrumbs.length - 1
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        // 목록
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('Folder is empty'))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _FolderItemTile(
                      item: item,
                      isPasswordProtected: provider.isPasswordProtected,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FolderItemTile extends StatelessWidget {
  final ShareItem item;
  final bool isPasswordProtected;

  const _FolderItemTile({
    required this.item,
    required this.isPasswordProtected,
  });

  @override
  Widget build(BuildContext context) {
    final isFolder = item.type == 'folder';
    final icon = isFolder
        ? Icons.folder_rounded
        : Icons.insert_drive_file_rounded;

    return ListTile(
      leading: Icon(icon),
      title: Text(item.name),
      trailing: isFolder
          ? const Icon(Icons.chevron_right)
          // T075: 파일 항목 — 비밀번호 없는 공유는 링크 복사 + 다운로드 병렬 제공
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isPasswordProtected)
                  IconButton(
                    icon: const Icon(Icons.link_rounded, size: 20),
                    tooltip: 'Copy Link',
                    onPressed: () => _copyLink(context),
                  ),
                IconButton(
                  icon: const Icon(Icons.download_rounded, size: 20),
                  tooltip: 'Download',
                  onPressed: () => _download(context),
                ),
              ],
            ),
      onTap: isFolder
          ? () => context.read<SharePageProvider>().navigateFolder(
                item.name,
                onToast: (msg) => ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(msg))),
              )
          : null,
    );
  }

  void _download(BuildContext context) {
    context.read<SharePageProvider>().downloadFile(
      fileUuid: item.uuid,
      onToast: (msg) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg))),
    );
  }

  Future<void> _copyLink(BuildContext context) async {
    final provider = context.read<SharePageProvider>();
    final url = '${AppConfig.baseUrl}/share/${provider.token}/${item.uuid}';
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied')),
      );
    }
  }
}

// ── 에러 화면 ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView();

  @override
  Widget build(BuildContext context) {
    final msg = context.select<SharePageProvider, String?>(
          (p) => p.errorMessage,
        ) ??
        'An unknown error occurred';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

