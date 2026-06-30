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
            if (!vault.hasDecryptError)
              IconButton(
                icon: const Icon(Icons.folder_outlined),
                tooltip: t.vaultManageCategories,
                onPressed: () => _openCategoryManager(context, vault),
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
          if (!vault.hasDecryptError)
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: t.vaultManageCategories,
              onPressed: () => _openCategoryManager(context, vault),
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
        _CategoryFilterBar(vault: vault),
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

// ── Category-based viewing + management (R0001 / NR0003) ────────────────────

/// Curated emoji/color palettes for custom categories (legacy SecureBolt
/// parity — `js/managers/categoryManager.js` predefined sets).
const List<String> kVaultCategoryIcons = [
  '📁', '💼', '👤', '🎮', '🏦', '🛒', '✉️', '🌐',
  '🔐', '⚙️', '📱', '🎵', '📷', '🎬', '✈️', '🏠',
];
const List<String> kVaultCategoryColors = [
  '#667eea', '#48bb78', '#ed8936', '#e53e3e',
  '#38b2ac', '#9f7aea', '#ed64a6', '#718096',
];

/// Parse a `#RRGGBB` (or `#AARRGGBB`) hex color, falling back on bad input.
Color vaultParseHexColor(String hex, Color fallback) {
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Horizontal category filter chips with live count badges: "전체 (N)" plus one
/// chip per category. Tapping scopes the list to that category (R0001:
/// "분류별로도 볼 수 있게"). Replaces the legacy sidebar navigator.
class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({required this.vault});

  final VaultProvider vault;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final counts = vault.categoryCounts;
    final selected = vault.categoryFilter;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                  '${t.vaultCategoryAll} (${counts[VaultProvider.allCategoryFilter] ?? 0})'),
              selected: selected == VaultProvider.allCategoryFilter,
              onSelected: (_) =>
                  vault.setCategoryFilter(VaultProvider.allCategoryFilter),
            ),
          ),
          for (final c in vault.categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Text(c.icon),
                label: Text(
                    '${vaultCategoryName(t, c)} (${counts[c.id] ?? 0})'),
                selected: selected == c.id,
                onSelected: (_) => vault.setCategoryFilter(c.id),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _openCategoryManager(
    BuildContext context, VaultProvider vault) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _CategoryManagerDialog(vault: vault),
  );
}

/// Lists categories with per-category counts. Default categories are locked
/// (shown with a lock badge); custom categories can be edited or deleted.
/// "Add" opens the [_CategoryEditorDialog]. Watches the provider so it reflects
/// add/rename/delete immediately.
class _CategoryManagerDialog extends StatelessWidget {
  const _CategoryManagerDialog({required this.vault});

  final VaultProvider vault;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final v = context.watch<VaultProvider>();
    final cats = v.categories;
    final counts = v.categoryCounts;
    return AlertDialog(
      title: Text(t.vaultManageCategories),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: cats.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final c = cats[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: vaultParseHexColor(
                          c.color, Theme.of(context).colorScheme.primary),
                      child: Text(c.icon,
                          style: const TextStyle(fontSize: 14)),
                    ),
                    title: Text(vaultCategoryName(t, c)),
                    subtitle: Text('${counts[c.id] ?? 0}'),
                    trailing: c.isDefault
                        ? Tooltip(
                            message: t.vaultCategoryDefaultLocked,
                            child: const Icon(Icons.lock_outline, size: 16),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                tooltip: t.vaultCategoryEdit,
                                onPressed: () =>
                                    _openCategoryEditor(context, vault, c),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete_outline, size: 18),
                                tooltip: t.commonDelete,
                                onPressed: () =>
                                    _confirmDeleteCategory(context, vault, c),
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _openCategoryEditor(context, vault, null),
          icon: const Icon(Icons.add),
          label: Text(t.vaultCategoryNew),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.commonClose),
        ),
      ],
    );
  }
}

Future<void> _confirmDeleteCategory(
  BuildContext context,
  VaultProvider vault,
  VaultCategory c,
) async {
  final t = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(t.commonDelete),
      content: Text(t.vaultCategoryDeleteConfirm(vaultCategoryName(t, c))),
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
  if (ok != true) return;
  final done = await vault.deleteCategory(c.id);
  if (!context.mounted) return;
  if (done) {
    AppToast.success(context, t.vaultCategoryDeleted);
  } else {
    AppToast.error(
        context, localizedVaultMessage(t, vault) ?? t.vaultCategoryActionFailed);
  }
}

Future<void> _openCategoryEditor(
  BuildContext context,
  VaultProvider vault,
  VaultCategory? existing,
) async {
  final t = AppLocalizations.of(context);
  final result = await showDialog<VaultCategory>(
    context: context,
    builder: (_) => _CategoryEditorDialog(existing: existing),
  );
  if (result == null || !context.mounted) return;
  final isEdit = existing != null;
  final done = isEdit
      ? await vault.updateCategory(result)
      : await vault.addCategory(result);
  if (!context.mounted) return;
  if (done) {
    AppToast.success(
        context, isEdit ? t.vaultCategoryUpdated : t.vaultCategoryAdded);
  } else {
    AppToast.error(
        context, localizedVaultMessage(t, vault) ?? t.vaultCategoryActionFailed);
  }
}

/// Add/edit a custom category: name + emoji picker + color picker + live
/// preview (legacy SecureBolt "카테고리 관리 모달" parity). Returns a built
/// [VaultCategory] (a new `cat_<ts>` id when adding; the existing id when
/// editing, so entry references stay valid).
class _CategoryEditorDialog extends StatefulWidget {
  const _CategoryEditorDialog({required this.existing});

  final VaultCategory? existing;

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final TextEditingController _name;
  late String _icon;
  late String _color;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _icon = e?.icon ?? kVaultCategoryIcons.first;
    _color = e?.color ?? kVaultCategoryColors.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final existing = widget.existing;
    final id = existing?.id ??
        'cat_${DateTime.now().millisecondsSinceEpoch}';
    Navigator.pop(
      context,
      VaultCategory(
        id: id,
        name: name,
        icon: _icon,
        color: _color,
        isDefault: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final previewName =
        _name.text.trim().isEmpty ? t.vaultCategoryNew : _name.text.trim();
    return AlertDialog(
      title: Text(
          widget.existing == null ? t.vaultCategoryNew : t.vaultCategoryEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live preview chip.
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Chip(
                avatar: Text(_icon),
                label: Text(previewName),
                backgroundColor:
                    vaultParseHexColor(_color, Theme.of(context).colorScheme.surface)
                        .withValues(alpha: 0.25),
              ),
            ),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 20,
              decoration: InputDecoration(
                labelText: t.vaultCategoryName,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Text(t.vaultCategoryIcon,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final icon in kVaultCategoryIcons)
                  InkWell(
                    onTap: () => setState(() => _icon = icon),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _icon == icon
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).dividerColor,
                          width: _icon == icon ? 2 : 1,
                        ),
                      ),
                      child: Text(icon, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(t.vaultCategoryColor,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in kVaultCategoryColors)
                  InkWell(
                    onTap: () => setState(() => _color = color),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: vaultParseHexColor(color, Colors.grey),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == color
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: _color == color
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
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
}
