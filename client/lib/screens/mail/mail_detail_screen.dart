import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/mail_provider.dart';
import '../../models/mail.dart';
import '../../services/mail_compose.dart';
import '../../utils/mail_body_render.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/mail_html_body.dart';
import 'mail_compose_screen.dart';

/// text text screen — NR0003 §7 initial implementation(text translated text).
///
/// text·text/text·translated text·Body·text translated text displaytext. text text text text +
/// translated text text text(MailProvider.openMail).
/// HTML Body text translated text text translated text text(NR0003 §6)text translated text
/// initial implementationtext translated text translated text displaytext, text text(text T)text translated text.
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
        ..._buildBodyContent(detail.body),
        if (detail.attachments.isNotEmpty) ...[
          const Divider(height: 32),
          Text(t.attachmentsLabel, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...detail.attachments.map((a) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file_rounded),
                title: Text(a.filename),
                subtitle: Text(_humanSize(a.sizeBytes)),
                // text downloadtext text text(text T)text translated text(P0007 §6.4).
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

  /// Render the body. Plain text shows as-is; HTML is rendered with a real HTML
  /// widget so styled layout (tables, fonts, inline CSS, images) appears the way
  /// the legacy web client showed it (0008 R0001 — the previous tag-stripping
  /// path mangled layout and leaked `<style>` CSS as visible text).
  ///
  /// `flutter_widget_from_html_core` drops non-displayed elements
  /// (`<style>`/`<script>`/`<head>`), renders inline styles, tables and `<img>`
  /// (server already inlines `cid:` pictures as `data:` URIs; remote `<img>`
  /// load over the network). If the HTML is empty/unrenderable we fall back to
  /// the hardened plain-text strip.
  ///
  /// [MailHtmlBody] wraps each image in a layout-stable box so loading an image
  /// cannot relayout the hovered subtree (0009 R0001 / NR0003 — the
  /// `mouse_tracker.dart:199` re-entrancy assertion flood).
  List<Widget> _buildBodyContent(MailBody body) {
    if (!body.isHtml) {
      return [SelectableText(body.content)];
    }
    if (body.content.trim().isEmpty) {
      return [SelectableText(stripHtmlToText(body.content))];
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
