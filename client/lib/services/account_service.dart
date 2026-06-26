import 'package:dio/dio.dart';
import '../models/mail_account.dart';
import 'mail_envelope.dart';

/// text account(M) API text — P0007 §6.2/§7.14 account endpoints.
///
/// server(Go mailapi)text account translated text text text text(NR0003 §3):
///   GET    /accounts            → translated text account text
///   POST   /accounts            → OAuth auth_code text → account text(201)
///   DELETE /accounts/{id}       → account text(204)
/// authentication tokentext MailApiClient translated text translated text(MailServicetext text Dio).
class AccountService {
  final Dio _dio;

  AccountService(this._dio);

  /// error text text branchtext text 4xx/5xxtext translated text text text [unwrapEnvelope]text
  /// `ok:false` translated text [MailApiException]text translated text text(share_page_provider
  /// text text text). translated text translated text Dio text DioException text text server error.code
  /// (ACCOUNT_DUPLICATE / oauth not configured text)text translated text.
  Options get _passErrors => Options(validateStatus: (_) => true);

  /// text translated text(`GET /accounts`) text translated text — TR0005 §symptom1.
  ///
  /// text Dio translated text text/text 30s text, "accounttext text?" text text text servertext
  /// translated text text text text text 30~60s translated text translated text("text translated text"text text text).
  /// translated text translated text text text translated text failed→translated text/translated text retrytext translated text.
  static const Duration kGateTimeout = Duration(seconds: 8);

  Options get _gateOptions => Options(
        validateStatus: (_) => true,
        receiveTimeout: kGateTimeout,
        sendTimeout: kGateTimeout,
      );

  /// GET /accounts — translated text account text(P0007 §7.14). translated text translated text text.
  Future<List<MailAccount>> listAccounts() async {
    final resp = await _dio.get('/accounts', options: _gateOptions);
    final data = unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
    return expectListData(data, httpStatus: resp.statusCode)
        .map((e) => MailAccount.fromJson(
            expectMapData(e, httpStatus: resp.statusCode)))
        .toList();
  }

  /// GET /accounts/oauth/authorize?provider= — provider consent URL issue(TR0005 §symptom2).
  ///
  /// server(accounts.go AuthorizeURL)text `{auth_url, state}` text translated text. state text
  /// servertext user/provider text translated text translated text translated text auth_url text browsertext text text.
  /// text text text→server translated text translated text translated text text·accounttranslated text translated text translated text
  /// translated text text translated text text(CH0007 "authenticationtext translated text" text). gmail/outlook text text
  /// (imap text password translated text consent URL text text → servertext VALIDATION_FAILED).
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

  /// POST /accounts — provider translated text text auth_code text servertext translated text accounttext
  /// translated text(P0007 §7.14). return: text translated text account(201).
  ///
  /// failed minutestext(mail_envelope):
  ///  - VALIDATION_FAILED(field=provider|auth_code) — text error
  ///  - ACCOUNT_CONFLICT — text translated text translated text
  ///  - UPSTREAM_UNAVAILABLE(reason=oauth not configured) — server OAuth env not configured
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

  /// DELETE /accounts/{id} — account text(P0007 §7.14). 204(Body None) allowed.
  Future<void> deleteAccount(String accountId) async {
    final resp = await _dio.delete('/accounts/$accountId', options: _passErrors);
    if (resp.statusCode == 204 || resp.data == null) return;
    unwrapEnvelope(resp.data, httpStatus: resp.statusCode);
  }
}
