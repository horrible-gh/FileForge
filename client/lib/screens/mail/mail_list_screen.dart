import 'dart:async';

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

class _MailListScreenState extends State<MailListScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();

  /// R0001(0022) 실시간 수신 — 받은편지함이 화면에 떠 있는 동안 주기적으로 서버
  /// 동기화(POST /sync)를 끌어와 외부 도착 메일을 자동 반영한다. NR0003 방향 A:
  /// 서버 무변경(백그라운드 워커 부재는 클라 폴링으로 보완).
  ///
  /// 간격 = 10초(T0007, 이전 15초에서 단축). "부하 심하나?"에 대한 근거:
  /// 새 메일이 없는 폴은 IMAP SEARCH가 빈 결과를 돌려주고 즉시 끝나므로 **본문
  /// 다운로드가 전혀 없다**(sync.go doSyncLocked: 적용할 변경 0건이면 FetchChanges
  /// 1페이지에서 종료). 따라서 빈 폴 1회의 실비용은 단발성 TLS+IMAP 로그인
  /// 왕복뿐이고 트래픽은 수십 KB 미만이다. 게다가 폴링은 (a) 받은편지함이
  /// **포그라운드 최상위**일 때만 돌고(작성/상세 push·앱 백그라운드 시 정지),
  /// (b) 서버 `acquireSyncLock`(sync.go:53)이 중복 동시 sync를 멱등 차단하며,
  /// (c) 한 번에 연결 1개를 직렬로 열고 즉시 닫으므로 동시 연결이 누적되지 않는다.
  /// 10초 = 계정 1개 기준 활성 화면에서 분당 6회로, 받은편지함 포그라운드 동안만
  /// 도는 임시 수신 보완책이다. 더 줄이려면(예: <10초) 폴마다 TLS
  /// 재접속 오버헤드가 지배적이 되어 연결 재사용/IMAP IDLE(방향 C)이 필요하다.
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

  // ── 주기 폴링(실시간 수신) ─────────────────────────────────────────────────
  //
  // ★T0004 제약(반드시 준수): "메일을 작성하는 중에 리프레시가 작성을 방해해서는
  // 안 된다." 이를 두 겹으로 보장한다.
  //   (1) 작성/상세 화면이 받은편지함 위로 push되어 있으면(= 이 라우트가 최상위가
  //       아니면) 폴링 tick은 아무 동작도 하지 않는다(_pollTick의 isCurrent 가드).
  //   (2) 설령 tick이 돌더라도 동기화는 받은편지함 *목록* 상태만 갱신하며,
  //       MailComposeScreen은 자체 로컬 상태(TextEditingController 등)만 쓰고
  //       MailProvider를 watch하지 않으므로 입력 중인 본문이 사라지지 않는다.

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollTick());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 주기 동기화 1회. 작성/상세 등 다른 화면이 위에 올라와 있거나, 계정이 없거나,
  /// 받은편지함이 아닌 라벨이거나, 이미 동기화/로딩 중이면 건너뛴다.
  void _pollTick() {
    if (!mounted) return;
    // (1) 메일 작성 중 방해 금지 — 받은편지함이 최상위 라우트가 아니면 절대 sync 안 함.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (!context.read<AccountProvider>().hasAccounts) return;
    final mail = context.read<MailProvider>();
    // 받은편지함에서만 자동 수신. 보낸편지함/임시보관함은 수신 대상이 아니다.
    if (mail.currentLabel != 'inbox') return;
    if (mail.isSyncing || mail.isLoading) return;
    // 목록이 비어 있지 않으면 syncInbox는 전체화면 스피너를 띄우지 않고 조용히 갱신한다.
    mail.syncInbox();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드에선 폴링을 멈추고(네트워크/배터리 절약), 포그라운드 복귀 시 즉시
    // 1회 동기화 후 폴링을 재개한다 — 복귀 직후 한발짝 늦지 않도록.
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
          final summary = mail.mails[index];
          return _MailListTile(
            summary: summary,
            onTap: () => _openMail(summary),
            onTogglePin: () =>
                context.read<MailProvider>().togglePin(summary.mailId),
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

/// R0001(0013) — 계정별 구분색 팔레트. 서버 `display_color`는 계정마다 동일한
/// 기본값(Gmail #EA4335 등)으로 부여되는 경우가 많아, 색만으로는 구분이 안 된다.
/// 따라서 색은 계정 식별자 해시로 이 팔레트에서 안정적으로 파생해 *계정마다
/// 서로 다른 색*을 보장한다(텍스트 라벨이 1차 단서, 색은 보조 단서).
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

/// 계정 식별자 → 안정적 구분색. 같은 계정은 항상 같은 색, 다른 계정은(거의)
/// 다른 색. 식별자가 없으면 중립 회색.
Color _accountColor(MailAccountRef account) {
  final key = account.key;
  if (key.isEmpty) return const Color(0xFF607D8B);
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _kAccountPalette[hash % _kAccountPalette.length];
}

class _MailListTile extends StatelessWidget {
  final MailSummary summary;
  final VoidCallback onTap;

  /// R0001(0027) — 행의 핀 토글. 핀=상단 고정 UX의 진입점(트레일링 핀 아이콘).
  final VoidCallback onTogglePin;

  const _MailListTile({
    required this.summary,
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
    final acctColor = _accountColor(acct);
    final pinned = summary.isPinned;
    return ListTile(
      onTap: onTap,
      // 트레일링 핀 토글 — 채워진 핀=고정됨, 외곽선=미고정. 행 본문 탭(상세 열기)과
      // 독립적으로 동작한다(IconButton이 자체 탭을 가로챈다).
      trailing: IconButton(
        icon: Icon(
          pinned ? Icons.push_pin : Icons.push_pin_outlined,
          size: 20,
          color: pinned ? theme.colorScheme.primary : null,
        ),
        tooltip: pinned ? t.mailUnpin : t.mailPin,
        onPressed: onTogglePin,
      ),
      // 좌측 색상 바 + 아바타 — 바 색은 계정별로 달라 어느 계정인지 한눈에 보인다.
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          // R0001(0013) — 어느 계정으로 받았는지 표시하는 배지(점 + 계정 라벨).
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
