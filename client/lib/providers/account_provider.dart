import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/mail_account.dart';
import '../services/account_cache.dart';
import '../services/account_service.dart';
import '../services/mail_envelope.dart';

/// 계정 게이트 로드 상태 — 메일 진입 게이트(NR0003 §5.5)가 분기한다.
///
///  - [unknown]  : 아직 한 번도 확인 안 함(초기) — 스피너.
///  - [loading]  : 첫 확인 진행 중 — 스피너.
///  - [ready]    : 확인 완료([accounts] 가 진실). 0개면 온보딩, ≥1개면 inbox.
///  - [error]    : 무계정이 아니라 "진짜" 조회 실패(네트워크 등) — 재시도.
enum AccountGateState { unknown, loading, ready, error }

/// [AccountGateState.error] 의 원인 구분 — NR0004 §4 (썬더버드 패리티).
///
/// 계정 "읽기 실패"를 전부 한 덩어리로 막던 것이 사용자가 화내던 차단 화면의
/// 근원이었다. 401/403 은 메일 계정 부재가 아니라 **세션 문제**(재로그인)이고,
/// 네트워크·일시 오류는 인라인 재시도 대상이다 — 둘 다 앱을 블랙아웃하면 안 된다.
///
///  - [session]   : 401/403 또는 인증 범주 — "다시 로그인" 신호.
///  - [transient] : 네트워크·일시·기타 — 인라인 재시도(앱 셸은 유지).
enum AccountLoadErrorKind { session, transient }

/// 메일 계정(M) 상태 관리 Provider — NR0003 §5.3.
///
/// 책임: 연결된 계정 목록 로드(진입 게이트)·계정 추가(OAuth 교환)·해제.
/// MailProvider 와 동일한 MailApiClient Dio 를 공유하여 같은 세션 토큰을 탄다.
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

  /// 첫 실로드(네트워크) 성공 여부. true 면 [hasAccounts]가 실제 목록을 따른다.
  bool _realLoaded = false;

  /// 실로드 전 캐시로 띄운 낙관적 계정 유무(TR0005 §증상1). null 이면 미사용.
  bool? _optimisticHasAccounts;

  List<MailAccount> get accounts => List.unmodifiable(_accounts);
  AccountGateState get gate => _gate;
  String? get error => _error;

  /// [gate]==error 일 때의 원인 구분(NR0004 §4) — 화면이 세션(재로그인) vs
  /// 일시 오류(인라인 재시도)로 분기한다. error 가 아니면 null.
  AccountLoadErrorKind? get errorKind => _errorKind;

  /// 게이트 판정: 계정이 1개 이상인가. 실로드 전에는 캐시 기반 낙관값을 쓴다
  /// (TR0005 §증상1 — 콜드 진입 즉시 온보딩/목록 분기, 스피너 제거).
  bool get hasAccounts =>
      _realLoaded ? _accounts.isNotEmpty : (_optimisticHasAccounts ?? false);

  /// 한 번이라도 확인이 끝났는지(메일 화면이 스피너 vs 화면 분기). 캐시로 낙관적
  /// 해소(primeFromCache)된 경우에도 ready 로 보아 첫 프레임을 바로 그린다.
  bool get isResolved => _gate == AccountGateState.ready;

  /// 캐시된 "마지막 계정 유무"로 게이트를 낙관적으로 해소한다(TR0005 §증상1).
  ///
  /// 진입 직후(아직 unknown) + 캐시값이 있을 때만 동작하며, [gate]=ready 로 두어
  /// 화면이 네트워크 응답 전에 즉시 온보딩/목록을 그리게 한다. 반환값은 실제로
  /// 낙관적 해소를 했는지(=호출부가 낙관적 inbox 선로딩을 할지) 여부.
  Future<bool> primeFromCache() async {
    if (_cache == null || _gate != AccountGateState.unknown) return false;
    final cached = await _cache.getHasAccounts();
    if (cached == null || _gate != AccountGateState.unknown) return false;
    _optimisticHasAccounts = cached;
    _gate = AccountGateState.ready;
    notifyListeners();
    return true;
  }

  /// 연결된 계정 목록을 로드한다(진입 게이트의 1차 호출). stale 응답은 무시한다.
  /// 성공하면 [gate]=ready 로 두어 화면이 0개=온보딩 / ≥1개=inbox 로 분기한다.
  ///
  /// 이미 ready(캐시 낙관 해소)면 스피너로 되돌리지 않고 백그라운드 재조정만 한다
  /// (TR0005 §증상1 — 낙관 렌더 깜빡임 방지). 일시 오류로 재조정이 실패해도, 낙관
  /// 상태가 살아 있으면 블랙아웃하지 않고 직전(stale) 화면을 유지한다.
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
        // 낙관 상태(미실로드 ready)에서 일시 오류면 화면을 유지(stale)한다.
        // 세션(401/403) 오류는 낙관이어도 재로그인 안내를 위해 error 로 승격.
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

  /// 제공자 OAuth 동의 URL 을 가져온다(TR0005 §증상2 — 브라우저 런처용).
  /// 성공 시 (url, null), 실패 시 (null, 분류된 예외)를 반환한다.
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

  /// 계정 읽기 실패를 세션(재로그인) vs 일시 오류로 분류한다(NR0004 §4·§2).
  ///
  /// 서버 계약상 무계정은 200 `[]` 라 여기까지 오지 않는다 — 여기 도달하는 건
  /// "진짜" 실패뿐이다. `AccountService` 가 `validateStatus:true` 로 받기에 401/403
  /// 은 DioException 이 아니라 httpStatus 를 실은 [MailApiException] 으로 온다.
  /// 네트워크 단절(응답 없음)만 DioException(또는 기타)로 와서 transient 가 된다.
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

  /// 계정 추가 — provider 동의로 받은 auth_code 를 서버가 교환한다.
  /// 성공 시 목록에 즉시 반영하고 null, 실패 시 분류된 예외를 반환한다
  /// (연결 화면이 code 로 분기: oauth not configured / conflict / validation).
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

  /// 계정 해제 — 성공 시 목록에서 제거하고 true.
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

  /// 로그아웃/세션 만료 시 초기화(app.dart 리셋 콜백에서 호출).
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
