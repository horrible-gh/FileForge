import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/mail_provider.dart';
import '../../providers/account_provider.dart';
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

class _MailListScreenState extends State<MailListScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _enterMail());
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
      // R0001: 받은편지함 진입 시 서버 동기화(POST /sync)를 먼저 끌어온 뒤 재로딩한다.
      // 이 트리거가 없으면 수신 메일이 영영 로컬에 들어오지 않는다(syncInbox 내부에서
      // 동기화 실패는 best-effort로 무시하고 로컬 목록을 보여준다).
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
      // 막 계정을 연결/재연결했으므로 동기화로 수신함을 끌어온다(R0001).
      mail.syncInbox();
    }
  }

  @override
  void dispose() {
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

    // text(MainScreen) Bodytext compose FABtext translated text text text Scaffoldtext translated text
    // (AppBartext text translated text text translated text).
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _compose,
        tooltip: t.mailComposeTooltip,
        child: const Icon(Icons.edit_rounded),
      ),
      body: Column(
        children: [
          // 라벨 스위처 우측에 상시 계정 관리 진입점(R0001) — 계정이 이미
          // 있을 때는 온보딩 CTA가 뜨지 않으므로, 여기서 AccountConnectScreen으로
          // 가는 유일한 동선을 보장한다(추가·재연결·해제).
          Row(
            children: [
              Expanded(
                child: _LabelSwitcher(
                  current: context.watch<MailProvider>().currentLabel,
                  onSelected: _switchLabel,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.manage_accounts_rounded),
                tooltip: t.accountManageTooltip,
                onPressed: _openAccounts,
              ),
              const SizedBox(width: 4),
            ],
          ),
          // 재인증 필요(status=reauth_required) 배너 — 0018.0009-TR가 OAuth
          // credential 유실 시 부여하는 상태를 표면화하고 재연결 동선을 연다.
          if (accounts.hasReauthRequired)
            _ReauthBanner(
              email: accounts.reauthAccounts.first.email,
              onReconnect: _openAccounts,
            ),
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

    return RefreshIndicator(
      // R0001: 당겨서 새로고침은 받은편지함이면 서버 동기화 후 재로딩(syncRefresh),
      // 그 외 라벨(sent/drafts)은 로컬 재로딩만 수행한다.
      onRefresh: () => context.read<MailProvider>().syncRefresh(),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: mail.mails.length + (mail.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= mail.mails.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _MailListTile(
            summary: mail.mails[index],
            onTap: () => _openMail(mail.mails[index]),
          );
        },
      ),
    );
  }
}

/// 재인증 필요 배너(R0001) — 연결됐지만 OAuth credential이 유실된 계정
/// (status=reauth_required)을 표면화하고, "재연결" 버튼으로 AccountConnectScreen을
/// 연다. 서버 ReconnectAccount가 기존 계정 row를 갱신하므로 중복 계정은 생기지 않는다.
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

class _MailListTile extends StatelessWidget {
  final MailSummary summary;
  final VoidCallback onTap;

  const _MailListTile({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = !summary.isRead;
    final weight = unread ? FontWeight.w700 : FontWeight.w400;
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        child: Text(
          summary.from.display.isNotEmpty
              ? summary.from.display.characters.first.toUpperCase()
              : '?',
        ),
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
