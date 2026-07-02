import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/mail_provider.dart';
import '../../providers/account_provider.dart';
import '../../services/mail_service.dart' show SyncAccountError;
import '../../models/mail.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/app_toast.dart';
import '../../services/mail_compose.dart';
import 'mail_detail_screen.dart';
import 'mail_compose_screen.dart';
import 'account_connect_screen.dart';

/// text translated text translated text translated text text(text translated text text).
///
/// 'drafts' text [MailProvider] text Draft text text(`_isDraftsLabel`)text translated text,
/// text translated text text text text text text translated text translated text translated text translated text text.
const List<String> kMailSystemLabels = ['inbox', 'drafts', 'sent'];

/// translated text translated text translated text display name.
String mailLabelName(AppLocalizations t, String label) => switch (label) {
      'draft' || 'drafts' => t.labelDrafts,
      'sent' => t.labelSent,
      _ => t.labelInbox,
    };

/// text text screen — NR0003 §7 initial implementation(text translated text).
///
/// MainScreen(ShellRoute) Bodytext displaytext. storage translated text 'mail'text text
/// StorageDispatchertext FileListScreen text text screentext translated text.
/// text text → text screen(text screen push). translated text text text text text text text.
class MailListScreen extends StatefulWidget {
  final String? storageUuid;

  const MailListScreen({super.key, this.storageUuid});

  @override
  State<MailListScreen> createState() => _MailListScreenState();
}

