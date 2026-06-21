import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/mail.dart';
import '../../providers/mail_provider.dart';
import '../../services/mail_compose.dart';
import '../../services/mail_envelope.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/recipient_field.dart';

/// 메일 작성 화면 — NR0003 §7 상세 구현(쓰기 슬라이스 마무리). P0007 §7.5~§7.11.
///
/// 새 메일/답장/전달/초안 이어쓰기를 한 화면으로 처리한다.
/// - 수신자는 칩(태그) 입력(RecipientField)으로 받는다.
/// - 첨부는 file_picker 로 골라 POST /attachments 로 올리고 attachment_ids 로
///   발송에 연결한다(§7.11).
/// - 본문 포맷(text/html)을 토글할 수 있다(리치 에디터는 NR0003 §6 후속).
/// - 기존 초안([draft])을 받으면 base_updated_at 으로 낙관적 경합 갱신한다(§7.10).
///
/// 발송 전 클라 선검증(L0012)을 수행하고, 서버가 RECIPIENT_INVALID/
/// VALIDATION_FAILED 를 반환하면 작성 내용을 보존한다(USER_ACTION — L0010 §2.3).
class MailComposeScreen extends StatefulWidget {
  final ComposeMode mode;

  /// 답장/전달 시 원본에서 파생한 초기 페이로드(composeFrom 결과).
  final SendPayload? initial;

  /// 이어쓰기 시 불러온 초안 — 본문·첨부·base_updated_at 의 출처(§7.9/§7.10).
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

/// 진행 중인 첨부 업로드 한 건(파일명 + 0..1 진행률).
class _UploadTask {
  final String filename;
  double progress = 0;
  _UploadTask(this.filename);
}

class _MailComposeScreenState extends State<MailComposeScreen> {
  // 수신자 목록의 단일 진실원(칩 위젯은 이 상태를 표시·편집).
  List<MailAddress> _to = const [];
  List<MailAddress> _cc = const [];
  List<MailAddress> _bcc = const [];

  late final TextEditingController _subject;
  late final TextEditingController _body;

  String _format = 'text'; // 'text' | 'html' (P0007 §3.2)
  bool _showCcBcc = false;

  final List<MailAttachment> _attachments = [];
  final List<_UploadTask> _uploads = [];

  bool _sending = false;
  String? _toError;

  // 초안 이어쓰기 상태.
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
    );
  }

  // ── 첨부 업로드 (§7.11) ─────────────────────────────────────────────────────

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
          context, AppLocalizations.of(context).attachFailed(filename));
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  bool get _uploadsInFlight => _uploads.isNotEmpty;

  // ── 발송 / 초안 ─────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    if (_uploadsInFlight) {
      AppToast.warning(context, t.waitUploads);
      return;
    }
    setState(() => _toError = null);
    final payload = _buildPayload();

    // 클라 선검증(L0012 §4.1) — 서버 왕복 전에 명백한 오류를 잡는다.
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
    // 실패 — 범주별 분기(L0010 §2.3). 작성 내용은 보존한다.
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
      // 신규 초안.
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

    // 기존 초안 갱신(낙관적 경합, §7.10).
    final result =
        await provider.updateDraft(_draftId!, payload, _baseUpdatedAt ?? '');
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

  /// §7.10 — 초안이 다른 곳에서 수정됨. 서버 최신본 재적재를 안내한다.
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
            icon: const Icon(Icons.drafts_outlined),
          ),
          IconButton(
            tooltip: t.sendTooltip,
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _sending,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                  icon: const Icon(Icons.add, size: 18),
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
      ),
    );
  }

  /// 본문 포맷 선택(text/html). 리치 에디터는 NR0003 §6 후속 — 현재 HTML 은
  /// 소스 입력으로 받아 그대로 전송한다(format='html').
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
            leading: const Icon(Icons.insert_drive_file_outlined),
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
            leading: const Icon(Icons.upload_file_outlined),
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
