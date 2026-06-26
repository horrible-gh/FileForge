/// P0007 §1 text text text text + L0010 §2.3 error text minutestext.
///
/// text text: mailanchor.design.0002.0007-P §1.1/§1.2/§5,
///            mailanchor.design.0002.0010-L §2.3 classify.
///
/// branchtext text `error.code`text text(P0007 §1.2 — `message`text translated text translated text
/// UI branchtext text translated text). diotext translated text translated text, translated text text Body(Map)text
/// translated text text text translated text text(text translated text text).
library;

/// L0010 §2.3 — translated text branchtext error text.
enum MailErrorCategory {
  /// `TOKEN_EXPIRED` — translated text text retry text.
  refreshable,

  /// `TOKEN_INVALID`/`FORBIDDEN`/`AUTH_INVALID_CREDENTIALS` — authentication text.
  auth,

  /// `UPSTREAM_UNAVAILABLE`/`SEND_FAILED` — text error(translated text retry text).
  transient,

  /// `VALIDATION_FAILED`/`RECIPIENT_INVALID`/`DRAFT_CONFLICT`/`LABEL_DUPLICATE`
  /// — translated text text text.
  userAction,

  /// `MAIL_NOT_FOUND`/`ATTACHMENT_NOT_FOUND`/`LABEL_NOT_FOUND`.
  notFound,

  /// translated text text / translated text error — text error(P0007 §5 default value).
  generic,
}

/// L0010 §2.3 — `error.code` → text text. translated text translated text generic.
MailErrorCategory classifyMailErrorCode(String code) {
  switch (code) {
    case 'TOKEN_EXPIRED':
      return MailErrorCategory.refreshable;
    case 'TOKEN_INVALID':
    case 'FORBIDDEN':
    case 'AUTH_INVALID_CREDENTIALS':
      return MailErrorCategory.auth;
    case 'UPSTREAM_UNAVAILABLE':
    case 'SEND_FAILED':
      return MailErrorCategory.transient;
    case 'VALIDATION_FAILED':
    case 'RECIPIENT_INVALID':
    case 'DRAFT_CONFLICT':
    case 'LABEL_DUPLICATE':
      return MailErrorCategory.userAction;
    case 'MAIL_NOT_FOUND':
    case 'ATTACHMENT_NOT_FOUND':
    case 'LABEL_NOT_FOUND':
      return MailErrorCategory.notFound;
    default:
      return MailErrorCategory.generic;
  }
}

/// account text(authorize/connect) failedtext **translated text text** — NR0007 §6 L1.
///
/// TR0005 text OAuth browser translated text translated text failed translated text text translated text text,
/// `_connectErrorMessage` text catch-all text branchtext 5text failed(translated text/404·MALFORMED/
/// session401/VALIDATION/oauth-exchange-failed)text text translated text toasttext translated text
/// (NR0007 §5 — diagnostictranslated text text → "text failedtranslated text text text text text"). text enum text
/// text catch-all text translated text minutestext translated text/translated text text translated text text text text text.
enum ConnectFailureKind {
  /// text translated text account(`ACCOUNT_DUPLICATE`).
  conflict,

  /// servertext OAuth env not configured(`UPSTREAM_UNAVAILABLE` reason=`oauth not configured`).
  oauthNotConfigured,

  /// OAuth text text failed(`UPSTREAM_UNAVAILABLE` reason=`oauth exchange failed`).
  /// NR0007 §5.2 — reason branchtext text translated text translated text text toasttext text translated text.
  oauthExchangeFailed,

  /// session expired/text(401·403 text auth/refreshable text) — textlogin text.
  /// NR0007 §5.3 — connect/authorize pathtext session translated text text text.
  session,

  /// text server translated text/translated text text text translated text text text.
  network,

  /// text-text text(404·translated text HTML text) → `MALFORMED_RESPONSE`.
  /// NR0007 §4 H1 — text authorize translated text translated text text translated text text.
  malformed,

  /// provider translated text text/text verify failed text translated text text text.
  invalid,

  /// text translated text text translated text translated text failed(text text).
  generic,
}

