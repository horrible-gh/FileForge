import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/mail_provider.dart';
import '../../models/mail.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/app_toast.dart';
import '../../services/mail_compose.dart';
import 'mail_detail_screen.dart';
import 'mail_compose_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MailProvider>().loadInbox();
    });
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
            summary.subject.isEmpty ? '(no subject)' : summary.subject,
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
