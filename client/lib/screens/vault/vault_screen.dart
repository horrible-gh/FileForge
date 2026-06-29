import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/vault.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vault_provider.dart';
import '../../widgets/app_toast.dart';

/// SecureBolt vault screen (fileforge.securebolt.0001 / D0004 §6).
///
/// LOCKED → asks for the FileForge login password to derive the master key in
/// memory (the password never leaves the device). UNLOCKED → lists password
/// entries with search + add/edit. Locking wipes the in-memory key.
class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('SecureBolt'),
            if (vault.isLocalMode) ...[
              const SizedBox(width: 8),
              const Chip(
                label: Text('오프라인', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                avatar: Icon(Icons.cloud_off, size: 14),
              ),
            ],
          ],
        ),
        actions: [
          if (vault.isUnlocked) ...[
            if (vault.isSyncing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Sync',
                onPressed: () => vault.refresh(),
              ),
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: 'Lock',
              onPressed: () => vault.lock(),
            ),
          ],
        ],
      ),
      body: vault.isUnlocked
          ? _VaultBody(vault: vault)
          : const _UnlockView(),
      // Hide add while the vault is in a decrypt-failure state — saving would
      // clobber the real (undecryptable) server vault (L0006 §5-B).
      floatingActionButton: (vault.isUnlocked && !vault.hasDecryptError)
          ? FloatingActionButton(
              onPressed: () => _openEditor(context, vault, null),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

Future<void> _openEditor(
  BuildContext context,
  VaultProvider vault,
  VaultPasswordEntry? existing,
) async {
  final entry = await showDialog<VaultPasswordEntry>(
    context: context,
    builder: (_) => _EntryEditorDialog(
      existing: existing,
      categories: vault.categories,
    ),
  );
  if (entry == null || !context.mounted) return;
  final ok = await vault.savePassword(entry);
  if (!context.mounted) return;
  if (ok) {
    AppToast.success(context, '저장되었습니다');
  } else {
    AppToast.error(context, vault.error ?? '저장에 실패했습니다');
  }
}

class _UnlockView extends StatefulWidget {
  const _UnlockView();

  @override
  State<_UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<_UnlockView> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final username = context.read<AuthProvider>().user?.username ?? '';
    if (username.isEmpty || _controller.text.isEmpty) return;
    setState(() => _busy = true);
    final vault = context.read<VaultProvider>();
    await vault.unlock(username, _controller.text);
    _controller.clear();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined, size: 64),
              const SizedBox(height: 16),
              const Text(
                '볼트 잠금 해제',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '로그인 비밀번호로 볼트를 엽니다. 비밀번호는 기기 밖으로 나가지 않습니다.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _unlock,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('잠금 해제'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VaultBody extends StatelessWidget {
  const _VaultBody({required this.vault});

  final VaultProvider vault;

  @override
  Widget build(BuildContext context) {
    final entries = vault.passwords;
    final catById = {for (final c in vault.categories) c.id: c};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '검색',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: vault.setQuery,
          ),
        ),
        if (vault.error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: vault.hasDecryptError
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  vault.hasDecryptError
                      ? Icons.lock_reset
                      : Icons.info_outline,
                  size: 18,
                  color: vault.hasDecryptError
                      ? Theme.of(context).colorScheme.onErrorContainer
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vault.error!,
                    style: TextStyle(
                      color: vault.hasDecryptError
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('저장된 항목이 없습니다'))
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final cat = catById[e.category];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(cat?.icon ?? '🔑'),
                      ),
                      title: Text(e.title),
                      subtitle: Text(e.username,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: '비밀번호 복사',
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: e.password));
                              if (context.mounted) {
                                AppToast.success(context, '비밀번호를 복사했습니다');
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: '삭제',
                            onPressed: () => _confirmDelete(context, vault, e),
                          ),
                        ],
                      ),
                      onTap: () => _openEditor(context, vault, e),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    VaultProvider vault,
    VaultPasswordEntry e,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제'),
        content: Text("'${e.title}' 항목을 삭제할까요?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final done = await vault.deletePassword(e.id);
    if (!context.mounted) return;
    if (done) {
      AppToast.success(context, '삭제되었습니다');
    } else {
      AppToast.error(context, vault.error ?? '삭제에 실패했습니다');
    }
  }
}

class _EntryEditorDialog extends StatefulWidget {
  const _EntryEditorDialog({required this.existing, required this.categories});

  final VaultPasswordEntry? existing;
  final List<VaultCategory> categories;

  @override
  State<_EntryEditorDialog> createState() => _EntryEditorDialogState();
}

class _EntryEditorDialogState extends State<_EntryEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _url;
  late final TextEditingController _notes;
  late String _category;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController(text: e?.password ?? '');
    _url = TextEditingController(text: e?.url ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _category = e?.category ??
        (widget.categories.isNotEmpty ? widget.categories.first.id : 'work');
  }

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _url.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    final base = widget.existing;
    final entry = (base ??
            VaultPasswordEntry(
              id: DateTime.now().millisecondsSinceEpoch,
              title: _title.text.trim(),
            ))
        .copyWith(
      title: _title.text.trim(),
      username: _username.text,
      password: _password.text,
      url: _url.text,
      category: _category,
      notes: _notes.text,
    );
    Navigator.pop(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.categories.isNotEmpty
        ? widget.categories
        : kDefaultVaultCategories;
    return AlertDialog(
      title: Text(widget.existing == null ? '새 항목' : '항목 편집'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_title, '제목'),
            _field(_username, '사용자명'),
            _field(_password, '비밀번호', obscure: true),
            _field(_url, 'URL'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue:
                  cats.any((c) => c.id == _category) ? _category : cats.first.id,
              decoration: const InputDecoration(
                labelText: '분류',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final c in cats)
                  DropdownMenuItem(value: c.id, child: Text('${c.icon} ${c.name}')),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            _field(_notes, '메모'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
