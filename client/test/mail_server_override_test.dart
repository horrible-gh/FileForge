import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/config/env.dart';
import 'package:file_forge_app/providers/auth_provider.dart';
import 'package:file_forge_app/services/mail_api_client.dart';

/// B0001 / NR0003 §3 regression guard — 런타임 서버 주소 오버라이드가 메일 Dio에도
/// 전파되어야 한다.
///
/// 결함: 사용자가 설정에서 서버 주소를 바꾸면 파일 API Dio만 따라가고 메일 Dio는
/// 빌드에 박힌 `mailBaseUrl`(기본 localhost)에 고정 → `GET /mail/accounts`가 엉뚱한
/// 서버로 가서 빈 목록 → "구글 연동하라". 웹은 두 Dio가 같은 origin이라 정상.
/// 수정: MailApiClient.setBaseUrl + AuthProvider.setServerUrl 전파.
void main() {
  group('MailApiClient.setBaseUrl 정규화', () {
    test('host:port → /fileforge/mail 부착', () {
      final c = MailApiClient();
      c.setBaseUrl('192.168.0.250:8000');
      expect(c.dio.options.baseUrl, 'http://192.168.0.250:8000/fileforge/mail');
    });

    test('스킴 포함 host:port → http 유지 + /fileforge/mail', () {
      final c = MailApiClient();
      c.setBaseUrl('https://mail.example.com');
      expect(c.dio.options.baseUrl, 'https://mail.example.com/fileforge/mail');
    });

    test('파일 base와 동일한 .../fileforge 입력 → /mail 추가', () {
      final c = MailApiClient();
      c.setBaseUrl('http://192.168.0.250:8000/fileforge');
      expect(c.dio.options.baseUrl, 'http://192.168.0.250:8000/fileforge/mail');
    });

    test('이미 .../fileforge/mail 이면 그대로(이중 부착 없음)', () {
      final c = MailApiClient();
      c.setBaseUrl('http://192.168.0.250:8000/fileforge/mail');
      expect(c.dio.options.baseUrl, 'http://192.168.0.250:8000/fileforge/mail');
    });

    test('trailing slash 제거', () {
      final c = MailApiClient();
      c.setBaseUrl('192.168.0.250:8000/');
      expect(c.dio.options.baseUrl, 'http://192.168.0.250:8000/fileforge/mail');
    });

    test('빈 값 → 빌드 기본값(mailBaseUrl)으로 복귀', () {
      final c = MailApiClient();
      c.setBaseUrl('192.168.0.250:8000');
      c.setBaseUrl('   ');
      expect(c.dio.options.baseUrl, Env.mailServerUrl);
    });
  });

  group('AuthProvider.setServerUrl 전파 (B0001 핵심)', () {
    test('등록된 메일 콜백으로 서버 주소가 전파된다', () {
      final auth = AuthProvider();
      String? propagated;
      auth.setServerUrlChangeCallback((u) => propagated = u);

      auth.setServerUrl('192.168.0.250:8000');

      expect(propagated, '192.168.0.250:8000');
    });

    test('파일·메일 Dio가 같은 origin을 따라간다 (메일이 localhost에 갇히지 않음)', () {
      final auth = AuthProvider();
      final mail = MailApiClient();
      auth.setServerUrlChangeCallback(mail.setBaseUrl);

      auth.setServerUrl('192.168.0.250:8000');

      // 파일 Dio
      expect(auth.dio.options.baseUrl, 'http://192.168.0.250:8000/fileforge');
      // 메일 Dio — 수정 전이라면 여전히 localhost(빌드 기본값)였을 것.
      expect(mail.dio.options.baseUrl,
          'http://192.168.0.250:8000/fileforge/mail');
      expect(mail.dio.options.baseUrl.contains('localhost'), isFalse);
    });

    test('콜백 미등록이어도 파일 Dio 갱신은 안전(크래시 없음)', () {
      final auth = AuthProvider();
      auth.setServerUrl('192.168.0.250:8000');
      expect(auth.dio.options.baseUrl, 'http://192.168.0.250:8000/fileforge');
    });
  });
}
