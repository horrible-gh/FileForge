import 'package:dio/dio.dart';
import '../models/mail_account.dart';
import 'mail_envelope.dart';

/// 메일 계정(M) API 래퍼 — P0007 §6.2/§7.14 계정 엔드포인트.
///
/// 서버(Go mailapi)는 계정 입구가 이미 열려 있다(NR0003 §3):
///   GET    /accounts            → 연결된 계정 목록
///   POST   /accounts            → OAuth auth_code 교환 → 계정 연결(201)
///   DELETE /accounts/{id}       → 계정 해제(204)
/// 인증 토큰은 MailApiClient 인터셉터가 주입한다(MailService와 동일 Dio).
class AccountService {
  final Dio _dio;

  AccountService(this._dio);

  /// 에러 코드 기반 분기를 위해 4xx/5xx도 던지지 않고 받아 [unwrapEnvelope]가
  /// `ok:false` 봉투를 [MailApiException]으로 환원하게 한다(share_page_provider
  /// 와 동일 패턴). 그렇지 않으면 Dio 가 DioException 을 던져 서버 error.code
  /// (ACCOUNT_DUPLICATE / oauth not configured 등)를 잃는다.
  Options get _passErrors => Options(validateStatus: (_) => true);

  /// 진입 게이트(`GET /accounts`) 전용 타임아웃 — TR0005 §증상1.
  ///
  /// 전역 Dio 타임아웃은 연결/수신 30s 인데, "계정이 있나?" 판정 한 건이 서버가
  /// 느리거나 닿지 않을 때 최대 30~60s 스피너로 이어졌다("너무 느리다"의 한 축).
  /// 게이트 호출만 짧게 끊어 빠르게 실패→온보딩/인라인 재시도로 흘려보낸다.
  static const Duration kGateTimeout = Duration(seconds: 8);

  Options get _gateOptions => Options(
        validateStatus: (_) => true,
        receiveTimeout: kGateTimeout,
        sendTimeout: kGateTimeout,
      );

  /// GET /accounts — 연결된 계정 목록(P0007 §7.14). 게이트 타임아웃 적용.
  Future<List<MailAccount>> listAccounts() async {
    final resp = await _dio.get('/accounts', options: _gateOptions);
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return expectListData(data, httpStatus: resp.statusCode)
        .map((e) => MailAccount.fromJson(
            expectMapData(e, httpStatus: resp.statusCode)))
        .toList();
  }

  /// GET /accounts/oauth/authorize?provider= — 제공자 동의 URL 발급(TR0005 §증상2).
  ///
  /// 서버(accounts.go AuthorizeURL)가 `{auth_url, state}` 를 돌려준다. state 는
  /// 서버가 user/provider 에 결속해 두므로 클라는 auth_url 만 브라우저로 열면 된다.
  /// 동의 후 구글→서버 콜백이 백채널로 코드를 교환·계정연결하므로 사용자가 코드를
  /// 손으로 만질 필요가 없다(CH0007 "인증코드 붙여넣기" 제거). gmail/outlook 만 지원
  /// (imap 은 비밀번호 기반이라 동의 URL 이 없다 → 서버가 VALIDATION_FAILED).
  Future<String> authorizeUrl(String provider) async {
    final resp = await _dio.get(
      '/accounts/oauth/authorize',
      queryParameters: {'provider': provider},
      options: _passErrors,
    );
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    final map = expectMapData(data, httpStatus: resp.statusCode);
    final url = map['auth_url'] as String?;
    if (url == null || url.isEmpty) {
      throw MailApiException(
        code: 'MALFORMED_RESPONSE',
        message: 'authorize response missing auth_url',
        httpStatus: resp.statusCode,
      );
    }
    return url;
  }

  /// POST /accounts — provider 동의로 받은 auth_code 를 서버가 교환하여 계정을
  /// 연결한다(P0007 §7.14). 반환: 새로 연결된 계정(201).
  ///
  /// 실패 분류(mail_envelope):
  ///  - VALIDATION_FAILED(field=provider|auth_code) — 입력 오류
  ///  - ACCOUNT_CONFLICT — 이미 연결된 이메일
  ///  - UPSTREAM_UNAVAILABLE(reason=oauth not configured) — 서버 OAuth env 미설정
  Future<MailAccount> connectAccount({
    required String provider,
    required String authCode,
  }) async {
    final resp = await _dio.post(
      '/accounts',
      data: {'provider': provider, 'auth_code': authCode},
      options: _passErrors,
    );
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return MailAccount.fromJson(expectMapData(data, httpStatus: resp.statusCode));
  }

  /// DELETE /accounts/{id} — 계정 해제(P0007 §7.14). 204(본문 없음) 허용.
  Future<void> deleteAccount(String accountId) async {
    final resp = await _dio.delete('/accounts/$accountId', options: _passErrors);
    if (resp.statusCode == 204 || resp.data == null) return;
    unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
  }
}
