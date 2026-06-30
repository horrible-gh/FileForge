import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/vault.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vault_provider.dart';
import '../../widgets/app_toast.dart';

/// Maps the provider's locale-independent [VaultMessage] code to a localized
/// status/error string (i18n, fileforge.default.0003). [VaultMessage.none]
/// falls back to the provider's raw [VaultProvider.error] (e.g. an unexpected
/// exception or a server-supplied message that has no fixed translation).
String? localizedVaultMessage(AppLocalizations t, VaultProvider vault) {
  switch (vault.messageCode) {
    case VaultMessage.decryptBanner:
      return t.vaultMsgDecryptBanner;
    case VaultMessage.decryptBlockedSave:
      return t.vaultMsgDecryptBlockedSave;
    case VaultMessage.offlineMode:
      return t.vaultMsgOfflineMode;
    case VaultMessage.offlineSaved:
      return t.vaultMsgOfflineSaved;
    case VaultMessage.sessionExpired:
      return t.vaultMsgSessionExpired;
    case VaultMessage.syncFailed:
      return t.vaultMsgSyncFailed;
    case VaultMessage.none:
      return vault.error;
  }
}

/// Localized display name for a vault category. The three default categories
/// have fixed ids ({work, personal, entertainment}, L0006 §1.3) and are
/// translated; custom (user-created) categories keep their stored name.
String vaultCategoryName(AppLocalizations t, VaultCategory c) {
  switch (c.id) {
    case 'work':
      return t.vaultCategoryWork;
    case 'personal':
      return t.vaultCategoryPersonal;
    case 'entertainment':
      return t.vaultCategoryEntertainment;
    default:
      return c.name;
  }
}

/// SecureBolt vault screen (fileforge.securebolt.0001 / D0004 §6).
///
/// LOCKED → asks for the FileForge login password to derive the master key in
/// memory (the password never leaves the device). UNLOCKED → lists password
/// entries with search + add/edit. Locking wipes the in-memory key.
class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final vault = context.watch<VaultProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('SecureBolt'),
            if (vault.isLocalMode) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text(t.vaultOffline, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.cloud_off, size: 14),
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
                tooltip: t.vaultSync,
                onPressed: () => vault.refresh(),
              ),
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: t.vaultLock,
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

/// Embedded SecureBolt vault — the body of a 'password'-type storage rendered
/// inside the MainScreen shell (fileforge.securebolt.0003 / NR0003), mirroring
/// how MailListScreen renders for a 'mail' storage. It has NO AppBar of its own
/// (the shell AppBar shows the storage name); a transparent Scaffold supplies
/// the [+] FAB, and an inline toolbar carries the lock/sync/offline actions the
/// standalone [VaultScreen] keeps in its AppBar. All the heavy lifting reuses
/// the same private widgets ([_VaultBody], [_UnlockView], [_openEditor]).
class VaultStorageView extends StatelessWidget {
  const VaultStorageView({super.key});

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Hide add while in a decrypt-failure state — saving would clobber the
      // real (undecryptable) server vault (L0006 §5-B).
      floatingActionButton: (vault.isUnlocked && !vault.hasDecryptError)
          ? FloatingActionButton(
              onPressed: () => _openEditor(context, vault, null),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          if (vault.isUnlocked) _VaultToolbar(vault: vault),
          Expanded(
            child:
                vault.isUnlocked ? _VaultBody(vault: vault) : const _UnlockView(),
          ),
        ],
      ),
    );
  }
}

/// Inline lock/sync/offline toolbar for the embedded vault (the standalone
/// [VaultScreen] keeps these in its AppBar; the embedded view has none).
class _VaultToolbar extends StatelessWidget {
  const _VaultToolbar({required this.vault});

  final VaultProvider vault;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, size: 18),
          const SizedBox(width: 6),
          const Text('SecureBolt',
              style: TextStyle(fontWeight: FontWeight.bold)),
          if (vault.isLocalMode) ...[
            const SizedBox(width: 8),
            Chip(
              label: Text(t.vaultOffline, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.cloud_off, size: 14),
            ),
          ],
          const Spacer(),
          if (vault.isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: t.vaultSync,
              onPressed: () => vault.refresh(),
            ),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: t.vaultLock,
            onPressed: () => vault.lock(),
          ),
        ],
      ),
    );
  }
}

Future<void> _openEditor(
  BuildContext context,
  VaultProvider vault,
  VaultPasswordEntry? existing,
) async {
  final t = AppLocalizations.of(context);
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
    AppToast.success(context, t.vaultSaved);
  } else {
    AppToast.error(context, localizedVaultMessage(t, vault) ?? t.vaultSaveFailed);
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
    final t = AppLocalizations.of(context);
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
              Text(
                t.vaultUnlockTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                t.vaultUnlockDesc,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t.commonPassword,
                  border: const OutlineInputBorder(),
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
                      : Text(t.vaultUnlock),
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
    final t = AppLocalizations.of(context);
    final entries = vault.passwords;
    final catById = {for (final c in vault.categories) c.id: c};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: t.commonSearch,
              border: const OutlineInputBorder(),
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
                    localizedVaultMessage(t, vault) ?? '',
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
              ? Center(child: Text(t.vaultEmpty))
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
                            tooltip: t.vaultCopyPassword,
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: e.password));
                              if (context.mounted) {
                                AppToast.success(context, t.vaultPasswordCopied);
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: t.commonDelete,
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
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.commonDelete),
        content: Text(t.vaultDeleteConfirm(e.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final done = await vault.deletePassword(e.id);
    if (!context.mounted) return;
    if (done) {
      AppToast.success(context, t.vaultDeleted);
    } else {
      AppToast.error(
          context, localizedVaultMessage(t, vault) ?? t.vaultDeleteFailed);
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
    final t = AppLocalizations.of(context);
    final cats = widget.categories.isNotEmpty
        ? widget.categories
        : kDefaultVaultCategories;
    return AlertDialog(
      title: Text(widget.existing == null ? t.vaultEntryNew : t.vaultEntryEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(_title, t.vaultFieldTitle),
            _field(_username, t.commonUsername),
            _field(_password, t.commonPassword, obscure: true),
            _field(_url, 'URL'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue:
                  cats.any((c) => c.id == _category) ? _category : cats.first.id,
              decoration: InputDecoration(
                labelText: t.vaultFieldCategory,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final c in cats)
                  DropdownMenuItem(
                      value: c.id,
                      child: Text('${c.icon} ${vaultCategoryName(t, c)}')),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            _field(_notes, t.vaultFieldNotes),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(t.commonSave)),
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
