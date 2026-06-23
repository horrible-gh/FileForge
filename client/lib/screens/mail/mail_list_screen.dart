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

/// 라벨 스위처가 노출하는 시스템 라벨(읽기 슬라이스 범위).
///
/// 'drafts' 는 [MailProvider] 의 초안 라벨 판정(`_isDraftsLabel`)과 맞물려,
/// 이 라벨을 보고 있을 때 항목 탭이 상세가 아니라 이어쓰기로 열리게 한다.
const List<String> kMailSystemLabels = ['inbox', 'drafts', 'sent'];

/// 시스템 라벨의 현지화된 표시 이름.
String mailLabelName(AppLocalizations t, String label) => switch (label) {
      'draft' || 'drafts' => t.labelDrafts,
      'sent' => t.labelSent,
      _ => t.labelInbox,
    };

/// 메일 목록 화면 — NR0003 §7 초기 구현(읽기 슬라이스).
///
/// MainScreen(ShellRoute) 본문에 표시된다. 스토리지 타입이 'mail'일 때
/// StorageDispatcher가 FileListScreen 대신 이 화면을 렌더한다.
/// 항목 탭 → 상세 화면(전체 화면 push). 스크롤 끝 도달 시 다음 묶음 로드.
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

  /// 메일 진입 게이트(NR0003 §5.5) — inbox 를 긁기 전에 연결된 계정이 있는지
  /// 먼저 확인한다. 계정이 0개면 inbox 를 호출하지 않고(사용자가 본 "에러+Retry"
  /// 의 근본) 온보딩 화면으로 흘려보낸다. 1개 이상일 때만 loadInbox 한다.
  Future<void> _enterMail() async {
    final accounts = context.read<AccountProvider>();
    // 낙관적 렌더(TR0005 §증상1): 캐시된 마지막 계정 유무로 화면을 즉시 그린다.
    // 캐시상 계정이 있었으면 네트워크 응답 전이라도 inbox 를 선로딩한다.
    final primed = await accounts.primeFromCache();
    if (!mounted) return;
    if (primed && accounts.hasAccounts) {
      context.read<MailProvider>().loadInbox();
    }
    // 실로드로 재조정한다(이미 ready 면 스피너로 되돌지 않음).
    await accounts.load();
    if (!mounted) return;
    final mail = context.read<MailProvider>();
    if (accounts.hasAccounts && mail.mails.isEmpty) {
      mail.loadInbox();
    }
  }

  /// 계정 연결 화면으로 이동. 돌아왔을 때 계정이 생겼으면 inbox 를 로드한다
  /// (AccountConnectScreen 이 공유 AccountProvider 를 갱신하므로 즉시 반영됨).
  Future<void> _openAccounts() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountConnectScreen()),
    );
    if (!mounted) return;
    final mail = context.read<MailProvider>();
    if (context.read<AccountProvider>().hasAccounts && mail.mails.isEmpty) {
      mail.loadInbox();
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

  /// 초안 라벨(시스템) 여부 — 초안 항목 탭은 상세가 아니라 이어쓰기로 연다.
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

  /// 초안 이어쓰기(§7.9) — 초안을 불러와 작성 화면을 연다. 닫힌 뒤 목록 갱신.
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

  /// 라벨 전환 — 이미 보고 있는 라벨이면 무시(불필요한 재로드 방지).
  void _switchLabel(String label) {
    final provider = context.read<MailProvider>();
    if (provider.currentLabel == label) return;
    provider.loadInbox(label: label);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final accounts = context.watch<AccountProvider>();

    // ── 계정 게이트(NR0003 §5.5) — inbox 표시 이전에 계정 유무로 분기한다. ──
    // 아직 확인 전/확인 중이면 스피너. "진짜" 조회 실패(네트워크/세션, 무계정과
    // 구분)면 블랙아웃이 아니라 비차단 안내(NR0004 §4). 확인됐는데 0개면 온보딩.
    // ≥1개일 때만 메일 UI.
    if (accounts.gate == AccountGateState.error) {
      return _buildGateError(context, t, accounts);
    }
    if (!accounts.isResolved) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!accounts.hasAccounts) {
      return _buildOnboarding(context, t);
    }

    // 셸(MainScreen) 본문에 작성 FAB를 더하기 위해 내부 Scaffold로 감싼다
    // (AppBar는 셸이 제공하므로 두지 않는다).
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _compose,
        tooltip: t.mailComposeTooltip,
        child: const Icon(Icons.edit_rounded),
      ),
      body: Column(
        children: [
          _LabelSwitcher(
            current: context.watch<MailProvider>().currentLabel,
            onSelected: _switchLabel,
          ),
          Expanded(child: _buildBody(context, t)),
        ],
      ),
    );
  }

  /// 계정 읽기 실패 게이트 — NR0004 §4 (썬더버드 패리티).
  ///
  /// 전체 화면 ErrorRetry 로 앱을 블랙아웃하던 것이 사용자가 화내던 차단 화면의
  /// 근원이었다. 대신 상단에 **비차단** 인라인 배너(원인별 문구·재시도)를 두고,
  /// 그 아래 온보딩(계정 연결 CTA)을 그대로 노출해 계정 추가 도달성을 보존한다.
  /// (설정 화면은 별개 셸 라우트라 이와 무관하게 항상 도달 가능하다.)
  /// 401/403(세션 만료)은 "다시 로그인" 신호로, 그 외(네트워크 등)는 일시 오류로
  /// 구분해 안내한다.
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

  /// 무계정 온보딩 — 무서운 "메일을 불러오지 못했습니다 + Retry" 대신, 계정을
  /// 연결하라는 안내와 연결 버튼을 보여준다(NR0003 §5.6).
  Widget _buildOnboarding(BuildContext context, AppLocalizations t) {
    return Center(child: _buildOnboardingCard(context, t));
  }

  /// 온보딩 카드 본문(Center 미포함) — 무계정 게이트와 에러 게이트(인라인 배너
  /// 아래)에서 공유한다. ListView 안에서도 안전하도록 mainAxisSize.min Column.
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
      onRefresh: () => context.read<MailProvider>().refresh(),
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

/// 라벨 스위처 — 받은편지함/임시보관함/보낸편지함 사이를 전환한다.
///
/// 초안 이어쓰기(§7.9)의 UI 진입점: 임시보관함을 골라야 목록의 초안 항목을
/// 탭해 작성 화면(이어쓰기)으로 들어갈 수 있다(TR0009 잔여 "라벨 스위처").
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

  /// ISO-8601 문자열에서 날짜 부분만 간단 표기(상세 포맷은 후속 i18n 작업).
  static String _shortTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }
}
