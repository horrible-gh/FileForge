import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/mail.dart';
import '../services/mail_service.dart';
import '../services/mail_compose.dart';
import '../services/mail_envelope.dart';

/// 초안 갱신 결과 분류(§7.10) — 작성 화면이 경합/오류를 분기한다.
enum DraftUpdateStatus { saved, conflict, error }

/// 초안 갱신 결과 — saved 면 [updatedAt], conflict 면 [serverUpdatedAt] 동반.
class DraftUpdateResult {
  final DraftUpdateStatus status;
  final String? updatedAt;
  final String? serverUpdatedAt;

  const DraftUpdateResult({
    required this.status,
    this.updatedAt,
    this.serverUpdatedAt,
  });

  bool get isConflict => status == DraftUpdateStatus.conflict;
  bool get isSaved => status == DraftUpdateStatus.saved;
}

/// 메일(C) 상태 관리 Provider — NR0003 §2.3 / §7 초기 구현(읽기 슬라이스).
///
/// 책임: 목록(커서 페이지네이션)·상세·읽음 처리. FileProvider의 seq 가드
/// 패턴을 따라 stale 응답을 무시한다. 작성/라벨/계정/동기화는 후속 T.
class MailProvider extends ChangeNotifier {
  late final MailService _service;

  MailProvider(Dio dio) {
    _service = MailService(dio);
  }

  // ── 목록 상태 ──────────────────────────────────────────────────────────────
  final List<MailSummary> _mails = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  String? _nextCursor;
  bool _hasMore = false;
  String _currentLabel = 'inbox';
  int _loadSeq = 0;

  List<MailSummary> get mails => List.unmodifiable(_mails);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String get currentLabel => _currentLabel;

  // ── 상세 상태 ──────────────────────────────────────────────────────────────
  MailDetail? _detail;
  bool _detailLoading = false;
  String? _detailError;
  int _detailSeq = 0;

  MailDetail? get detail => _detail;
  bool get detailLoading => _detailLoading;
  String? get detailError => _detailError;

  // ── 목록 로드 ──────────────────────────────────────────────────────────────

