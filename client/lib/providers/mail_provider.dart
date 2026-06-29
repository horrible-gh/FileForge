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

  /// 활성 검색어(B0001/0026). 비어 있으면 검색 모드가 아니다. 검색 중에는
  /// [loadMore]가 같은 `q`를 유지해 다음 페이지도 검색 결과로만 채워지고, 자동 폴링/
  /// 동기화는 검색 결과를 덮어쓰지 않도록 호출부(MailListScreen)가 [isSearchMode]로
  /// 가드한다. `loadInbox`(비검색 로드)는 진입 시 이 값을 비워 상태를 일관되게 유지한다.
  String _searchQuery = '';

  List<MailSummary> get mails => List.unmodifiable(_mails);

  /// R0001(0027) — "ピン留め(고정됨)" 트레이에 채울 핀 메일들. 본 목록(`_mails`)을
  /// 핀/비핀으로 파티션해 트레이와 본문 리스트를 분리한다(핀이 시간순 목록에
  /// 묻혀 쌓이지 않고 **별도 트레이**로 모인다 — 사용자 반려 반영). 서버 통합
  /// 목록은 `ORDER BY m.is_pinned DESC`라 핀 메일이 결과 앞쪽(=첫 페이지)에 먼저
  /// 실려 들어오므로, 로드된 범위 안에서 트레이가 핀을 빠짐없이 모은다.
  List<MailSummary> get pinnedMails =>
      List.unmodifiable(mails.where((m) => m.isPinned));

  /// R0001(0027) — 트레이 아래 본문 시간순 리스트(비핀 메일만). 핀 메일은
  /// [pinnedMails] 트레이로 빠지므로 여기엔 중복되지 않는다. 공개 [mails]
  /// 게터에서 파생하므로(내부 `_mails` 직참조 아님) 서브클래스/테스트가 [mails]를
  /// 오버라이드하면 트레이/본문 파티션도 그 목록을 그대로 따른다.
  List<MailSummary> get unpinnedMails =>
      List.unmodifiable(mails.where((m) => !m.isPinned));

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSyncing => _isSyncing;

  /// 직전 동기화에서 서버가 계정을 reauth_required로 표시했는지(재인증 필요). 화면은
  /// AccountProvider의 배너로도 이를 표면화하지만, 동기화 직후 즉시 알 수 있도록 노출한다.
  bool get reauthRequired => _reauthRequired;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String get currentLabel => _currentLabel;

  /// 현재 검색 중인지(B0001/0026) — 검색어가 비어 있지 않으면 true.
  bool get isSearchMode => _searchQuery.isNotEmpty;
  String get searchQuery => _searchQuery;

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
    _searchQuery = ''; // 비검색 로드 — 이전 검색 상태를 해제한다(B0001/0026).
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
      final page = await _service.listMails(
        label: _currentLabel,
        q: _searchQuery.isEmpty ? null : _searchQuery, // 검색 중이면 다음 페이지도 검색 유지
        cursor: cursor,
      );
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

  // ── 검색(B0001/0026) ─────────────────────────────────────────────────────────

  /// 메일 검색(B0001/0026) — 현재 라벨 안에서 `q`로 서버 검색(`GET /mails?q=`)을 돌려
  /// 목록을 결과로 교체한다. 서버는 `q`를 SQL WHERE로 내려 **보관함 전체**(모든 계정·
  /// 모든 페이지)를 필터링하므로 "현재 페이지 내 검색"이 아니라 진짜 전체 검색이다.
  /// 빈 검색어는 검색을 해제한다([clearSearch]).
  Future<void> searchMails(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      await clearSearch();
      return;
    }
    _searchQuery = q;
    final seq = ++_loadSeq;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _service.listMails(label: _currentLabel, q: q);
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

  /// 검색 해제(B0001/0026) — 현재 라벨의 일반 목록으로 복귀한다(`loadInbox`가
  /// `_searchQuery`를 비운다). 이미 검색 중이 아니면 아무것도 하지 않는다.
  Future<void> clearSearch() async {
    if (_searchQuery.isEmpty) return;
    await loadInbox(label: _currentLabel);
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

  /// 핀 고정/해제(R0001/0027) — 낙관적 갱신. 토글이 즉시 UI에 반영되도록 먼저
  /// 로컬 상태를 바꾼다. 핀을 켜면 그 메일은 시간순 본문 리스트에서 빠져
  /// **"ピン留め(고정됨)" 트레이**([pinnedMails])로 즉시 이동하고, 끄면 다시
  /// 본문 리스트로 돌아온다(파티션은 [pinnedMails]/[unpinnedMails] 게터가 수행).
  /// 서버 PATCH 실패 시 토글 이전 상태(플래그+순서)를 되돌린다. 열려 있는
  /// 상세(detail)가 같은 메일이면 그 상태도 함께 맞춘다. 내부 `_mails`는 핀을
  /// 앞쪽에 모으는 안정 파티션(_resortPinned)을 유지하는데, 이는 서버
  /// `ORDER BY m.is_pinned DESC`와 같은 순서라 페이지네이션·재로딩에서 핀이
  /// 앞쪽에 일관되게 남도록 보장한다(렌더링은 트레이/본문 게터로 분리).
  Future<void> togglePin(String mailId, {bool? pinned}) async {
    final idx = _mails.indexWhere((m) => m.mailId == mailId);
    final current = idx >= 0
        ? _mails[idx].isPinned
        : (_detail?.mailId == mailId ? (_detail?.isPinned ?? false) : false);
    final next = pinned ?? !current;
    if (next == current && idx < 0 && _detail?.mailId != mailId) return;

    // 실패 시 정확히 되돌릴 수 있도록 순서/상세 상태를 스냅샷한다(되돌리기는 단순
    // 플래그 복원만으로는 부족 — _resortPinned가 이미 순서를 바꿔놨기 때문).
    final prevOrder = List<MailSummary>.from(_mails);
    final prevDetail = _detail;

    // 낙관적 적용
    if (idx >= 0) _mails[idx] = _mails[idx].copyWithPinned(next);
    if (_detail?.mailId == mailId) _detail = _detail!.copyWithPinned(next);
    _resortPinned();
    notifyListeners();

    try {
      await _service.setPinned(mailId, next);
    } catch (_) {
      // 실패 시 토글 이전 상태(플래그+순서)를 그대로 복원한다(서버 미반영).
      _mails
        ..clear()
        ..addAll(prevOrder);
      _detail = prevDetail;
      notifyListeners();
    }
  }

  /// 핀 메일을 목록 최상단으로 올리되 그룹 내 상대 순서(수신 시각순)는 보존하는
  /// 안정 정렬 — 서버의 `ORDER BY m.is_pinned DESC, m.sent_date DESC`와 동일한 시각 결과.
  void _resortPinned() {
    if (_mails.isEmpty) return;
    final pinned = <MailSummary>[];
    final rest = <MailSummary>[];
    for (final m in _mails) {
      (m.isPinned ? pinned : rest).add(m);
    }
    _mails
      ..clear()
      ..addAll(pinned)
      ..addAll(rest);
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
    _searchQuery = '';
    _detail = null;
    _detailLoading = false;
    _detailError = null;
    notifyListeners();
  }

  String _msg(Object e) => e.toString();
}