class _MailListScreenState extends State<MailListScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();

  /// R0001(0027) — expanded/collapsed state of the "ピン留め(pinned)" tray. It can
  /// be collapsed so it takes no space even with many pins, and defaults to
  /// expanded. If there are no pinned mails at all, the tray is not rendered.
  bool _pinnedTrayExpanded = true;

  /// B0001(0037) — signature of the per-account sync errors the user already
  /// dismissed. The 10s auto-poll keeps re-reporting a persistent failure; once
  /// dismissed we hide it for the *same* set, but a new/different failure (a
  /// different account or message) changes the signature and re-shows the banner.
  String? _dismissedSyncErrorSig;

  /// R0001(0022) realtime receive — while the inbox is on screen, periodically
  /// pull a server sync (POST /sync) to auto-reflect externally arriving mail.
  /// NR0003 direction A: server unchanged (the absence of a background worker is
  /// compensated by client polling).
  ///
  /// Interval = 10s (T0007, shortened from the previous 15s). Rationale for "is
  /// the load heavy?": a poll with no new mail has IMAP SEARCH return an empty
  /// result and finish immediately, so there is **no body download at all**
  /// (sync.go doSyncLocked: if 0 changes to apply it ends at the first
  /// FetchChanges page). So the real cost of one empty poll is just a single
  /// TLS+IMAP login round-trip and traffic is under a few tens of KB. Moreover
  /// polling (a) runs only when the inbox is the **foreground top route** (stops
  /// on compose/detail push and when the app is backgrounded), (b) is idempotently
  /// blocked against duplicate concurrent syncs by the server `acquireSyncLock`
  /// (sync.go:53), and (c) opens one connection serially at a time and closes it
  /// immediately so concurrent connections do not accumulate. 10s = 6 times per
  /// minute on an active screen for one account, a temporary receive supplement
  /// that runs only while the inbox is in the foreground. Going lower (e.g. <10s)
  /// makes the per-poll TLS reconnect overhead dominant, requiring connection
  /// reuse / IMAP IDLE (direction C).
  static const Duration _pollInterval = Duration(seconds: 10);
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _enterMail());
    _startPolling();
  }

  // ── periodic polling (realtime receive) ───────────────────────────────────
  //
  // ★T0004 constraint (must obey): "while composing a mail, a refresh must not
  // disturb the composition." This is guaranteed in two layers.
  //   (1) If a compose/detail screen is pushed over the inbox (= this route is not
  //       the top), the polling tick does nothing (_pollTick's isCurrent guard).
  //   (2) Even if the tick runs, the sync only updates the inbox *list* state, and
  //       MailComposeScreen uses only its own local state (TextEditingController,
  //       etc.) and does not watch MailProvider, so the body being typed never
  //       disappears.

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollTick());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// One periodic sync. Skips if another screen (compose/detail, etc.) is on top,
  /// if there are no accounts, if the label is not the inbox, or if a sync/load
  /// is already in progress.
  void _pollTick() {
    if (!mounted) return;
    // (1) Do not disturb mail composition — never sync unless the inbox is the top route.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (!context.read<AccountProvider>().hasAccounts) return;
    final mail = context.read<MailProvider>();
    // Auto-receive only on the inbox. Sent/drafts are not receive targets.
    if (mail.currentLabel != 'inbox') return;
    // While searching, skip so the auto-sync does not overwrite search results (B0001/0026).
    // Because syncInbox→loadInbox clears the query and reloads the full list.
    if (mail.isSearchMode) return;
    // R0001/0039 — also skip while a scroll load-more is in flight: otherwise the
    // poll's sync+reload would discard the fetched page (stale _loadSeq) and snap the
    // list back to page 1, which is exactly the "scroll refresh takes forever / gets
    // a few items" symptom. loadMore already blocks on _isLoading; this makes the
    // guard symmetric so a running load-more also blocks the poll.
    if (mail.isSyncing || mail.isLoading || mail.isLoadingMore) return;
    // Quiet background refresh: merges new mail into the head without clearing the
    // loaded pages or resetting the scroll position (see MailProvider.syncInbox).
    mail.syncInbox(quiet: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // In the background, stop polling (save network/battery); on foreground resume,
    // sync once immediately then restart polling — so it isn't a step behind right after resuming.
    switch (state) {
      case AppLifecycleState.resumed:
        _startPolling();
        _pollTick();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _stopPolling();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// text text translated text(NR0003 §5.5) — inbox text text text translated text accounttext translated text
  /// text translated text. accounttext 0text inbox text translated text text(translated text text "error+Retry"
  /// text text) translated text screentext translated text. 1text and abovetext text loadInbox text.
  Future<void> _enterMail() async {
    final accounts = context.read<AccountProvider>();
    // translated text text(TR0005 §symptom1): translated text translated text account translated text screentext text translated text.
    // translated text accounttext translated text translated text text translated text inbox text textloadingtext.
    final primed = await accounts.primeFromCache();
    if (!mounted) return;
    if (primed && accounts.hasAccounts) {
      // R0001: on entering the inbox, pull a server sync (POST /sync) first, then reload.
      // Without this trigger, received mail never makes it into local storage (inside
      // syncInbox a sync failure is ignored best-effort and the local list is shown).
      context.read<MailProvider>().syncInbox();
    }
    // translated text translated text(text ready text translated text translated text text).
    await accounts.load();
    if (!mounted) return;
    final mail = context.read<MailProvider>();
    if (accounts.hasAccounts && mail.mails.isEmpty) {
      mail.syncInbox();
    }
  }

  /// account text screentext navigate. translated text text accounttext translated text inbox text translated text
  /// (AccountConnectScreen text text AccountProvider text refreshtranslated text text translated text).
  Future<void> _openAccounts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountConnectScreen()),
    );
    if (!mounted) return;
    final mail = context.read<MailProvider>();
    if (context.read<AccountProvider>().hasAccounts && mail.mails.isEmpty) {
      // An account was just connected/reconnected, so pull the inbox via sync (R0001).
      mail.syncInbox();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      context.read<MailProvider>().loadMore();
    }
  }

  /// Draft text(translated text) text — Draft text text translated text translated text translated text text.
  static bool _isDraftsLabel(String label) =>
      label == 'draft' || label == 'drafts';

  void _openMail(MailSummary m) {
    if (_isDraftsLabel(context.read<MailProvider>().currentLabel)) {
      _openDraft(m);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MailDetailScreen(mailId: m.mailId, subject: m.subject),
      ),
    );
  }

  /// Draft translated text(§7.9) — Drafttext translated text compose screentext text. text text text refresh.
  Future<void> _openDraft(MailSummary m) async {
    final provider = context.read<MailProvider>();
    final draft = await provider.loadDraft(m.mailId);
    if (!mounted) return;
    if (draft == null) {
      AppToast.error(context, AppLocalizations.of(context).draftLoadFailed);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MailComposeScreen(draft: draft),
      ),
    );
    if (mounted) provider.refresh();
  }

  Future<void> _compose() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const MailComposeScreen(mode: ComposeMode.newMail),
      ),
    );
    if (sent == true && mounted) {
      context.read<MailProvider>().refresh();
    }
  }

  /// R0001(0030) — mark every unread mail as read. Relocated from the shared shell
  /// AppBar into the mail tray (CH0007/NR0009). Delegates to MailProvider (which
  /// persists via the server then clears the unread cue locally), then reports the
  /// count; the server-side persistence means the 10s inbox poll will not revert it.
  Future<void> _markAllRead() async {
    final t = AppLocalizations.of(context);
    final updated = await context.read<MailProvider>().markAllRead();
    if (!mounted) return;
    if (updated < 0) {
      AppToast.error(context, t.mailMarkAllReadFailed);
    } else {
      AppToast.success(context, t.mailMarkedAllRead(updated));
    }
  }

  /// R0001(0042) — manual sync button (placed in the tray between mark-all-read
  /// and account-connect). The title "리프레시는 어디서..." asked for a discoverable
  /// refresh action: the sync behaviour itself already exists (pull-to-refresh and
  /// the 10s poll both call syncInbox), so this just gives it an explicit affordance
  /// in the toolbar. Delegates to [MailProvider.syncRefresh] (server POST /sync then
  /// reload of the current label); reports success/failure with a toast since an
  /// explicit tap is a deliberate user action. Re-tapping while a sync is in flight
  /// is blocked at the button (onPressed null when isSyncing) and idempotently by the
  /// provider's _isSyncing guard.
  Future<void> _syncNow() async {
    final t = AppLocalizations.of(context);
    final mail = context.read<MailProvider>();
    await mail.syncRefresh();
    if (!mounted) return;
    if (mail.error != null) {
      AppToast.error(context, t.mailSyncFailed);
    } else {
      AppToast.success(context, t.mailSynced);
    }
  }

  /// text text — text text text translated text text(translated text translated text text).
  void _switchLabel(String label) {
    final provider = context.read<MailProvider>();
    if (provider.currentLabel == label) return;
    provider.loadInbox(label: label);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final accounts = context.watch<AccountProvider>();

    // ── account translated text(NR0003 §5.5) — inbox display translated text account translated text branchtext. ──
    // text text text/text translated text translated text. "text" lookup failed(translated text/session, textaccounttext
    // textminutes)text translated text translated text translated text text(NR0004 §4). translated text 0text translated text.
    // ≥1text text text UI.
    if (accounts.gate == AccountGateState.error) {
      return _buildGateError(context, t, accounts);
    }
    if (!accounts.isResolved) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!accounts.hasAccounts) {
      return _buildOnboarding(context, t);
    }

    // Embedded in the shared MainScreen Body (it provides the AppBar). The mail
    // toolbar lives in the label-switcher tray below (CH0007/NR0009): the shell
    // AppBar shows only [search][overflow] for mail, while the mail-specific
    // actions — compose / mark-all-read / account — sit in this tray. Compose was
    // a FloatingActionButton before; it is now the tray "+" so all mail actions
    // are grouped in one place.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Mail toolbar tray (CH0007/NR0009): right of the label switcher, the
          // three mail actions in the user-specified order — [+ compose] /
          // [mark all read] / [account connect]. When accounts already exist the
          // onboarding CTA does not appear, so the account button here also stays
          // the guaranteed path to AccountConnectScreen (add/reconnect/disconnect).
          Row(
            children: [
              Expanded(
                child: _LabelSwitcher(
                  current: context.watch<MailProvider>().currentLabel,
                  onSelected: _switchLabel,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: t.mailComposeTooltip,
                onPressed: _compose,
              ),
              IconButton(
                icon: const Icon(Icons.mark_email_read_rounded),
                tooltip: t.mailMarkAllRead,
                onPressed: _markAllRead,
              ),
              // R0001(0042) — manual sync/refresh, between mark-all-read and
              // account-connect as requested. While a sync is running the icon is
              // replaced by a same-size spinner and the button is disabled so it
              // cannot be double-fired.
              Builder(builder: (context) {
                final syncing = context.watch<MailProvider>().isSyncing;
                return IconButton(
                  icon: syncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  tooltip: t.mailSyncTooltip,
                  onPressed: syncing ? null : _syncNow,
                );
              }),
              IconButton(
                icon: const Icon(Icons.manage_accounts_rounded),
                tooltip: t.accountManageTooltip,
                onPressed: _openAccounts,
              ),
              const SizedBox(width: 4),
            ],
          ),
          // Re-auth required (status=reauth_required) banner — surfaces the state
          // that 0018.0009-TR assigns when the OAuth credential is lost, and opens
          // the reconnect path.
          if (accounts.hasReauthRequired)
            _ReauthBanner(
              email: accounts.reauthAccounts.first.email,
              onReconnect: _openAccounts,
            ),
          // B0001(0037, NR0003 H2) — per-account sync failures used to vanish
          // silently (the inbox just looked empty). The server now reports which
          // accounts failed and why; surface that as a dismissible warning so a
          // single flaky account is no longer invisible.
          Builder(builder: (context) {
            final errors = context.watch<MailProvider>().syncAccountErrors;
            if (errors.isEmpty) return const SizedBox.shrink();
            final sig = errors.map((e) => '${e.accountId}:${e.message}').join('|');
            if (sig == _dismissedSyncErrorSig) return const SizedBox.shrink();
            return _SyncErrorBanner(
              errors: errors,
              onDismiss: () => setState(() => _dismissedSyncErrorSig = sig),
            );
          }),
          Expanded(child: _buildBody(context, t)),
        ],
      ),
    );
  }

  /// account text failed translated text — NR0004 §4 (translated text translated text).
  ///
  /// text screen ErrorRetry text text translated text text translated text translated text text screentext
  /// translated text. text translated text **translated text** translated text banner(translated text message·retry)text text,
  /// text text translated text(account text CTA)text as-is translated text account add translated text preservedtext.
  /// (text screentext text text translated text text translated text text text translated text.)
  /// 401/403(session expired)text "again login" translated text, text text(translated text text)text text errortext
  /// textminutestext translated text.
  Widget _buildGateError(
      BuildContext context, AppLocalizations t, AccountProvider accounts) {
    final theme = Theme.of(context);
    final isSession = accounts.errorKind == AccountLoadErrorKind.session;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: theme.colorScheme.errorContainer,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  isSession
                      ? Icons.lock_clock_rounded
                      : Icons.cloud_off_rounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isSession
                        ? t.accountGateSessionExpired
                        : t.accountGateTransientError,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _enterMail,
                  child: Text(t.accountGateRetry),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildOnboardingCard(context, t),
      ],
    );
  }

  /// textaccount translated text — translated text "translated text translated text translated text + Retry" text, accounttext
  /// translated text translated text text translated text translated text(NR0003 §5.6).
  Widget _buildOnboarding(BuildContext context, AppLocalizations t) {
    return Center(child: _buildOnboardingCard(context, t));
  }

  /// translated text text Body(Center translated text) — textaccount translated text error translated text(translated text banner
  /// text)text translated text. ListView translated text translated text mainAxisSize.min Column.
  Widget _buildOnboardingCard(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mark_email_unread_rounded,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            t.accountOnboardingTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            t.accountOnboardingBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openAccounts,
            icon: const Icon(Icons.add_link_rounded),
            label: Text(t.accountConnectCta),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations t) {
    final mail = context.watch<MailProvider>();

    // R0001(0037 rev1) — give every linked account a DISTINCT row color. The
    // previous code hashed the account id into a 10-color palette; with only a
    // few accounts two ids could hash to the same slot, so the list looked like
    // it used "one color". Assign instead by the account's stable position in
    // the AccountProvider list, so the first N≤10 accounts get N different
    // colors (palette cycles beyond that). Accounts no longer in the live list
    // (e.g. a removed account whose mail is still cached) fall back to the hash.
    final colorMap = <String, Color>{};
    final accs = context.watch<AccountProvider>().accounts;
    for (var i = 0; i < accs.length; i++) {
      final id = accs[i].accountId;
      if (id.isNotEmpty) {
        colorMap.putIfAbsent(
            id, () => _kAccountPalette[i % _kAccountPalette.length]);
      }
    }

    if (mail.isLoading && mail.mails.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (mail.error != null && mail.mails.isEmpty) {
      return ErrorRetry(
        message: t.mailLoadFailed,
        onRetry: () => context.read<MailProvider>().refresh(),
      );
    }
    if (mail.mails.isEmpty) {
      return EmptyState(
        message: t.mailListEmpty,
        icon: Icons.mail_outline_rounded,
      );
    }

    // R0001(0027) — pins do not pile up in the chronological list; they gather in
    // a **separate "ピン留め(pinned)" tray** (reflecting the user's rejection). The
    // list is partitioned into pinned/unpinned to render the tray (top) and the
    // chronological body list (below, unpinned only) separately.
    final pinned = mail.pinnedMails;
    final rest = mail.unpinnedMails;
    final hasTray = pinned.isNotEmpty;
    final trayCount = hasTray ? 1 : 0;

    return RefreshIndicator(
      // R0001: pull-to-refresh on the inbox syncs the server then reloads (syncRefresh);
      // on other labels (sent/drafts) it only reloads locally.
      onRefresh: () => context.read<MailProvider>().syncRefresh(),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: trayCount + rest.length + (mail.hasMore ? 1 : 0),
        // The tray has its own container border, so no divider is placed below it.
        separatorBuilder: (_, index) =>
            (hasTray && index == 0) ? const SizedBox.shrink() : const Divider(height: 1),
        itemBuilder: (context, index) {
          // Index mapping of [tray?] + unpinned mails + [load-more spinner?].
          if (hasTray && index == 0) {
            return _buildPinnedTray(context, t, pinned, colorMap);
          }
          final i = index - trayCount;
          if (i >= rest.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final summary = rest[i];
          return _MailListTile(
            summary: summary,
            accountColor: _resolveAccountColor(summary.account, colorMap),
            onTap: () => _openMail(summary),
            onTogglePin: () =>
                context.read<MailProvider>().togglePin(summary.mailId),
          );
        },
      ),
    );
  }

  /// R0001(0027) — the "ピン留め(pinned)" tray. Gathers pinned mails into a visual
  /// container (tinted background, border, header) separate from the chronological
  /// list. It can be collapsed/expanded by tapping the header (so many pins fold
  /// away without burden even when space is ample), and when expanded it renders
  /// the pinned mail rows as-is (including the per-row pin toggle) — unpinning from
  /// the tray immediately drops that mail down into the body list below.
  Widget _buildPinnedTray(BuildContext context, AppLocalizations t,
      List<MailSummary> pinned, Map<String, Color> colorMap) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header: pin icon + label + count badge + expand/collapse chevron. The whole row is the tap area.
          InkWell(
            onTap: () =>
                setState(() => _pinnedTrayExpanded = !_pinnedTrayExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.push_pin_rounded,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    t.mailPinnedTray,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: t.mailPinnedTrayCount(pinned.length),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${pinned.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _pinnedTrayExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                    semanticLabel: _pinnedTrayExpanded
                        ? t.mailPinnedTrayCollapse
                        : t.mailPinnedTrayExpand,
                  ),
                ],
              ),
            ),
          ),
          if (_pinnedTrayExpanded)
            for (final summary in pinned) ...[
              const Divider(height: 1),
              _MailListTile(
                summary: summary,
                accountColor: _resolveAccountColor(summary.account, colorMap),
                onTap: () => _openMail(summary),
                onTogglePin: () =>
                    context.read<MailProvider>().togglePin(summary.mailId),
              ),
            ],
        ],
      ),
    );
  }
}

