import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/mail_provider.dart';
import '../../models/mail.dart';
import '../../services/mail_compose.dart';
import '../../widgets/error_retry.dart';
import 'mail_compose_screen.dart';

/// 메일 상세 화면 — NR0003 §7 초기 구현(읽기 슬라이스).
///
/// 제목·발신/수신·수신시각·본문·첨부 메타를 표시한다. 진입 시 상세 로드 +
/// 안읽음이면 읽음 처리(MailProvider.openMail).
/// HTML 본문 리치 렌더링은 신규 의존성 도입(NR0003 §6)이 필요하므로
/// 초기 구현은 텍스트 폴백으로 표시하고, 상세 구현(후속 T)에서 교체한다.
class MailDetailScreen extends StatefulWidget {
  final String mailId;
  final String subject;

  const MailDetailScreen({super.key, required this.mailId, this.subject = ''});

  @override
  State<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends State<MailDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MailProvider>().openMail(widget.mailId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final mail = context.watch<MailProvider>();
    final detail = mail.detail;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.subject.isEmpty ? t.mailDetailTitle : widget.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (detail != null)
            PopupMenuButton<ComposeMode>(
              icon: const Icon(Icons.reply_rounded),
              onSelected: (mode) => _compose(mode, detail),
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: ComposeMode.reply, child: Text(t.composeTitleReply)),
                PopupMenuItem(
                    value: ComposeMode.replyAll,
                    child: Text(t.composeTitleReplyAll)),
                PopupMenuItem(
                    value: ComposeMode.forward,
                    child: Text(t.composeTitleForward)),
              ],
            ),
        ],
      ),
      body: _buildBody(context, mail, detail),
    );
  }

  void _compose(ComposeMode mode, MailDetail detail) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MailComposeScreen(
          mode: mode,
          initial: composeFrom(mode, detail),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MailProvider mail, MailDetail? detail) {
    final t = AppLocalizations.of(context);
    if (mail.detailLoading && detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (mail.detailError != null && detail == null) {
      return ErrorRetry(
        message: t.mailLoadFailed,
        onRetry: () => context.read<MailProvider>().openMail(widget.mailId),
      );
    }
    if (detail == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          detail.subject.isEmpty ? t.noSubject : detail.subject,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        _addrRow(context, t.fieldFrom, [detail.from]),
        if (detail.to.isNotEmpty) _addrRow(context, t.fieldTo, detail.to),
        if (detail.cc.isNotEmpty) _addrRow(context, t.fieldCc, detail.cc),
        const SizedBox(height: 4),
        Text(
          _formatTime(detail.receivedAt),
          style: theme.textTheme.bodySmall,
        ),
        const Divider(height: 32),
        SelectableText(_renderBody(detail.body)),
        if (detail.attachments.isNotEmpty) ...[
          const Divider(height: 32),
          Text(t.attachmentsLabel, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...detail.attachments.map((a) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file_rounded),
                title: Text(a.filename),
                subtitle: Text(_humanSize(a.sizeBytes)),
                // 첨부 다운로드는 상세 구현(후속 T)에서 연결한다(P0007 §6.4).
              )),
        ],
      ],
    );
  }

  Widget _addrRow(BuildContext context, String label, List<MailAddress> addrs) {
    final text = addrs.map((a) {
      final d = a.display;
      return d == a.address ? a.address : '$d <${a.address}>';
    }).join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  /// 초기 구현 본문 렌더링: text는 그대로, html은 태그를 제거한 텍스트 폴백.
  /// 리치 HTML 렌더링은 NR0003 §6(flutter_widget_from_html 도입) 후 교체.
  static String _renderBody(MailBody body) {
    if (!body.isHtml) return body.content;
    return body.content
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  static String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
