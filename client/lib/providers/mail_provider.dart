import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/mail.dart';
import '../services/mail_service.dart';
import '../services/mail_compose.dart';
import '../services/mail_envelope.dart';

/// Draft refresh result minutestext(§7.10) — compose screentext text/errortext branchtext.
enum DraftUpdateStatus { saved, conflict, error }

/// Draft refresh result — saved text [updatedAt], conflict text [serverUpdatedAt] text.
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

/// text(C) state management Provider — NR0003 §2.3 / §7 initial implementation(text translated text).
///
/// text: text(text translated text)·text·text text. FileProvidertext seq guard
/// translated text text stale translated text translated text. compose/text/account/synctext text T.
class MailProvider extends ChangeNotifier {
  late final MailService _service;

  MailProvider(Dio dio) {
    _service = MailService(dio);
  }

  // ── text state ──────────────────────────────────────────────────────────────
  final List<MailSummary> _mails = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isSyncing = false;
  bool _reauthRequired = false;
  String? _error;
  String? _nextCursor;
  bool _hasMore = false;
  String _currentLabel = 'inbox';
  int _loadSeq = 0;

  List<MailSummary> get mails => List.unmodifiable(_mails);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSyncing => _isSyncing;

  /// 직전 동기화에서 서버가 계정을 reauth_required로 표시했는지(재인증 필요). 화면은
  /// AccountProvider의 배너로도 이를 표면화하지만, 동기화 직후 즉시 알 수 있도록 노출한다.
  bool get reauthRequired => _reauthRequired;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String get currentLabel => _currentLabel;

  // ── text state ──────────────────────────────────────────────────────────────
  MailDetail? _detail;
  bool _detailLoading = false;
  String? _detailError;
  int _detailSeq = 0;

  MailDetail? get detail => _detail;
  bool get detailLoading => _detailLoading;
  String? get detailError => _detailError;

  // ── text text ──────────────────────────────────────────────────────────────

  /// text translated text text(text text text). text translated text translated text text translated text.
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

  /// translated text translated text — current text text text translated text translated text.
  Future<void> refresh() => loadInbox(label: _currentLabel);

  /// 받은편지함 동기화 후 재로딩(R0001) — 서버 `POST /sync`로 IMAP 수신을 끌어온 뒤
  /// 로컬 목록(`GET /mails`)을 다시 읽는다. 송신과 달리 **수신은 이 트리거가 있어야**
  /// 채워진다(서버에 백그라운드 동기화 워커가 없고, 기존 클라이언트는 sync를 전혀
  /// 호출하지 않아 받은편지함이 영영 비어 있었다).
  ///
  /// 동기화 대상은 받은편지함뿐이므로 `inbox` 라벨에서만 sync를 트리거하고, 그 외
  /// 라벨(sent/drafts)은 로컬 재로딩만 한다. 동기화는 best-effort: 실패(네트워크/재인증)
  /// 해도 로컬 메일은 그대로 보여주며, 재인증이 필요하면 [reauthRequired]로 표면화한다.
  Future<void> syncInbox({String label = 'inbox'}) async {
    if (label == 'inbox' && !_isSyncing) {
      _isSyncing = true;
      _isLoading = true; // 동기화~재로딩 전체 구간 동안 스피너 유지
      _error = null;
      notifyListeners();
      try {
        final r = await _service.triggerSync();
        _reauthRequired = r.reauthRequired;
      } catch (_) {
        // best-effort: 동기화 실패는 조용히 무시하고 로컬 목록 로드로 진행.
      } finally {
        _isSyncing = false;
      }
    }
    await loadInbox(label: label);
  }

  /// 당겨서 새로고침 / 받은편지함 진입 시 호출 — current 라벨로 [syncInbox].
  Future<void> syncRefresh() => syncInbox(label: _currentLabel);

  /// text text(text) text — translated text translated text text loading translated text translated text.
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore || _isLoading) return;
    final cursor = _nextCursor;
    if (cursor == null || cursor.isEmpty) return;
    final seq = _loadSeq; // text text sessiontranslated text translated text.
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _service.listMails(label: _currentLabel, cursor: cursor);
      if (seq != _loadSeq) return; // text text translated text
      _mails.addAll(page.items);
      _nextCursor = page.nextCursor;
      _hasMore = page.hasMore;
    } catch (_) {
      // add text failedtext text errortext translated text translated text(text text).
    } finally {
      if (seq == _loadSeq) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  // ── text text ──────────────────────────────────────────────────────────────

  /// text text text, translated text text text(P0007 §7.3)text text translated text.
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
        // text translated text best-effort — failedtext text displaytext keeptext.
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

  /// 첨부파일 다운로드(NR0003 §4) — 응답 바이트/헤더를 그대로 화면에 전달해
  /// [DownloadSaveService]로 저장하도록 한다. provider 상태는 바꾸지 않는다.
  Future<Response<List<int>>> downloadAttachment({
    required String mailId,
    required String attachmentId,
  }) {
    return _service.downloadAttachment(
      mailId: mailId,
      attachmentId: attachmentId,
    );
  }

  /// text text + local text/text translated text refresh.
  Future<void> markRead(String mailId, {bool isRead = true}) async {
    try {
      await _service.setRead(mailId, isRead);
      final idx = _mails.indexWhere((m) => m.mailId == mailId);
      if (idx >= 0) _mails[idx] = _mails[idx].copyWithRead(isRead);
      notifyListeners();
    } catch (_) {
      // text text failedtext translated text text(text synctext text).
    }
  }

  // ── compose/text/Draft (P0007 §7.5~§7.10) ───────────────────────────────────────

  /// text. success text null, failed text minutestext exampletext returntext(compose screentext branch).
  /// USER_ACTION(RECIPIENT_INVALID text)text compose contenttext preservedtranslated text translated text.
  Future<MailApiException?> sendMail(SendPayload payload) async {
    try {
      await _service.sendMail(payload);
      // Senttext text translated text translated text(text translated text screentext text text text).
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

  /// Draft save — success text draft_id, failed text null(compose screentext toast text).
  Future<String?> saveDraft(SendPayload payload) async {
    try {
      final d = await _service.saveDraft(payload);
      return d['draft_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Draft load(translated text) — failed text null.
  Future<MailDraft?> loadDraft(String draftId) async {
    try {
      return await _service.getDraft(draftId);
    } catch (_) {
      return null;
    }
  }

  /// Draft refresh(translated text text, §7.10). DRAFT_CONFLICT text server text translated text text
  /// compose screentext "translated text text"text text text text minutestext resulttext translated text.
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

  /// composetext text upload(§7.11) — success text text text, failed text null.
  /// [onProgress]text (text, text) bytes translated text.
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

  // ── initialize ────────────────────────────────────────────────────────────────

  /// logout/session expired text state initialize(app.dart text translated text text).
  void reset() {
    _mails.clear();
    _isLoading = false;
    _isLoadingMore = false;
    _isSyncing = false;
    _reauthRequired = false;
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
