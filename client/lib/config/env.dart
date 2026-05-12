/// 빌드 환경변수 — --dart-define-from-file 로 주입된 값만 담는다.
/// 앱 내부 상수는 app_config.dart 에 둔다.
class Env {
  /// 빌드 시 --dart-define=SERVER_URL=https://... 또는
  /// --dart-define-from-file=config/dev.json 으로 주입.
  /// 컨텍스트 경로(/fileforge)를 포함한 API base URL 전체를 설정한다 (T077).
  static const String serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'http://10.0.2.2:8000/fileforge',
  );

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
