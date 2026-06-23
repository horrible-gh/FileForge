import 'package:shared_preferences/shared_preferences.dart';

/// 계정 유무(presence) 캐시 — TR0005 §증상1(진입 지연) 낙관적 렌더용.
///
/// 진입 게이트가 매 콜드스타트마다 `GET /accounts` 응답을 기다린 뒤에야
/// 온보딩/목록을 결정하던 것이 "어카운트 작성 화면까지 너무 느리다"의 한 축이다.
/// 마지막으로 알려진 "계정이 있었나" 한 비트만 영속해 두면, 다음 진입에서 화면을
/// 즉시 그리고(스피너 제거) 네트워크는 백그라운드로 재조정할 수 있다.
///
/// 인터페이스로 추상화해 단위 테스트가 플러그인(SharedPreferences) 없이 인메모리
/// 더블로 게이트 로직을 검증하게 한다.
abstract class AccountPresenceCache {
  /// 마지막으로 알려진 계정 유무. 한 번도 기록된 적 없으면 null.
  Future<bool?> getHasAccounts();

  /// 성공적인 로드/연결/해제 후 계정 유무를 갱신한다(베스트에포트).
  Future<void> setHasAccounts(bool value);
}

/// SharedPreferences 백엔드 기본 구현(이미 pubspec 의존성).
class SharedPrefsAccountCache implements AccountPresenceCache {
  static const String _key = 'mail_has_accounts_v1';

  @override
  Future<bool?> getHasAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key);
  }

  @override
  Future<void> setHasAccounts(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
