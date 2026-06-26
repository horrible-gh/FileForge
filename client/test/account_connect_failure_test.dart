import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/services/mail_envelope.dart';

/// NR0007 §6 L1·L2 — account Connection failed catch-all minutestext core(text minutestext)text verifytext.
///
/// TR0005 text text "failed text translated text" text resulttext `_connectErrorMessage` text 5text failedtext
/// text toasttext translated text(NR0007 §5). [classifyConnectFailure] text text 5text text text
/// translated text translated text, [diagnosticLabel] text diagnostic tokentext translated text text.
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
        '(§5.2 — translated text text toasttext text translated text)', () {
      expect(
        classifyConnectFailure(
            _envelope('UPSTREAM_UNAVAILABLE', reason: 'oauth exchange failed')),
        ConnectFailureKind.oauthExchangeFailed,
      );
    });

    test('401/403 text auth text → session (§5.3)', () {
      expect(classifyConnectFailure(_envelope('TOKEN_INVALID', httpStatus: 401)),
          ConnectFailureKind.session);
      expect(classifyConnectFailure(_envelope('FORBIDDEN', httpStatus: 403)),
          ConnectFailureKind.session);
      // httpStatus text translated text authentication translated text sessiontext text.
      expect(classifyConnectFailure(_envelope('AUTH_INVALID_CREDENTIALS')),
          ConnectFailureKind.session);
    });

    test('UNKNOWN(translated text) text reason text UPSTREAM_UNAVAILABLE(text) → network', () {
      expect(classifyConnectFailure(_envelope('UNKNOWN')),
          ConnectFailureKind.network);
      expect(classifyConnectFailure(_envelope('UPSTREAM_UNAVAILABLE')),
          ConnectFailureKind.network);
    });

    test('MALFORMED_RESPONSE(404·translated text) → malformed (§4 H1)', () {
      expect(classifyConnectFailure(_envelope('MALFORMED_RESPONSE', httpStatus: 404)),
          ConnectFailureKind.malformed);
    });

    test('VALIDATION_FAILED → invalid', () {
      expect(classifyConnectFailure(_envelope('VALIDATION_FAILED')),
          ConnectFailureKind.invalid);
    });

    test('translated text text → generic text', () {
      expect(classifyConnectFailure(_envelope('SOME_NEW_CODE')),
          ConnectFailureKind.generic);
    });

    test('session translated text: 401 text UPSTREAM_UNAVAILABLE text sessiontext(translated text state text)',
        () {
      // reason text UPSTREAM_UNAVAILABLE translated text 401 text sessiontext text.
      expect(
        classifyConnectFailure(_envelope('UPSTREAM_UNAVAILABLE', httpStatus: 401)),
        ConnectFailureKind.session,
      );
    });
  });

  group('diagnosticLabel — NR0007 §6 L2', () {
    test('code text translated text code text', () {
      expect(diagnosticLabel(_envelope('UNKNOWN')), 'UNKNOWN');
    });

    test('httpStatus·requestId text translated text text text', () {
      final label = diagnosticLabel(
          _envelope('MALFORMED_RESPONSE', httpStatus: 404, requestId: 'rq_9'));
      expect(label, 'MALFORMED_RESPONSE · HTTP 404 · req rq_9');
    });
  });
}