/// [MailApiException] text [ConnectFailureKind] text minutestranslated text(NR0007 §6 L1).
///
/// branchtext `code`/`httpStatus`/`category`/`details.reason` text text(`message` text
/// translated text translated text text text — P0007 §1.2). translated text translated text: text text(text·OAuth
/// reason) → session(state/text) → translated text/text → MALFORMED → textverify → text.
ConnectFailureKind classifyConnectFailure(MailApiException e) {
  if (e.code == 'ACCOUNT_DUPLICATE') return ConnectFailureKind.conflict;
  if (e.code == 'UPSTREAM_UNAVAILABLE') {
    final reason = e.details?['reason'] as String?;
    if (reason == 'oauth not configured') {
      return ConnectFailureKind.oauthNotConfigured;
    }
    if (reason == 'oauth exchange failed') {
      return ConnectFailureKind.oauthExchangeFailed;
    }
  }
  if (e.httpStatus == 401 ||
      e.httpStatus == 403 ||
      e.category == MailErrorCategory.auth ||
      e.category == MailErrorCategory.refreshable) {
    return ConnectFailureKind.session;
  }
  // UNKNOWN(translated text text) text transient(UPSTREAM_UNAVAILABLE/SEND_FAILED, reason
  // text)text text "servertext text text/text text" → retry text.
  if (e.code == 'UNKNOWN' || e.category == MailErrorCategory.transient) {
    return ConnectFailureKind.network;
  }
  if (e.code == 'MALFORMED_RESPONSE') return ConnectFailureKind.malformed;
  if (e.category == MailErrorCategory.userAction) {
    return ConnectFailureKind.invalid;
  }
  return ConnectFailureKind.generic;
}

/// toast/bannertext translated text **diagnostic translated text**(NR0007 §6 L2) — translated text/translated text translated text
/// text text translated text `code`·`httpStatus`·`requestId` text translated text translated text translated text.
/// `MailApiException` text text text text text(mail_envelope §60-100).
String diagnosticLabel(MailApiException e) {
  final parts = <String>[e.code];
  if (e.httpStatus != null) parts.add('HTTP ${e.httpStatus}');
  if (e.requestId != null && e.requestId!.isNotEmpty) {
    parts.add('req ${e.requestId}');
  }
  return parts.join(' · ');
}

/// P0007 §1.2 error translated text translated text exampletext.
class MailApiException implements Exception {
  final String code;
  final String message;
  final MailErrorCategory category;
  final int? httpStatus;
  final Map<String, dynamic>? details;
  final String? requestId;

  MailApiException({
    required this.code,
    required this.message,
    this.httpStatus,
  })  : category = classifyMailErrorCode(code),
        details = null,
        requestId = null;

  MailApiException._({
    required this.code,
    required this.message,
    required this.category,
    this.httpStatus,
    this.details,
    this.requestId,
  });

  /// P0007 §1.2 error text(Map)translated text exampletext translated text.
  factory MailApiException.fromEnvelope(
    Map<String, dynamic> body, {
    int? httpStatus,
  }) {
    final err = (body['error'] as Map?)?.cast<String, dynamic>() ?? const {};
    final code = err['code'] as String? ?? 'UNKNOWN';
    return MailApiException._(
      code: code,
      message: err['message'] as String? ?? 'Unknown error',
      category: classifyMailErrorCode(code),
      httpStatus: httpStatus,
      details: (err['details'] as Map?)?.cast<String, dynamic>(),
      requestId: err['request_id'] as String?,
    );
  }

  @override
  String toString() => 'MailApiException($code: $message)';
}

/// P0007 §1.1/§1.2 — success translated text `data`text translated text. failed translated text translated text.
/// Bodytext text translated text translated text(example: translated text text) generic exampletext translated text.
dynamic unwrapEnvelope(dynamic body, {int? httpStatus}) {
  if (body is! Map) {
    throw MailApiException(
      code: 'MALFORMED_RESPONSE',
      message: 'Response is not a valid envelope',
      httpStatus: httpStatus,
    );
  }
  final map = body.cast<String, dynamic>();
  if (map['ok'] == true) {
    return map['data'];
  }
  throw MailApiException.fromEnvelope(map, httpStatus: httpStatus);
}

/// success translated text `data`text text(Map)text translated text `Map<String, dynamic>`text translated text.
/// translated text [unwrapEnvelope]text verifytranslated text, `ok:true` text text `data`text text-Maptext
/// translated text successtranslated text textguard translated text raw `TypeError`text translated text(NR0016 §3 MINOR).
/// text generic `MALFORMED_RESPONSE` exampletext translated text translated text.
Map<String, dynamic> expectMapData(dynamic data, {int? httpStatus}) {
  if (data is! Map) {
    throw MailApiException(
      code: 'MALFORMED_RESPONSE',
      message: 'Expected an object in response data',
      httpStatus: httpStatus,
    );
  }
  return data.cast<String, dynamic>();
}

/// [expectMapData]text List text — success translated text `data`text translated text translated text.
/// `null`text empty translated text allowed(text translated text data text text)text, text-List translated text
/// translated text raw `TypeError` text `MALFORMED_RESPONSE` exampletext translated text.
List<dynamic> expectListData(dynamic data, {int? httpStatus}) {
  if (data == null) return const [];
  if (data is! List) {
    throw MailApiException(
      code: 'MALFORMED_RESPONSE',
      message: 'Expected an array in response data',
      httpStatus: httpStatus,
    );
  }
  return data;
}

/// success translated text `meta`(text translated text text)text translated text. translated text null.
Map<String, dynamic>? envelopeMeta(dynamic body) {
  if (body is Map) {
    return (body['meta'] as Map?)?.cast<String, dynamic>();
  }
  return null;
}
