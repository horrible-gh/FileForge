import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/config/env.dart';

/// R0001 후속증상 회귀가드: 미주입 기본 base URL 의 호스트가 런타임에 맞게 해석되는지.
///
/// `10.0.2.2` 는 안드로이드 에뮬레이터 전용 별칭이라 웹/데스크톱/iOS 에선 라우팅 불가
/// (`net::ERR_CONNECTION_TIMED_OUT`). 본 테스트는 `MAIL_SERVER_URL`/`SERVER_URL` 이
/// 주입되지 않은 상태(테스트 런은 dart-define 없음)에서 host 폴백을 검증한다.
///
/// VM 테스트에서는 `kIsWeb` 가 컴파일타임 false 라 웹 분기를 직접 토글할 수 없으나,
/// 웹은 비-안드로이드와 동일하게 `localhost` 를 쓰므로 "안드로이드만 10.0.2.2, 그 외 localhost"
/// 라는 핵심 불변식이 아래 두 분기로 커버된다.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('Env 미주입 기본 host 해석', () {
    test('안드로이드(비-웹): 에뮬레이터 별칭 10.0.2.2 유지', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      // 메일 폴백은 Go MailAnchor(:8090), 파일 폴백은 Python FileForge(:8000).
      expect(Env.mailServerUrl, 'http://10.0.2.2:8090/api/v1');
      expect(Env.serverUrl, 'http://10.0.2.2:8000/fileforge');
    });

    test('iOS: 라우팅 불가한 10.0.2.2 대신 localhost 로 폴백', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(Env.mailServerUrl, 'http://localhost:8090/api/v1');
      expect(Env.serverUrl, 'http://localhost:8000/fileforge');
    });

    test('데스크톱(예: macOS): localhost 로 폴백', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(Env.mailServerUrl, 'http://localhost:8090/api/v1');
      expect(Env.serverUrl, 'http://localhost:8000/fileforge');
    });

    test('어떤 런타임에서도 기본값에 에뮬레이터 별칭이 무차별로 박히지 않음', () {
      // 비-안드로이드 런타임의 기본값에는 10.0.2.2 가 등장하지 않아야 한다.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(Env.mailServerUrl.contains('10.0.2.2'), isFalse);
      expect(Env.serverUrl.contains('10.0.2.2'), isFalse);
    });

    test('T0008 회귀가드: 메일 미주입 폴백이 Python :8000(구조적 404) 을 가리키지 않음', () {
      // R0001/T0008 증상: 설정 주입 없는 빌드가 `:8000/api/v1/...` 로 404.
      // 메일 폴백은 어떤 런타임에서도 :8000 이 아니라 Go MailAnchor :8090 이어야 한다.
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(Env.mailServerUrl.contains(':8000'), isFalse,
            reason: '$platform: 메일 폴백이 Python :8000 을 가리키면 /api/v1 구조적 404');
        expect(Env.mailServerUrl.endsWith(':8090/api/v1'), isTrue);
      }
    });
  });
}
