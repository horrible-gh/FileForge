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
  List<SyncAccountError> _syncAccountErrors = const [];
  String? _error;
  String? _nextCursor;
  bool _hasMore = false;
  String _currentLabel = 'inbox';
  int _loadSeq = 0;

  /// Active search query (B0001/0026). Empty means not in search mode. While
  /// searching, [loadMore] keeps the same `q` so the next page is also filled with
  /// search results only, and the caller (MailListScreen) guards via [isSearchMode]
  /// so auto polling/sync does not overwrite the search results. `loadInbox`
  /// (non-search load) clears this value on entry to keep state consistent.
  String _searchQuery = '';

  List<MailSummary> get mails => List.unmodifiable(_mails);

  /// R0001(0027) — pinned mails to fill the "ピン留め" (pinned) tray. Partitions the
  /// main list (`_mails`) into pinned/unpinned to separate the tray from the body
  /// list (pins gather into a **separate tray** instead of piling up buried in the
  /// chronological list — reflecting user rejection feedback). The server unified
  /// list is `ORDER BY m.is_pinned DESC`, so pinned mails come in at the front of
  /// the results (= first page); thus within the loaded range the tray gathers all pins.
  List<MailSummary> get pinnedMails =>
      List.unmodifiable(mails.where((m) => m.isPinned));

  /// R0001(0027) — the chronological body list below the tray (unpinned mails only).
  /// Pinned mails go into the [pinnedMails] tray, so they are not duplicated here.
  /// Derived from the public [mails] getter (not a direct `_mails` reference), so if
  /// a subclass/test overrides [mails], the tray/body partition follows that list too.
  List<MailSummary> get unpinnedMails =>
      List.unmodifiable(mails.where((m) => !m.isPinned));

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSyncing => _isSyncing;

  /// Whether the last sync had the server mark an account reauth_required (re-auth needed).
  /// The screen also surfaces this via AccountProvider's banner, but it is exposed here so it can be known immediately after a sync.
  bool get reauthRequired => _reauthRequired;

  /// Per-account sync failures from the last sync (B0001 / NR0003 H2). Empty on a
  /// clean sync. Previously the server swallowed these silently and a flaky
  /// account just made the inbox look empty with no clue; now the screen can show
  /// a dismissible warning ("N accounts didn't sync"). Derived list is read-only.
  List<SyncAccountError> get syncAccountErrors =>
      List.unmodifiable(_syncAccountErrors);

  String? get error => _error;
  bool get hasMore => _hasMore;
  String get currentLabel => _currentLabel;

  /// Whether a search is currently active (B0001/0026) — true if the query is not empty.
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
    _searchQuery = ''; // non-search load — clears the previous search state (B0001/0026).
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

  /// Reload after syncing the inbox (R0001) — pull IMAP receipts via the server
  /// `POST /sync`, then re-read the local list (`GET /mails`). Unlike sending,
  /// **receiving is only filled when this trigger fires** (the server has no
  /// background sync worker, and the old client never called sync, so the inbox
  /// stayed empty forever).
  ///
  /// Since only the inbox is synced, sync is triggered only on the `inbox` label;
  /// other labels (sent/drafts) just reload locally. Sync is best-effort: even on
  /// failure (network/re-auth) the local mails are still shown, and if re-auth is
  /// needed it is surfaced via [reauthRequired].
  Future<void> syncInbox({String label = 'inbox', bool quiet = false}) async {
    // R0001/0039 — the 10s background poll fires a *quiet* sync. A quiet refresh
    // must NEVER reset a deeply-scrolled list back to page 1: doing so was the core
    // "scroll → refresh that fetches a few items yet takes forever" complaint (the
    // list snapped back to ~20 items every 10s, throwing away every already-loaded
    // page and the scroll position, then re-paging from the top). So a quiet sync
    // never runs while another load/search is in flight, stays invisible (no
    // full-screen spinner, no _isLoading that would also stall the user's scroll via
    // loadMore's guard), and reconciles by *merging* the fresh head into the loaded
    // list ([_mergeInboxHead]) instead of clear+reload.
    if (quiet && (_isLoading || _isLoadingMore || _isSyncing || isSearchMode)) {
      return;
    }
    if (label == 'inbox' && !_isSyncing) {
      _isSyncing = true;
      if (!quiet) _isLoading = true; // full-screen spinner span only for explicit refresh
      _error = null;
      notifyListeners();
      try {
        final r = await _service.triggerSync();
        _reauthRequired = r.reauthRequired;
        // H2: surface per-account failures instead of swallowing them. The whole
        // sync still succeeded HTTP-wise (best-effort), but individual accounts may
        // have failed; keep that visible until the next clean sync clears it.
        _syncAccountErrors = r.accountErrors;
      } catch (_) {
        // best-effort: silently ignore a *whole-request* sync failure and proceed
        // to load the local list (network down, etc.). Per-account errors above are
        // a separate, surfaced channel.
      } finally {
        _isSyncing = false;
      }
    }
    if (quiet) {
      await _mergeInboxHead(label: label);
    } else {
      await loadInbox(label: label);
    }
  }

  /// R0001/0039 — reconcile the freshest server page into the *head* of the already
  /// loaded list without resetting pagination. Used only by the quiet background
  /// poll. Unlike [loadInbox] it does not `clear()` the whole list or rewind the
  /// cursor: it replaces the head with the server's fresh first page (so new mail
  /// and read/pin flag changes show up), and keeps every already-loaded deeper page
  /// as the tail — so the user's scroll position and load-more cursor survive a
  /// background refresh. On an empty/failed fetch the current list is left intact.
  Future<void> _mergeInboxHead({String label = 'inbox'}) async {
    // A concurrent explicit reload/search may have started during the POST /sync
    // await above; do not clobber it.
    if (isSearchMode || _isLoading) {
      notifyListeners();
      return;
    }
    try {
      final page = await _service.listMails(label: label);
      final fresh = page.items;
      if (fresh.isNotEmpty) {
        final freshIds = {for (final m in fresh) m.mailId};
        // Everything already loaded that the fresh first page does not cover = the
        // deeper pages (2..N) the user scrolled into. Keep them, in order, as the tail.
        final tail = _mails.where((m) => !freshIds.contains(m.mailId)).toList();
        _mails
          ..clear()
          ..addAll(fresh)
          ..addAll(tail);
      }
      // Keep the deep cursor from the last loadMore so continued scrolling still
      // advances; only seed pagination from page 1 if nothing has been paged yet.
      if (_nextCursor == null || _nextCursor!.isEmpty) {
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
      }
    } catch (_) {
      // best-effort: keep the currently displayed list on a failed refresh.
    } finally {
      notifyListeners();
    }
  }

  /// Called on pull-to-refresh / inbox entry — [syncInbox] with the current label.
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
        q: _searchQuery.isEmpty ? null : _searchQuery, // keep search on the next page too while searching
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

  // ── search (B0001/0026) ──────────────────────────────────────────────────────

  /// Mail search (B0001/0026) — runs a server search by `q` within the current
  /// label (`GET /mails?q=`) and replaces the list with the results. The server
  /// pushes `q` down to SQL WHERE to filter the **entire mailbox** (all accounts,
  /// all pages), so it is a true full search, not a "search within the current page".
  /// An empty query clears the search ([clearSearch]).
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

  /// Clear search (B0001/0026) — return to the current label's normal list (`loadInbox`
  /// clears `_searchQuery`). Does nothing if not already searching.
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

  /// Download an attachment (NR0003 §4) — passes the response bytes/headers straight
  /// to the screen to be saved via [DownloadSaveService]. Does not change provider state.
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

  /// Mark all read (R0001/0030) — "메일 전체 읽음처리". Asks the server to flip
  /// every unread mail in the user's mailboxes to read, then reflects it locally
  /// by setting `isRead = true` on every loaded summary (and the open detail, if
  /// any) so the bold/dot unread cue clears immediately without a full reload.
  /// Returns the number the server reported as updated (0 = nothing was unread).
  /// On failure local state is left untouched and -1 is returned so the caller can
  /// surface an error toast. The change is persisted server-side, so the 10s inbox
  /// poll (loadInbox) will not revert it.
  Future<int> markAllRead() async {
    try {
      final updated = await _service.markAllRead();
      var changed = false;
      for (var i = 0; i < _mails.length; i++) {
        if (!_mails[i].isRead) {
          _mails[i] = _mails[i].copyWithRead(true);
          changed = true;
        }
      }
      if (_detail != null && !_detail!.isRead) {
        _detail = _detail!.copyWithRead(true);
        changed = true;
      }
      if (changed || updated > 0) notifyListeners();
      return updated;
    } catch (_) {
      return -1;
    }
  }

  /// Pin/unpin (R0001/0027) — optimistic update. Changes local state first so the
  /// toggle reflects in the UI immediately. Turning a pin on removes that mail from
  /// the chronological body list and moves it at once into the **"ピン留め" (pinned)
  /// tray** ([pinnedMails]); turning it off returns it to the body list (the
  /// partition is done by the [pinnedMails]/[unpinnedMails] getters). On a server
  /// PATCH failure the pre-toggle state (flag + order) is rolled back. If the open
  /// detail is the same mail, its state is aligned too. Internal `_mails` keeps a
  /// stable partition (_resortPinned) that gathers pins at the front, matching the
  /// server `ORDER BY m.is_pinned DESC`, so pins stay consistently at the front
  /// across pagination/reload (rendering is split via the tray/body getters).
  Future<void> togglePin(String mailId, {bool? pinned}) async {
    final idx = _mails.indexWhere((m) => m.mailId == mailId);
    final current = idx >= 0
        ? _mails[idx].isPinned
        : (_detail?.mailId == mailId ? (_detail?.isPinned ?? false) : false);
    final next = pinned ?? !current;
    if (next == current && idx < 0 && _detail?.mailId != mailId) return;

    // Snapshot order/detail state so we can roll back exactly on failure (a simple
    // flag restore is not enough — _resortPinned has already reordered the list).
    final prevOrder = List<MailSummary>.from(_mails);
    final prevDetail = _detail;

    // optimistic apply
    if (idx >= 0) _mails[idx] = _mails[idx].copyWithPinned(next);
    if (_detail?.mailId == mailId) _detail = _detail!.copyWithPinned(next);
    _resortPinned();
    notifyListeners();

    try {
      await _service.setPinned(mailId, next);
    } catch (_) {
      // On failure, restore the pre-toggle state (flag + order) exactly (server not updated).
      _mails
        ..clear()
        ..addAll(prevOrder);
      _detail = prevDetail;
      notifyListeners();
    }
  }

  /// Stable sort that raises pinned mails to the top of the list while preserving
  /// the relative order within each group (by received time) — visually identical
  /// to the server's `ORDER BY m.is_pinned DESC, m.sent_date DESC`.
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
    _syncAccountErrors = const [];
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
