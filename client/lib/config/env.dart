import 'package:flutter/foundation.dart';

/// 빌드 환경변수 — --dart-define-from-file 로 주입된 값만 담는다.
/// 앱 내부 상수는 app_config.dart 에 둔다.
class Env {
  /// 주입된 SERVER_URL(미주입 시 빈 문자열). 주입되면 그대로 사용한다.
  static const String _serverUrlOverride = String.fromEnvironment('SERVER_URL');

  /// 주입된 MAIL_SERVER_URL(미주입 시 빈 문자열).
  static const String _mailServerUrlOverride = String.fromEnvironment(
    'MAIL_SERVER_URL',
  );

  /// 미주입 기본값의 호스트.
  ///
  /// `10.0.2.2` 는 **안드로이드 에뮬레이터 전용** 별칭(에뮬레이터→호스트 loopback)이라
  /// 웹/데스크톱/iOS 런타임에서는 라우팅 불가다. 그 런타임에서 이 값을 기본으로 쓰면
  /// `net::ERR_CONNECTION_TIMED_OUT` 로 모든 호출이 타임아웃된다(R0001 후속증상의
  /// 실측 트리거: 웹 빌드가 `10.0.2.2:8000/api/v1/accounts/oauth/authorize` 타임아웃).
  /// 따라서 안드로이드(비-웹)만 `10.0.2.2`, 그 외(웹·데스크톱·iOS)는 `localhost` 로 폴백한다.
  /// `--dart-define` 으로 명시 주입한 값은 항상 우선한다.
  static String get _defaultHost {
    if (kIsWeb) return 'localhost';
    return defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
  }

  /// 파일 API base URL. 빌드 시 --dart-define=SERVER_URL=https://... 또는
  /// --dart-define-from-file=config/dev.json 으로 주입.
  /// 컨텍스트 경로(/fileforge)를 포함한 API base URL 전체를 설정한다 (T077).
  static String get serverUrl => _serverUrlOverride.isNotEmpty
      ? _serverUrlOverride
      : 'http://$_defaultHost:8000/fileforge';

  /// MailAnchor(Go 서비스) API base URL — P0007 §표기 규칙의 `https://{host}/api/v1`.
  /// 흡수 아키텍처(NR0003 §1)에서 메일은 별도 Go 백엔드가 담당하므로 파일 API와
  /// 분리한다. 리버스 프록시 단일 origin 구성 시에도 경로 프리픽스가 다르므로
  /// 별도 base URL로 둔다. 빌드 시 --dart-define=MAIL_SERVER_URL=... 로 주입.
  ///
  /// ★ 미주입 폴백 포트 = **8090** (Go MailAnchor), `:8000` (Python FileForge) 아님.
  /// `:8000` 은 FastAPI 가 `/fileforge/*` 프리픽스만 마운트하므로 `/api/v1/*` 메일
  /// 라우트가 **구조적으로 항상 404** 다(R0001·T0008 의 `localhost:8000/api/v1/
  /// accounts/oauth/authorize 404` 가 정확히 이 폴백 때문). `String.fromEnvironment`
  /// 는 컴파일타임 상수라 `--dart-define-from-file=config/dev.json` 없이 빌드/실행하면
  /// override 가 빈 문자열이 되어 이 기본값으로 떨어진다. 따라서 설정 주입이 누락된
  /// dev 빌드라도 메일 API 가 살아있는 Go 백엔드(:8090)에 도달하도록 폴백 포트를
  /// 8090 으로 둔다(파일 API 폴백은 Python 이므로 :8000/fileforge 유지). prod 는
  /// 항상 prod.json(`https://.../api/v1`)을 주입하므로 이 폴백을 타지 않는다.
  static String get mailServerUrl => _mailServerUrlOverride.isNotEmpty
      ? _mailServerUrlOverride
      : 'http://$_defaultHost:8090/api/v1';

  /// 로그 최소 레벨: debug | info | warn | error
  static const String logLevel = String.fromEnvironment(
    'LOG_LEVEL',
    defaultValue: 'debug',
  );

  /// 공유 링크 base URL — /share/{token} 앞에 붙는 출처.
  /// 빌드 시 SHARE_BASE_URL 로 주입. 미주입 시 개발 기본값 사용.
  static const String shareBaseUrl = String.fromEnvironment(
    'SHARE_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// 콘솔 출력 여부 (release 환경에서는 false 로 주입)
  static const bool logConsole = bool.fromEnvironment(
    'LOG_CONSOLE',
    defaultValue: true,
  );

  /// 파일 출력 여부
  static const bool logFile = bool.fromEnvironment(
    'LOG_FILE',
    defaultValue: true,
  );
}
