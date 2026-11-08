import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/account_provider.dart';
import '../../providers/mail_provider.dart';
import '../../models/mail.dart';
import '../../models/mail_account.dart';
import '../../services/mail_compose.dart';
import '../../services/download_save_service.dart';
import '../../utils/mail_body_render.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/mail_html_body.dart';
import '../../widgets/mail_linked_text.dart';
import 'mail_compose_screen.dart';

/// Mail detail: one subject in the AppBar, address metadata and the message.
/// HTML uses the isolated browser renderer; plain text retains linked selection.
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
      if (mounted) context.read<MailProvider>().openMail(widget.mailId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final mail = context.watch<MailProvider>();
    // The provider may still hold the previous mail until openMail starts.
    // Never show its subject/actions as if they belonged to the current mail.
    final candidate = mail.detail;
    final detail = candidate?.mailId == widget.mailId ? candidate : null;
    final title = detail != null
        ? (detail.subject.trim().isEmpty ? t.noSubject : detail.subject)
        : (widget.subject.trim().isEmpty ? t.mailDetailTitle : widget.subject);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Pinning/unpinning keeps the list and detail in sync.
          if (detail != null)
            IconButton(
              icon: Icon(detail.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined),
              tooltip: detail.isPinned ? t.mailUnpin : t.mailPin,
              onPressed: () =>
                  context.read<MailProvider>().togglePin(detail.mailId),
            ),
          // The copy menu preserves whole-subject/body copy even when the
          // AppBar title is ellipsized or HTML uses a separate browser surface.
          if (detail != null)
            PopupMenuButton<_CopyTarget>(
              icon: const Icon(Icons.content_copy_rounded),
              tooltip: t.mailActionCopy,
              onSelected: (target) => _copy(target, detail),
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: _CopyTarget.subject, child: Text(t.mailCopySubject)),
                PopupMenuItem(
                    value: _CopyTarget.body, child: Text(t.mailCopyBody)),
                PopupMenuItem(
                    value: _CopyTarget.from, child: Text(t.mailCopyFrom)),
              ],
            ),
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
          initial: composeFrom(mode, detail, selfAddress: _selfAddress(detail)),
        ),
      ),
    );
  }

  /// Address of the account this mail arrived at, so "reply all" can drop the
  /// user from the Cc list. Falls back to the single connected account, then ''
  /// (no filter), preserving the B0001/0043 self-exclusion fix.
  String _selfAddress(MailDetail detail) {
    final List<MailAccount> accounts;
    try {
      accounts = context.read<AccountProvider>().accounts;
    } on ProviderNotFoundException {
      return '';
    }
    if (accounts.isEmpty) return '';
    for (final a in accounts) {
      if (a.accountId == detail.accountId) return a.email;
    }
    return accounts.length == 1 ? accounts.first.email : '';
  }

  /// Copy full original fields, not the ellipsized title or raw HTML/CSS.
  Future<void> _copy(_CopyTarget target, MailDetail detail) async {
    final t = AppLocalizations.of(context);
    final String value;
    switch (target) {
      case _CopyTarget.subject:
        value = detail.subject;
        break;
      case _CopyTarget.body:
        value = detail.body.isHtml
            ? stripHtmlToText(detail.body.content)
            : detail.body.content;
        break;
      case _CopyTarget.from:
        value = detail.from.address;
        break;
    }
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.mailCopied)),
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
    if (detail == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    // Address rows/plain text stay selectable. HTML selection belongs to the
    // browser. The sole subject lives in the AppBar, not again in this list.
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _addrRow(context, t.fieldFrom, [detail.from]),
          if (detail.to.isNotEmpty) _addrRow(context, t.fieldTo, detail.to),
          if (detail.cc.isNotEmpty) _addrRow(context, t.fieldCc, detail.cc),
          // Bcc is populated by the server for sent mail only.
          if (detail.bcc.isNotEmpty) _addrRow(context, t.fieldBcc, detail.bcc),
          const SizedBox(height: 4),
          Text(_formatTime(detail.receivedAt), style: theme.textTheme.bodySmall),
          const Divider(height: 32),
          ..._buildBodyContent(detail.body),
          if (detail.attachments.isNotEmpty) ...[
            const Divider(height: 32),
            Text(t.attachmentsLabel, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...detail.attachments.map((a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_rounded),
                  title: Text(a.filename),
                  subtitle: Text(_humanSize(a.sizeBytes)),
                  trailing: const Icon(Icons.download_rounded),
                  onTap: () => _handleAttachmentDownload(a),
                )),
          ],
        ],
      ),
    );
  }

  Future<void> _handleAttachmentDownload(MailAttachment attachment) async {
    final t = AppLocalizations.of(context);
    try {
      final response = await context.read<MailProvider>().downloadAttachment(
            mailId: widget.mailId,
            attachmentId: attachment.attachmentId,
          );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) AppToast.error(context, t.attachmentDownloadFailed);
        return;
      }
      final cdHeader = response.headers.value('content-disposition');
      final filename = DownloadSaveService.extractFilename(cdHeader) ??
          (attachment.filename.isNotEmpty
              ? attachment.filename
              : attachment.attachmentId);
      await DownloadSaveService.saveBytes(bytes: bytes, filename: filename);
      if (mounted) AppToast.success(context, t.attachmentDownloaded);
    } on DioException {
      if (mounted) AppToast.error(context, t.attachmentDownloadFailed);
    } catch (_) {
      if (mounted) AppToast.error(context, t.attachmentDownloadFailed);
    }
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
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  /// HTML uses MailHtmlBody's browser isolation/compatibility fallback. Keep
  /// plain-text URL handling and the existing copy contract unchanged.
  List<Widget> _buildBodyContent(MailBody body) {
    if (!body.isHtml) return [MailLinkedText(body.content)];
    if (body.content.trim().isEmpty) {
      return [MailLinkedText(stripHtmlToText(body.content))];
    }
    return [MailHtmlBody(body.content)];
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

enum _CopyTarget { subject, body, from }
