import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/mail_account.dart';
import '../services/account_cache.dart';
import '../services/account_service.dart';
import '../services/mail_envelope.dart';

/// account translated text text state — text text translated text(NR0003 §5.5)text branchtext.
///
///  - [unknown]  : text text text text text text(text) — translated text.
///  - [loading]  : text text text text — translated text.
///  - [ready]    : text complete([accounts] text text). 0text translated text, ≥1text inbox.
///  - [error]    : textaccounttext translated text "text" lookup failed(translated text text) — retry.
enum AccountGateState { unknown, loading, ready, error }

/// [AccountGateState.error] text text textminutes — NR0004 §4 (translated text translated text).
///
/// account "text failed"text text text translated text text text translated text translated text text screentext
/// translated text. 401/403 text text account translated text translated text **session text**(textlogin)text,
/// translated text·text errortext translated text retry translated text — text text text translated text text text.
///
///  - [session]   : 401/403 text authentication text — "again login" text.
///  - [transient] : translated text·text·text — translated text retry(text text keep).
enum AccountLoadErrorKind { session, transient }

/// text account(M) state management Provider — NR0003 §5.3.
///
/// text: translated text account text text(text translated text)·account add(OAuth text)·text.
/// MailProvider text translated text MailApiClient Dio text translated text text session tokentext text.
class AccountProvider extends ChangeNotifier {
  late final AccountService _service;
  final AccountPresenceCache? _cache;

  AccountProvider(Dio dio, {AccountPresenceCache? cache}) : _cache = cache {
    _service = AccountService(dio);
  }

  final List<MailAccount> _accounts = [];
  AccountGateState _gate = AccountGateState.unknown;
  String? _error;
  AccountLoadErrorKind? _errorKind;
  int _loadSeq = 0;

  /// text translated text(translated text) success text. true text [hasAccounts]text text translated text translated text.
  bool _realLoaded = false;

  /// translated text text translated text text translated text account text(TR0005 §symptom1). null text translated text.
  bool? _optimisticHasAccounts;

  List<MailAccount> get accounts => List.unmodifiable(_accounts);
  AccountGateState get gate => _gate;
  String? get error => _error;

  /// [gate]==error text text text textminutes(NR0004 §4) — screentext session(textlogin) vs
  /// text error(translated text retry)text branchtext. error text translated text null.
  AccountLoadErrorKind? get errorKind => _errorKind;

  /// translated text text: accounttext 1text and abovetext. translated text translated text text text translated text text
  /// (TR0005 §symptom1 — text text text translated text/text branch, translated text text).
  bool get hasAccounts =>
      _realLoaded ? _accounts.isNotEmpty : (_optimisticHasAccounts ?? false);

  /// text translated text translated text translated text(text screentext translated text vs screen branch). translated text translated text
  /// text(primeFromCache)text translated text ready text text text translated text text translated text.
  bool get isResolved => _gate == AccountGateState.ready;

  /// translated text "translated text account text"text translated text translated text translated text(TR0005 §symptom1).
  ///
  /// text text(text unknown) + translated text text text translated text, [gate]=ready text text
  /// screentext translated text text text text translated text/translated text translated text text. returntext translated text
  /// translated text translated text translated text(=translated text translated text inbox textloadingtext text) text.
  Future<bool> primeFromCache() async {
    if (_cache == null || _gate != AccountGateState.unknown) return false;
    final cached = await _cache.getHasAccounts();
    if (cached == null || _gate != AccountGateState.unknown) return false;
    _optimisticHasAccounts = cached;
    _gate = AccountGateState.ready;
    notifyListeners();
    return true;
  }