/// Re-auth required banner (R0001) — surfaces an account that is connected but has
/// lost its OAuth credential (status=reauth_required), and opens AccountConnectScreen
/// via the "reconnect" button. The server's ReconnectAccount updates the existing
/// account row, so no duplicate account is created.
class _ReauthBanner extends StatelessWidget {
  final String email;
  final VoidCallback onReconnect;

  const _ReauthBanner({required this.email, required this.onReconnect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.key_off_rounded, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.accountReauthBannerTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.accountReauthBannerBody(email),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onReconnect,
            child: Text(t.accountReauthAction),
          ),
        ],
      ),
    );
  }
}

/// B0001(0037, NR0003 H2) — a dismissible warning that one or more accounts
/// failed to sync on the last refresh. Replaces the old silent swallow where a
/// flaky account simply made the inbox look empty with no explanation. Shows the
/// failed-account count (localized plural) and the first account's reason for a
/// quick clue; the user can dismiss it.
class _SyncErrorBanner extends StatelessWidget {
  final List<SyncAccountError> errors;
  final VoidCallback onDismiss;

  const _SyncErrorBanner({required this.errors, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final first = errors.first;
    final detail = first.email.isNotEmpty
        ? '${first.email} — ${first.message}'
        : first.message;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sync_problem_rounded,
              color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.mailSyncAccountFailed(errors.length),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: t.commonClose,
            color: theme.colorScheme.onTertiaryContainer,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// text translated text — Inbox/Drafts/Sent translated text translated text.
///
/// Draft translated text(§7.9)text UI translated text: Draftstext translated text translated text Draft translated text
/// text compose screen(translated text)text translated text text text(TR0009 remaining work "text translated text").
class _LabelSwitcher extends StatelessWidget {
  final String current;
  final ValueChanged<String> onSelected;

  const _LabelSwitcher({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: kMailSystemLabels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final label = kMailSystemLabels[i];
          return ChoiceChip(
            label: Text(mailLabelName(t, label)),
            selected: current == label || (label == 'drafts' && current == 'draft'),
            onSelected: (_) => onSelected(label),
          );
        },
      ),
    );
  }
}

/// R0001(0013) — per-account distinguishing-color palette. The server's
/// `display_color` is often assigned the same default per account (Gmail #EA4335,
/// etc.), so color alone cannot distinguish them. The list assigns these colors by
/// the account's *position* in the linked-account list (see `_buildBody`), so the
/// first N≤10 accounts get N visibly different colors; `_accountColor` (a stable
/// hash) is only the fallback for accounts no longer present in that list.
const List<Color> _kAccountPalette = [
  Color(0xFF1565C0), // blue
  Color(0xFF2E7D32), // green
  Color(0xFFAD1457), // pink
  Color(0xFF6A1B9A), // purple
  Color(0xFFEF6C00), // orange
  Color(0xFF00838F), // cyan
  Color(0xFFC62828), // red
  Color(0xFF4527A0), // deep purple
  Color(0xFF558B2F), // light green
  Color(0xFF00695C), // teal
];

/// Account identifier → stable distinguishing color. The same account always gets
/// the same color, different accounts (almost) always different. Neutral gray if no identifier.
///
/// Fallback only: hashes can collide (two ids → same slot), which is exactly what
/// made the list look single-colored, so the live list now prefers index-based
/// assignment (`_resolveAccountColor`) and this is used only for accounts absent
/// from the current AccountProvider list.
Color _accountColor(MailAccountRef account) {
  final key = account.key;
  if (key.isEmpty) return const Color(0xFF607D8B);
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _kAccountPalette[hash % _kAccountPalette.length];
}

/// Resolve a mail row's account color: prefer the distinct index-based color from
/// the linked-account list (`colorMap`, keyed by account id); fall back to the
/// stable hash for accounts not in the live list.
Color _resolveAccountColor(MailAccountRef account, Map<String, Color> colorMap) {
  final mapped = colorMap[account.accountId];
  if (mapped != null) return mapped;
  return _accountColor(account);
}

class _MailListTile extends StatelessWidget {
  final MailSummary summary;
  final VoidCallback onTap;