  /// 첫 페이지 로드(라벨 전환 포함). 기존 목록을 비우고 새로 채운다.
  Future<void> loadInbox({String label = 'inbox'}) async {
    _currentLabel = label;
    final seq = ++_loadSeq;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _service.listMails(label: label);
      if (seq != _loadSeq) return; // stale
      _mails
        ..clear()
        ..addAll(page.items);
      _nextCursor = page.nextCursor;
      _hasMore = page.hasMore;
    } catch (e) {
      if (seq == _loadSeq) _error = _msg(e);
    } finally {
      if (seq == _loadSeq) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 당겨서 새로고침 — 현재 라벨 기준 첫 페이지 재로드.
  Future<void> refresh() => loadInbox(label: _currentLabel);

  /// 다음 묶음(커서) 로드 — 마지막 묶음이거나 이미 로딩 중이면 무시한다.
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore || _isLoading) return;
    final cursor = _nextCursor;
    if (cursor == null || cursor.isEmpty) return;
    final seq = _loadSeq; // 같은 로드 세션에서만 이어붙인다.
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _service.listMails(label: _currentLabel, cursor: cursor);
      if (seq != _loadSeq) return; // 그 사이 새로고침됨
      _mails.addAll(page.items);
      _nextCursor = page.nextCursor;
      _hasMore = page.hasMore;
    } catch (_) {
      // 추가 로드 실패는 전체 에러로 승격하지 않는다(보조 동작).
    } finally {
      if (seq == _loadSeq) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  // ── 상세 로드 ──────────────────────────────────────────────────────────────

  /// 상세 로드 후, 안읽음이면 읽음 처리(P0007 §7.3)를 자동 수행한다.
  Future<void> openMail(String mailId) async {
    final seq = ++_detailSeq;
    _detail = null;
    _detailLoading = true;
    _detailError = null;
    notifyListeners();
    try {
      final d = await _service.getMail(mailId);
      if (seq != _detailSeq) return;
      _detail = d;
      if (!d.isRead) {
        // 읽음 처리는 best-effort — 실패해도 상세 표시는 유지한다.
        markRead(mailId);
      }
    } catch (e) {
      if (seq == _detailSeq) _detailError = _msg(e);
    } finally {
      if (seq == _detailSeq) {
        _detailLoading = false;
        notifyListeners();
      }
    }
  }

  /// 읽음 처리 + 로컬 목록/상세 낙관적 갱신.
  Future<void> markRead(String mailId, {bool isRead = true}) async {
    try {
      await _service.setRead(mailId, isRead);
      final idx = _mails.indexWhere((m) => m.mailId == mailId);
      if (idx >= 0) _mails[idx] = _mails[idx].copyWithRead(isRead);
      notifyListeners();
    } catch (_) {
      // 읽음 처리 실패는 조용히 무시(다음 동기화에서 수렴).
    }
  }

  // ── 작성/발송/초안 (P0007 §7.5~§7.10) ───────────────────────────────────────

  /// 발송. 성공 시 null, 실패 시 분류된 예외를 반환한다(작성 화면이 분기).
  /// USER_ACTION(RECIPIENT_INVALID 등)은 작성 내용을 보존하라는 신호다.
  Future<MailApiException?> sendMail(SendPayload payload) async {
    try {
      await _service.sendMail(payload);
      // 보낸편지함을 보고 있었다면 새로고침(그 외에는 화면이 목록 복귀 처리).
      if (_currentLabel == 'sent') {
        await refresh();
      }
      return null;
    } on MailApiException catch (e) {
      return e;
    } catch (e) {
      return MailApiException(code: 'UNKNOWN', message: e.toString());
    }
  }

  /// 초안 저장 — 성공 시 draft_id, 실패 시 null(작성 화면이 토스트 처리).
  Future<String?> saveDraft(SendPayload payload) async {
    try {
      final d = await _service.saveDraft(payload);
      return d['draft_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// 초안 불러오기(이어쓰기) — 실패 시 null.
  Future<MailDraft?> loadDraft(String draftId) async {
    try {
      return await _service.getDraft(draftId);
    } catch (_) {
      return null;
    }
  }

  /// 초안 갱신(낙관적 경합, §7.10). DRAFT_CONFLICT 면 서버 최신 시각을 담아
  /// 작성 화면이 "재적재 안내"를 띄울 수 있게 분류 결과를 돌려준다.
  Future<DraftUpdateResult> updateDraft(
    String draftId,
    SendPayload payload,
    String baseUpdatedAt,
  ) async {
    try {
      final d = await _service.updateDraft(draftId, payload, baseUpdatedAt);
      return DraftUpdateResult(
        status: DraftUpdateStatus.saved,
        updatedAt: d['updated_at'] as String?,
      );
    } on MailApiException catch (e) {
      if (e.code == 'DRAFT_CONFLICT') {
        return DraftUpdateResult(
          status: DraftUpdateStatus.conflict,
          serverUpdatedAt: e.details?['server_updated_at'] as String?,
        );
      }
      return const DraftUpdateResult(status: DraftUpdateStatus.error);
    } catch (_) {
      return const DraftUpdateResult(status: DraftUpdateStatus.error);
    }
  }

  /// 작성용 첨부 업로드(§7.11) — 성공 시 첨부 메타, 실패 시 null.
  /// [onProgress]는 (전송, 전체) 바이트 진행률.
  Future<MailAttachment?> uploadAttachment({
    required String filename,
    required List<int> bytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      return await _service.uploadAttachment(
        filename: filename,
        bytes: bytes,
        onSendProgress: onProgress,
      );
    } catch (_) {
      return null;
    }
  }

  // ── 초기화 ────────────────────────────────────────────────────────────────

  /// 로그아웃/세션 만료 시 상태 초기화(app.dart 리셋 콜백에서 호출).
  void reset() {
    _mails.clear();
    _isLoading = false;
    _isLoadingMore = false;
    _error = null;
    _nextCursor = null;
    _hasMore = false;
    _currentLabel = 'inbox';
    _detail = null;
    _detailLoading = false;
    _detailError = null;
    notifyListeners();
  }

  String _msg(Object e) => e.toString();
}
