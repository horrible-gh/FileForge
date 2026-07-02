import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/mail.dart';
import '../../models/mail_account.dart';
import '../../providers/account_provider.dart';
import '../../providers/mail_provider.dart';
import '../../services/mail_compose.dart';
import '../../services/mail_envelope.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/recipient_field.dart';

import 'package:flutter_dropzone/flutter_dropzone.dart'
    if (dart.library.io) '../../utils/dropzone_stub.dart';

/// text compose screen — NR0003 §7 text text(text translated text translated text). P0007 §7.5~§7.11.
///
/// text text/text/text/Draft translated text text screentext translated text.
/// - translated text text(text) text(RecipientField)text translated text.
/// - translated text file_picker text text POST /attachments text translated text attachment_ids text
///   translated text translated text(§7.11).
/// - Body text(text/html)text translated text text text(text translated text NR0003 §6 text).
/// - text Draft([draft])text translated text base_updated_at text translated text text refreshtext(§7.10).
///
/// text text text textverify(L0012)text translated text, servertext RECIPIENT_INVALID/
/// VALIDATION_FAILED text returntext compose contenttext preservedtext(USER_ACTION — L0010 §2.3).
class MailComposeScreen extends StatefulWidget {
  final ComposeMode mode;

  /// text/text text translated text translated text text translated text(composeFrom result).
  final SendPayload? initial;

  /// translated text text translated text Draft — Body·text·base_updated_at text text(§7.9/§7.10).
  final MailDraft? draft;

  const MailComposeScreen({
    super.key,
    this.mode = ComposeMode.newMail,
    this.initial,
    this.draft,
  });

  @override
  State<MailComposeScreen> createState() => _MailComposeScreenState();
}

/// text text text upload text text(filetext + 0..1 translated text).
class _UploadTask {
  final String filename;
  double progress = 0;
  _UploadTask(this.filename);
}

class _MailComposeScreenState extends State<MailComposeScreen> {
  // translated text translated text text translated text(text translated text text statetext display·text).
  List<MailAddress> _to = const [];
  List<MailAddress> _cc = const [];
  List<MailAddress> _bcc = const [];

  late final TextEditingController _subject;
  late final TextEditingController _body;

  String _format = 'text'; // 'text' | 'html' (P0007 §3.2)
  bool _showCcBcc = false;

  /// R0001(0035) — selected sender account (account_uuid). null = server default
  /// (first account). Reply/forward seed it from the original's receiving account.
  String? _fromAccountId;

  final List<MailAttachment> _attachments = [];
  final List<_UploadTask> _uploads = [];

  bool _sending = false;
  bool _isDraggingAttachment = false;
  String? _toError;
  DropzoneViewController? _dropController;

  // Draft translated text state.
  String? _draftId;
  String? _baseUpdatedAt;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    final init = widget.initial;
    if (draft != null) {
      _to = List.of(draft.to);
      _cc = List.of(draft.cc);
      _bcc = List.of(draft.bcc);
      _subject = TextEditingController(text: draft.subject);
      _body = TextEditingController(text: draft.body.content);
      _format = draft.body.format.isEmpty ? 'text' : draft.body.format;
      _attachments.addAll(draft.attachments);
      _draftId = draft.draftId;
      _baseUpdatedAt = draft.updatedAt;
    } else {
      _to = List.of(init?.to ?? const []);
      _cc = List.of(init?.cc ?? const []);
      _bcc = List.of(init?.bcc ?? const []);
      _subject = TextEditingController(text: init?.subject ?? '');
      _body = TextEditingController(text: init?.body.content ?? '');
      if (init != null && init.body.format.isNotEmpty) {
        _format = init.body.format;
      }
      _fromAccountId = init?.fromAccountId;
    }
    _showCcBcc = _cc.isNotEmpty || _bcc.isNotEmpty;
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  SendPayload _buildPayload() {
    final init = widget.initial;
    return SendPayload(
      to: _to,
      cc: _cc,
      bcc: _bcc,
      subject: _subject.text,
      body: MailBody(format: _format, content: _body.text),
      attachmentIds: _attachments.map((a) => a.attachmentId).toList(),
      inReplyTo: init?.inReplyTo,
      replyType: init?.replyType,
      fromAccountId: _fromAccountId,
    );
  }

  /// R0001(0035) — the effective sender id given the connected accounts: the
  /// explicit selection when it still maps to a connected account, otherwise the
  /// first account (mirrors the server's deterministic default). Empty when none.
  String _effectiveFrom(List<MailAccount> accounts) {
    if (_fromAccountId != null &&
        accounts.any((a) => a.accountId == _fromAccountId)) {
      return _fromAccountId!;
    }
    return accounts.isNotEmpty ? accounts.first.accountId : '';
  }

