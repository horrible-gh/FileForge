import 'package:dio/dio.dart';
import '../models/mail.dart';
import 'mail_compose.dart';
import 'mail_envelope.dart';

/// MailAnchor 메일(C) API 래퍼 — P0007 §6.2 메일 엔드포인트.
///
/// 초기 구현 범위(NR0003 §7): 읽기 슬라이스 — 목록/상세/읽음 처리.
/// 작성·초안·첨부·라벨·계정·동기화는 상세 구현(후속 T)에서 추가한다.
/// 인증 토큰은 MailApiClient 인터셉터가 주입한다.
class MailService {
  final Dio _dio;

  MailService(this._dio);

  /// GET /mails — 메일 목록(라벨·검색·읽음 필터, 커서). P0007 §6.2/§7.1/§4.
  /// 빈 값은 쿼리에 싣지 않는다.
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

  /// GET /mails/{mail_id} — 메일 상세. P0007 §6.2/§7.3.
  Future<MailDetail> getMail(String mailId) async {
    final resp = await _dio.get('/mails/$mailId');
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return MailDetail.fromJson(expectMapData(data, httpStatus: resp.statusCode));
  }

  /// PATCH /mails/{mail_id} — 읽음 여부 변경. P0007 §6.2/§7.3.
  Future<void> setRead(String mailId, bool isRead) async {
    final resp = await _dio.patch(
      '/mails/$mailId',
      data: {'is_read': isRead},
    );
    unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
  }

  // ── 작성/발송/초안 (P0007 §6.2/§7.5~§7.10) ───────────────────────────────────

  /// POST /mails — 새/답장/전달 발송. 발송 결과(mail_id 등)를 반환한다(§7.5).
  Future<Map<String, dynamic>> sendMail(SendPayload payload) async {
    final resp = await _dio.post('/mails', data: payload.toJson());
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return expectMapData(data, httpStatus: resp.statusCode);
  }

  /// POST /drafts — 초안 저장. 반환: { draft_id, updated_at } (§7.9).
  Future<Map<String, dynamic>> saveDraft(SendPayload payload) async {
    final resp = await _dio.post('/drafts', data: payload.toJson());
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return expectMapData(data, httpStatus: resp.statusCode);
  }

  /// GET /drafts/{draft_id} — 초안 불러오기(이어쓰기, §6.2/§7.9).
  Future<MailDraft> getDraft(String draftId) async {
    final resp = await _dio.get('/drafts/$draftId');
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return MailDraft.fromJson(expectMapData(data, httpStatus: resp.statusCode));
  }

  /// PUT /drafts/{draft_id} — 초안 갱신(낙관적 경합 base_updated_at, §7.10).
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

  /// DELETE /drafts/{draft_id} — 초안 삭제.
  Future<void> deleteDraft(String draftId) async {
    final resp = await _dio.delete('/drafts/$draftId');
    // 204(본문 없음)면 봉투가 없을 수 있다 — 그 경우 통과.
    if (resp.statusCode == 204 || resp.data == null) return;
    unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
  }

  // ── 첨부 업로드 (P0007 §6.4/§7.11) ───────────────────────────────────────

  /// POST /attachments — 작성용 첨부 업로드(multipart/form-data, 필드 `file`).
  /// 반환: §3.4 Attachment(첨부 메타). 발송 시 `attachment_id` 를 본문
  /// `attachment_ids` 에 포함한다(§7.11). [onSendProgress]/[cancelToken]은
  /// 진행률 표시·취소용(FileForge storage upload 패턴과 동일).
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
}