  /// translated text account translated text translated text(text translated text 1text text). stale translated text translated text.
  /// successtext [gate]=ready text text screentext 0text=translated text / ≥1text=inbox text branchtext.
  ///
  /// text ready(text text text)text translated text translated text text translated text translated text text
  /// (TR0005 §symptom1 — text text translated text text). text errortext translated text failedtext, text
  /// statetext text translated text translated text text text(stale) screentext keeptext.
  Future<void> load() async {
    final seq = ++_loadSeq;
    final wasOptimisticReady = _gate == AccountGateState.ready && !_realLoaded;
    if (_gate != AccountGateState.ready) {
      _gate = AccountGateState.loading;
      notifyListeners();
    }
    _error = null;
    _errorKind = null;
    try {
      final list = await _service.listAccounts();
      if (seq != _loadSeq) return; // stale
      _accounts
        ..clear()
        ..addAll(list);
      _realLoaded = true;
      _optimisticHasAccounts = null;
      _gate = AccountGateState.ready;
      await _cache?.setHasAccounts(list.isNotEmpty);
    } catch (e) {
      if (seq == _loadSeq) {
        final kind = _classifyLoadError(e);
        // text state(translated text ready)text text errortext screentext keep(stale)text.
        // session(401/403) errortext translated text textlogin translated text text error text text.
        if (wasOptimisticReady && kind == AccountLoadErrorKind.transient) {
          // keep optimistic view
        } else {
          _error = _msg(e);
          _errorKind = kind;
          _gate = AccountGateState.error;
        }
      }
    } finally {
      if (seq == _loadSeq) notifyListeners();
    }
  }

  /// provider OAuth consent URL text translated text(TR0005 §symptom2 — browser translated text).
  /// success text (url, null), failed text (null, minutestext exampletext)text returntext.
  Future<({String? url, MailApiException? error})> oauthAuthorizeUrl(
      String provider) async {
    try {
      final url = await _service.authorizeUrl(provider);
      return (url: url, error: null);
    } on MailApiException catch (e) {
      return (url: null, error: e);
    } catch (e) {
      return (url: null, error: MailApiException(code: 'UNKNOWN', message: e.toString()));
    }
  }

  /// account text failedtext session(textlogin) vs text errortext minutestranslated text(NR0004 §4·§2).
  ///
  /// server translated text textaccounttext 200 `[]` text translated text text translated text — text translated text text
  /// "text" failedtranslated text. `AccountService` text `validateStatus:true` text translated text 401/403
  /// text DioException text translated text httpStatus text text [MailApiException] text text.
  /// translated text text(text None)text DioException(text text)text text transient text text.
  static AccountLoadErrorKind _classifyLoadError(Object e) {
    if (e is MailApiException) {
      if (e.httpStatus == 401 || e.httpStatus == 403) {
        return AccountLoadErrorKind.session;
      }
      if (e.category == MailErrorCategory.auth ||
          e.category == MailErrorCategory.refreshable) {
        return AccountLoadErrorKind.session;
      }
    }
    if (e is DioException && (e.response?.statusCode == 401 ||
        e.response?.statusCode == 403)) {
      return AccountLoadErrorKind.session;
    }
    return AccountLoadErrorKind.transient;
  }

  /// account add — provider translated text text auth_code text servertext translated text.
  /// success text translated text text translated text null, failed text minutestext exampletext returntext
  /// (text screentext code text branch: oauth not configured / conflict / validation).
  Future<MailApiException?> connect({
    required String provider,
    required String authCode,
  }) async {
    try {
      final account =
          await _service.connectAccount(provider: provider, authCode: authCode);
      _accounts.add(account);
      _realLoaded = true;
      _optimisticHasAccounts = null;
      _gate = AccountGateState.ready;
      await _cache?.setHasAccounts(true);
      notifyListeners();
      return null;
    } on MailApiException catch (e) {
      return e;
    } catch (e) {
      return MailApiException(code: 'UNKNOWN', message: e.toString());
    }
  }

  /// account text — success text translated text translated text true.
  Future<bool> remove(String accountId) async {
    try {
      await _service.deleteAccount(accountId);
      _accounts.removeWhere((a) => a.accountId == accountId);
      await _cache?.setHasAccounts(_accounts.isNotEmpty);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// logout/session expired text initialize(app.dart text translated text text).
  void reset() {
    _accounts.clear();
    _gate = AccountGateState.unknown;
    _error = null;
    _errorKind = null;
    _realLoaded = false;
    _optimisticHasAccounts = null;
    notifyListeners();
  }

  String _msg(Object e) =>
      e is MailApiException ? e.message : e.toString();
}
