import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/services/mail_envelope.dart';

/// NR0007 §6 L1·L2 — 계정 연결 실패 catch-all 분화의 핵심(순수 분류기)을 검증한다.
///
/// TR0005 가 남긴 "실패 표면 미설계" 의 결과로 `_connectErrorMessage` 가 5종 실패를
/// 단일 토스트로 뭉갰다(NR0007 §5). [classifyConnectFailure] 가 그 5종을 서로 다른
/// 범주로 갈라내는지, [diagnosticLabel] 이 진단 토큰을 노출하는지 본다.
MailApiException _envelope(
  String code, {
  int? httpStatus,
  String? reason,
  String? requestId,
}) {
  final err = <String, dynamic>{'code': code, 'message': 'x'};
  if (reason != null) err['details'] = {'reason': reason};
  if (requestId != null) err['request_id'] = requestId;
  return MailApiException.fromEnvelope({'error': err}, httpStatus: httpStatus);
}

void main() {
  group('classifyConnectFailure — NR0007 §6 L1', () {
    test('ACCOUNT_DUPLICATE → conflict', () {
      expect(classifyConnectFailure(_envelope('ACCOUNT_DUPLICATE')),
          ConnectFailureKind.conflict);
    });

    test('UPSTREAM_UNAVAILABLE reason="oauth not configured" → oauthNotConfigured',
        () {
      expect(
        classifyConnectFailure(
            _envelope('UPSTREAM_UNAVAILABLE', reason: 'oauth not configured')),
        ConnectFailureKind.oauthNotConfigured,
      );
    });

    test('UPSTREAM_UNAVAILABLE reason="oauth exchange failed" → oauthExchangeFailed '
        '(§5.2 — 이전엔 일반 토스트로 새던 케이스)', () {
      expect(
        classifyConnectFailure(
            _envelope('UPSTREAM_UNAVAILABLE', reason: 'oauth exchange failed')),
        ConnectFailureKind.oauthExchangeFailed,
      );
    });

    test('401/403 또는 auth 범주 → session (§5.3)', () {
      expect(classifyConnectFailure(_envelope('TOKEN_INVALID', httpStatus: 401)),
          ConnectFailureKind.session);
      expect(classifyConnectFailure(_envelope('FORBIDDEN', httpStatus: 403)),
          ConnectFailureKind.session);
      // httpStatus 가 없어도 인증 범주면 세션으로 승격.
      expect(classifyConnectFailure(_envelope('AUTH_INVALID_CREDENTIALS')),
          ConnectFailureKind.session);
    });

    test('UNKNOWN(네트워크) 와 reason 없는 UPSTREAM_UNAVAILABLE(일시) → network', () {
      expect(classifyConnectFailure(_envelope('UNKNOWN')),
          ConnectFailureKind.network);
      expect(classifyConnectFailure(_envelope('UPSTREAM_UNAVAILABLE')),
          ConnectFailureKind.network);
    });

    test('MALFORMED_RESPONSE(404·비봉투) → malformed (§4 H1)', () {
      expect(classifyConnectFailure(_envelope('MALFORMED_RESPONSE', httpStatus: 404)),
          ConnectFailureKind.malformed);
    });

    test('VALIDATION_FAILED → invalid', () {
      expect(classifyConnectFailure(_envelope('VALIDATION_FAILED')),
          ConnectFailureKind.invalid);
    });

    test('미정의 코드 → generic 폴백', () {
      expect(classifyConnectFailure(_envelope('SOME_NEW_CODE')),
          ConnectFailureKind.generic);
    });

    test('세션 우선순위: 401 인 UPSTREAM_UNAVAILABLE 도 세션으로(범주보다 상태 먼저)',
        () {
      // reason 없는 UPSTREAM_UNAVAILABLE 이지만 401 이면 세션이 우선.
      expect(
        classifyConnectFailure(_envelope('UPSTREAM_UNAVAILABLE', httpStatus: 401)),
        ConnectFailureKind.session,
      );
    });
  });

  group('diagnosticLabel — NR0007 §6 L2', () {
    test('code 만 있으면 code 단독', () {
      expect(diagnosticLabel(_envelope('UNKNOWN')), 'UNKNOWN');
    });

    test('httpStatus·requestId 가 있으면 함께 노출', () {
      final label = diagnosticLabel(
          _envelope('MALFORMED_RESPONSE', httpStatus: 404, requestId: 'rq_9'));
      expect(label, 'MALFORMED_RESPONSE · HTTP 404 · req rq_9');
    });
  });
}