  // ── text upload (§7.11) ─────────────────────────────────────────────────────

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !mounted) return;
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      _startUpload(f.name, bytes);
    }
  }

  Future<void> _startUpload(String filename, List<int> bytes) async {
    final task = _UploadTask(filename);
    setState(() => _uploads.add(task));
    final meta = await context.read<MailProvider>().uploadAttachment(
      filename: filename,
      bytes: bytes,
      onProgress: (sent, total) {
        if (total > 0 && mounted) {
          setState(() => task.progress = sent / total);
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _uploads.remove(task);
      if (meta != null) _attachments.add(meta);
    });
    if (meta == null) {
      AppToast.error(
        context,
        AppLocalizations.of(context).attachFailed(filename),
      );
    }
  }

  void _handleAttachmentDrop(List<dynamic>? files) {
    if (!kIsWeb || _sending) return;
    if (_dropController == null || files == null || files.isEmpty) return;
    unawaited(_processDroppedAttachments(files));
  }

  Future<void> _processDroppedAttachments(List<dynamic> files) async {
    if (mounted) {
      setState(() => _isDraggingAttachment = false);
    }

    final droppedFiles = <({String filename, List<int> bytes})>[];
    final controller = _dropController;
    if (controller == null) return;

    for (final file in files) {
      if (file == null) continue;
      try {
        final filename = await controller.getFilename(file);
        final bytes = await controller.getFileData(file);
        droppedFiles.add((
          filename: filename.isEmpty ? 'attachment' : filename,
          bytes: bytes,
        ));
      } catch (_) {
        // Ignore unreadable drag items and keep valid files from the same drop.
      }
    }

    if (!mounted) return;
    for (final file in droppedFiles) {
      unawaited(_startUpload(file.filename, file.bytes));
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  bool get _uploadsInFlight => _uploads.isNotEmpty;

  // ── text / Draft ─────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    if (_uploadsInFlight) {
      AppToast.warning(context, t.waitUploads);
      return;
    }
    setState(() => _toError = null);
    final payload = _buildPayload();

    // text textverify(L0012 §4.1) — server text text translated text errortext translated text.
    final v = payload.validate();
    if (!v.ok) {
      setState(() {
        if (v.noRecipients) {
          _toError = t.enterRecipient;
        } else if (v.invalidAddresses.isNotEmpty) {
          _toError = t.invalidAddress(v.invalidAddresses.first);
        } else if (v.tooManyRecipients) {
          _toError = t.tooManyRecipients;
        }
      });
      if (v.subjectTooLong) {
        AppToast.warning(context, t.subjectTooLong);
      }
      return;
    }

    setState(() => _sending = true);
    final err = await context.read<MailProvider>().sendMail(payload);
    if (!mounted) return;
    setState(() => _sending = false);

    if (err == null) {
      AppToast.success(context, t.mailSent);
      Navigator.of(context).pop(true);
      return;
    }
    // failed — translated text branch(L0010 §2.3). compose contenttext preservedtext.
    if (err.category == MailErrorCategory.userAction &&
        err.code == 'RECIPIENT_INVALID') {
      setState(() => _toError = t.serverRejectedRecipient);
    } else {
      AppToast.error(context, t.sendFailed(err.code));
    }
  }

  Future<void> _saveDraft() async {
    final t = AppLocalizations.of(context);
    if (_uploadsInFlight) {
      AppToast.warning(context, t.waitUploads);
      return;
    }
    setState(() => _sending = true);
    final provider = context.read<MailProvider>();
    final payload = _buildPayload();

    if (_draftId == null) {
      // text Draft.
      final id = await provider.saveDraft(payload);
      if (!mounted) return;
      setState(() => _sending = false);
      if (id != null) {
        AppToast.success(context, t.draftSaved);
        Navigator.of(context).pop(false);
      } else {
        AppToast.error(context, t.draftSaveFailed);
      }
      return;
    }

    // text Draft refresh(translated text text, §7.10).
    final result = await provider.updateDraft(
      _draftId!,
      payload,
      _baseUpdatedAt ?? '',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    switch (result.status) {
      case DraftUpdateStatus.saved:
        _baseUpdatedAt = result.updatedAt ?? _baseUpdatedAt;
        AppToast.success(context, t.draftUpdated);
        Navigator.of(context).pop(false);
      case DraftUpdateStatus.conflict:
        await _handleDraftConflict();
      case DraftUpdateStatus.error:
        AppToast.error(context, t.draftUpdateFailed);
    }
  }

  /// §7.10 — Drafttext text translated text updatetext. server translated text translated text translated text.
  Future<void> _handleDraftConflict() async {
    final t = AppLocalizations.of(context);
    final reload = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.draftConflictTitle),
        content: Text(t.draftConflictBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.keepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.reload),
          ),
        ],
      ),
    );
    if (reload != true || !mounted || _draftId == null) return;
    final fresh = await context.read<MailProvider>().loadDraft(_draftId!);
    if (!mounted || fresh == null) return;
    setState(() {
      _to = List.of(fresh.to);
      _cc = List.of(fresh.cc);
      _bcc = List.of(fresh.bcc);
      _subject.text = fresh.subject;
      _body.text = fresh.body.content;
      _format = fresh.body.format.isEmpty ? 'text' : fresh.body.format;
      _attachments
        ..clear()
        ..addAll(fresh.attachments);
      _baseUpdatedAt = fresh.updatedAt;
      _showCcBcc = _cc.isNotEmpty || _bcc.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final title = widget.draft != null
        ? t.composeTitleDraft
        : switch (widget.mode) {
            ComposeMode.reply => t.composeTitleReply,
            ComposeMode.replyAll => t.composeTitleReplyAll,
            ComposeMode.forward => t.composeTitleForward,
            ComposeMode.newMail => t.composeTitleNew,
          };
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: t.saveDraftTooltip,
            onPressed: _sending ? null : _saveDraft,
            icon: const Icon(Icons.drafts_rounded),
          ),
          IconButton(
            tooltip: t.sendTooltip,
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
      body: _composeBody(context, t),
    );
  }

  Widget _composeBody(BuildContext context, AppLocalizations t) {
    final content = AbsorbPointer(
      absorbing: _sending,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _senderField(t),
          RecipientField(
            label: t.fieldTo,
            addresses: _to,
            errorText: _toError,
            onChanged: (xs) => setState(() => _to = xs),
          ),
          const SizedBox(height: 8),
          if (!_showCcBcc)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showCcBcc = true),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(t.ccBccToggle),
              ),
            ),
          if (_showCcBcc) ...[
            RecipientField(
              label: t.fieldCc,
              addresses: _cc,
              onChanged: (xs) => setState(() => _cc = xs),
            ),
            const SizedBox(height: 8),
            RecipientField(
              label: t.fieldBcc,
              addresses: _bcc,
              onChanged: (xs) => setState(() => _bcc = xs),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _subject,
            decoration: InputDecoration(labelText: t.subjectLabel),
          ),
          const SizedBox(height: 8),
          _formatToggle(t),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: t.messageLabel,
              alignLabelWithHint: true,
              hintText: _format == 'html' ? t.htmlSourceHint : null,
            ),
          ),
          const SizedBox(height: 12),
          _attachmentsSection(context),
          if (_sending)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );

    if (!kIsWeb) return content;

    return Stack(
      children: [
        content,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_isDraggingAttachment,
            child: DropzoneView(
              operation: DragOperation.copy,
              cursor: CursorType.Default,
              onCreated: (ctrl) => _dropController = ctrl,
              onHover: () {
                if (!_sending && !_isDraggingAttachment) {
                  setState(() => _isDraggingAttachment = true);
                }
              },
              onLeave: () {
                if (_isDraggingAttachment) {
                  setState(() => _isDraggingAttachment = false);
                }
              },
              onDropFiles: _handleAttachmentDrop,
            ),
          ),
        ),
        if (_isDraggingAttachment)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.14),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.upload_file_rounded,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t.uploadDropHere,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// R0001(0035) — sender account selector. Shown only when more than one account
  /// is linked (a single account leaves nothing to choose). The chosen account is
  /// what the message is sent from, ending the "who/what is the From — random?"
  /// ambiguity. Reply/forward arrive pre-selected with the receiving account.
  Widget _senderField(AppLocalizations t) {
    final accounts = context.watch<AccountProvider>().accounts;
    if (accounts.length < 2) return const SizedBox.shrink();
    final value = _effectiveFrom(accounts);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value.isNotEmpty ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: t.fieldFrom,
          prefixIcon: const Icon(Icons.account_circle_outlined),
        ),
        items: [
          for (final a in accounts)
            DropdownMenuItem<String>(
              value: a.accountId,
              child: Text(
                a.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _sending ? null : (v) => setState(() => _fromAccountId = v),
      ),
    );
  }

  /// Body text selection(text/html). text translated text NR0003 §6 text — current HTML text
  /// text translated text text as-is translated text(format='html').
  Widget _formatToggle(AppLocalizations t) {
    return Row(
      children: [
        Text(t.formatLabel),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text(t.formatPlain),
          selected: _format == 'text',
          onSelected: (_) => setState(() => _format = 'text'),
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          label: Text(t.formatHtml),
          selected: _format == 'html',
          onSelected: (_) => setState(() => _format = 'html'),
        ),
      ],
    );
  }

  Widget _attachmentsSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(t.attachmentsLabel, style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: _sending ? null : _pickAttachments,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(t.addLabel),
            ),
          ],
        ),
        for (var i = 0; i < _attachments.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            // Matches the detail-view attachment row glyph (NR0004 §4).
            leading: const Icon(Icons.description_rounded),
            title: Text(_attachments[i].filename, maxLines: 1),
            subtitle: Text(_humanSize(_attachments[i].sizeBytes)),
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: t.removeLabel,
              onPressed: () => _removeAttachment(i),
            ),
          ),
        for (final task in _uploads)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_rounded),
            title: Text(task.filename, maxLines: 1),
            subtitle: LinearProgressIndicator(
              value: task.progress > 0 ? task.progress : null,
            ),
          ),
      ],
    );
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
