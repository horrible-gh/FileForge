import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../providers/share_page_provider.dart';
import '../../l10n/app_localizations.dart';

/// D004 §2-3 — public text text text screen.
/// - SharePageProvidertext text translated text text create (text register prohibited — L004 ST-L4-02).
/// - statetext 5text screen branch: loading | password | file | folder | error
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
    final t = AppLocalizations.of(context);
    final state = context.select<SharePageProvider, SharePageState>(
      (p) => p.state,
    );

    return Scaffold(
      appBar: AppBar(title: Text(t.sharedFileTitle)),
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

// ── password text screen ────────────────────────────────────────────────────────

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
    final t = AppLocalizations.of(context);
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
            Text(t.sharePasswordProtected),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: t.commonPassword,
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
                child: Text(t.commonConfirm),
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

// ── file text screen ────────────────────────────────────────────────────────────

class _FileView extends StatelessWidget {
  const _FileView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
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
            // T075: password text translated text text text text display
            if (!provider.isPasswordProtected) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  final url = '${AppConfig.baseUrl}/share/${provider.token}';
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(t.shareLinkCopied)),
                    );
                  }
                },
                icon: const Icon(Icons.link_rounded),
                label: Text(t.shareCopyLink),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: () => _download(context),
              icon: const Icon(Icons.download_rounded),
              label: Text(t.commonDownload),
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

// ── folder text screen ────────────────────────────────────────────────────────────

class _FolderView extends StatelessWidget {
  const _FolderView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final provider = context.watch<SharePageProvider>();
    final breadcrumbs = provider.breadcrumbs;
    final items = provider.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // translated text
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
        // text
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(t.shareFolderEmpty))
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
    final t = AppLocalizations.of(context);
    final isFolder = item.type == 'folder';
    final icon = isFolder
        ? Icons.folder_rounded
        : Icons.insert_drive_file_rounded;

    return ListTile(
      leading: Icon(icon),
      title: Text(item.name),
      trailing: isFolder
          ? const Icon(Icons.chevron_right)
          // T075: file text — password text translated text text text + download text text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isPasswordProtected)
                  IconButton(
                    icon: const Icon(Icons.link_rounded, size: 20),
                    tooltip: t.shareCopyLink,
                    onPressed: () => _copyLink(context),
                  ),
                IconButton(
                  icon: const Icon(Icons.download_rounded, size: 20),
                  tooltip: t.commonDownload,
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
    final t = AppLocalizations.of(context);
    final provider = context.read<SharePageProvider>();
    final url = '${AppConfig.baseUrl}/share/${provider.token}/${item.uuid}';
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.shareLinkCopied)),
      );
    }
  }
}

// ── error screen ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final msg = context.select<SharePageProvider, String?>(
          (p) => p.errorMessage,
        ) ??
        t.shareUnknownError;

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

