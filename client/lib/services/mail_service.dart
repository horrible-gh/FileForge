import 'package:dio/dio.dart';
import '../models/mail.dart';
import 'mail_compose.dart';
import 'mail_envelope.dart';

/// POST /sync result (F) — the sync end state for the primary account.
/// [applied] is the number of changes merged into local storage by this sync;
/// [reauthRequired] is whether the server dropped the account to reauth_required
/// (re-authentication needed).
class SyncResult {
  final String state;
  final int applied;
  final bool reauthRequired;

  const SyncResult({
    required this.state,
    required this.applied,
    required this.reauthRequired,
  });
}

/// MailAnchor text(C) API text — P0007 §6.2 text endpoints.
///
/// initial implementation text(NR0003 §7): text translated text — text/text/text text.
/// compose·Draft·text·text·account·synctext text text(text T)text addtext.
/// authentication tokentext MailApiClient translated text translated text.
class MailService {
  final Dio _dio;

  MailService(this._dio);

  /// GET /mails — text text(text·text·text text, text). P0007 §6.2/§7.1/§4.
  /// empty valuetext translated text text translated text.
  Future<MailPage> listMails({
    String? label,
    String? q,
    bool? unread,
    String? cursor,
    int? limit,
  }) async {
    final resp = await _dio.get(
      '/mails',
      queryParameters: {
        if (label != null && label.isNotEmpty) 'label': label,
        if (q != null && q.isNotEmpty) 'q': q,
        if (unread == true) 'unread': true,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': ?limit,
      },
    );
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    final meta = envelopeMeta(resp.data);
    return MailPage.fromEnvelopeParts(
      expectListData(data, httpStatus: resp.statusCode),
      meta,
    );
  }

  /// POST /sync — triggers an inbox sync for the user's connected accounts (F, P0007 §7.15).
  /// The server performs the IMAP fetch inline (no background worker), so by the
  /// time this call returns, newly received mail is already merged into the local
  /// store. Unlike sending, inbound mail is only populated when this trigger fires
  /// (R0001: the root cause of mail not being received = the sync was never triggered).
  Future<SyncResult> triggerSync() async {
    final resp = await _dio.post('/sync');
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    final map = expectMapData(data, httpStatus: resp.statusCode);
    return SyncResult(
      state: map['state'] as String? ?? 'idle',
      applied: (map['applied'] as num?)?.toInt() ?? 0,
      reauthRequired: map['reauth_required'] == true,
    );
  }

  /// GET /mails/{mail_id} — text text. P0007 §6.2/§7.3.
  Future<MailDetail> getMail(String mailId) async {
    final resp = await _dio.get('/mails/$mailId');
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return MailDetail.fromJson(expectMapData(data, httpStatus: resp.statusCode));
  }

  /// PATCH /mails/{mail_id} — text text change. P0007 §6.2/§7.3.
  Future<void> setRead(String mailId, bool isRead) async {
    final resp = await _dio.patch(
      '/mails/$mailId',
      data: {'is_read': isRead},
    );
    unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
  }

  /// PATCH /mails/{mail_id} {is_pinned} — pin/unpin (R0001/0027).
  /// The server accepts is_pinned on the same PATCH endpoint as is_read and
  /// updates only within the owner scope (authenticated user_uuid), avoiding the
  /// legacy /actions/pin IDOR.
  Future<void> setPinned(String mailId, bool isPinned) async {
    final resp = await _dio.patch(
      '/mails/$mailId',
      data: {'is_pinned': isPinned},
    );
    unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
  }

  // ── compose/text/Draft (P0007 §6.2/§7.5~§7.10) ───────────────────────────────────

  /// POST /mails — text/text/text text. text result(mail_id text)text returntext(§7.5).
  Future<Map<String, dynamic>> sendMail(SendPayload payload) async {
    final resp = await _dio.post('/mails', data: payload.toJson());
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return expectMapData(data, httpStatus: resp.statusCode);
  }

  /// POST /drafts — Draft save. return: { draft_id, updated_at } (§7.9).
  Future<Map<String, dynamic>> saveDraft(SendPayload payload) async {
    final resp = await _dio.post('/drafts', data: payload.toJson());
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return expectMapData(data, httpStatus: resp.statusCode);
  }

  /// GET /drafts/{draft_id} — Draft load(translated text, §6.2/§7.9).
  Future<MailDraft> getDraft(String draftId) async {
    final resp = await _dio.get('/drafts/$draftId');
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return MailDraft.fromJson(expectMapData(data, httpStatus: resp.statusCode));
  }

  /// PUT /drafts/{draft_id} — Draft refresh(translated text text base_updated_at, §7.10).
  Future<Map<String, dynamic>> updateDraft(
    String draftId,
    SendPayload payload,
    String baseUpdatedAt,
  ) async {
    final resp = await _dio.put(
      '/drafts/$draftId',
      data: {...payload.toJson(), 'base_updated_at': baseUpdatedAt},
    );
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return expectMapData(data, httpStatus: resp.statusCode);
  }

  /// DELETE /drafts/{draft_id} — Draft delete.
  Future<void> deleteDraft(String draftId) async {
    final resp = await _dio.delete('/drafts/$draftId');
    // 204 (Body None) has no envelope to unwrap — return early.
    if (resp.statusCode == 204 || resp.data == null) return;
    unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
  }

  // ── text upload (P0007 §6.4/§7.11) ───────────────────────────────────────

  /// POST /attachments — composetext text upload(multipart/form-data, text `file`).
  /// return: §3.4 Attachment(text text). text text `attachment_id` text Body
  /// `attachment_ids` text translated text(§7.11). [onSendProgress]/[cancelToken]text
  /// translated text display·canceltext(FileForge storage upload translated text text).
  Future<MailAttachment> uploadAttachment({
    required String filename,
    required List<int> bytes,
    void Function(int, int)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final resp = await _dio.post(
      '/attachments',
      data: formData,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return MailAttachment.fromJson(expectMapData(data, httpStatus: resp.statusCode));
  }

  /// GET /files/attachment/{mailId}/{attachmentId} — attachment download (NR0003 §4).
  ///
  /// The server derives user_uuid from the auth token and returns the attachment
  /// within the owner scope (reusing the verbose `/mail/files/*` endpoint). The
  /// caller delegates the response bytes and Content-Disposition header to
  /// [DownloadSaveService.saveBytes] for saving.
  Future<Response<List<int>>> downloadAttachment({
    required String mailId,
    required String attachmentId,
    void Function(int, int)? onReceiveProgress,
    CancelToken? cancelToken,
  }) {
    return _dio.get<List<int>>(
      '/files/attachment/$mailId/$attachmentId',
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
  }
}