  /// R0001(0037 rev1) — the distinct per-account color resolved by the parent
  /// list from the account's position (so each linked account differs).
  final Color accountColor;

  /// R0001(0027) — the row's pin toggle. Pin = entry point to the pin-to-top UX (trailing pin icon).
  final VoidCallback onTogglePin;

  const _MailListTile({
    required this.summary,
    required this.accountColor,
    required this.onTap,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final unread = !summary.isRead;
    final weight = unread ? FontWeight.w700 : FontWeight.w400;
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final acct = summary.account;
    final acctColor = accountColor;
    final pinned = summary.isPinned;
    return ListTile(
      onTap: onTap,
      // R0001(0030) — read/unread was distinguished by font weight ALONE (bold vs
      // not), which the user found too subtle. Reinforce unread with two extra
      // always-visible cues on top of the bold: (1) a filled accent dot at the row
      // head, (2) a faint surface tint behind the whole row. Read rows get neither
      // (transparent dot placeholder keeps the text aligned), so the contrast
      // between the two states is unmistakable at a glance.
      tileColor: unread
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : null,
      // Trailing pin toggle — filled pin = pinned, outline = unpinned. Operates
      // independently of the row-body tap (open detail) (the IconButton intercepts its own tap).
      trailing: IconButton(
        icon: Icon(
          pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          size: 20,
          color: pinned ? theme.colorScheme.primary : null,
        ),
        tooltip: pinned ? t.mailUnpin : t.mailPin,
        onPressed: onTogglePin,
      ),
      // Unread dot + left color bar + avatar. The unread dot (R0001/0030) is the
      // primary at-a-glance cue; the bar color differs per account so you can tell
      // at a glance which account a mail arrived at.
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Filled accent dot when unread; a same-size transparent placeholder
          // when read so sender/avatar stay vertically aligned across both states.
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: unread ? theme.colorScheme.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: acct.hasIdentity ? acctColor : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: acct.hasIdentity ? acctColor : null,
            foregroundColor: acct.hasIdentity ? Colors.white : null,
            child: Text(
              summary.from.display.isNotEmpty
                  ? summary.from.display.characters.first.toUpperCase()
                  : '?',
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              summary.from.display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: weight),
            ),
          ),
          if (summary.hasAttachment)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.attach_file_rounded, size: 16),
            ),
          const SizedBox(width: 6),
          Text(
            _shortTime(summary.receivedAt),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.subject.isEmpty ? t.noSubject : summary.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: weight),
          ),
          if (summary.snippet.isNotEmpty)
            Text(
              summary.snippet,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          // R0001(0013) — a badge showing which account received it (dot + account label).
          if (acct.hasIdentity)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: acctColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      acct.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: acctColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// ISO-8601 stringtext text textminutestext text text(text translated text text i18n text).
  static String _shortTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }
}
