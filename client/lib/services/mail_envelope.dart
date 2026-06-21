/// P0007 §1 공통 응답 봉투 해석 + L0010 §2.3 에러 코드 분류.
///
/// 설계 출처: mailanchor.design.0002.0007-P §1.1/§1.2/§5,
///            mailanchor.design.0002.0010-L §2.3 classify.
///
/// 분기는 항상 `error.code`로만 한다(P0007 §1.2 — `message`는 로케일 종속이라
/// UI 분기에 쓰지 않는다). dio에 의존하지 않도록, 디코드된 응답 본문(Map)을
/// 입력으로 받는 순수 함수로 둔다(단위 테스트 용이).
library;

/// L0010 §2.3 — 클라이언트 분기용 에러 범주.
enum MailErrorCategory {
  /// `TOKEN_EXPIRED` — 리프레시 후 재시도 대상.
  refreshable,

  /// `TOKEN_INVALID`/`FORBIDDEN`/`AUTH_INVALID_CREDENTIALS` — 인증 흐름.
  auth,

  /// `UPSTREAM_UNAVAILABLE`/`SEND_FAILED` — 일시 오류(백오프 재시도 대상).
  transient,

  /// `VALIDATION_FAILED`/`RECIPIENT_INVALID`/`DRAFT_CONFLICT`/`LABEL_DUPLICATE`
  /// — 사용자 조치 필요.
  userAction,

  /// `MAIL_NOT_FOUND`/`ATTACHMENT_NOT_FOUND`/`LABEL_NOT_FOUND`.
  notFound,

  /// 미정의 코드 / 네트워크 오류 — 일반 오류(P0007 §5 기본값).
  generic,
}

/// L0010 §2.3 — `error.code` → 범주 매핑. 미정의 코드는 generic.
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

/// P0007 §1.2 에러 봉투를 표현하는 예외.
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

  /// P0007 §1.2 에러 봉투(Map)로부터 예외를 만든다.
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

/// P0007 §1.1/§1.2 — 성공 봉투에서 `data`를 벗긴다. 실패 봉투면 던진다.
/// 본문이 봉투 형태가 아니면(예: 비정상 응답) generic 예외로 환원한다.
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

/// 성공 봉투의 `data`가 객체(Map)임을 보장하고 `Map<String, dynamic>`로 캐스트한다.
/// 봉투는 [unwrapEnvelope]가 검증하지만, `ok:true` 인데 내부 `data`가 비-Map인
/// 비정상 성공응답이면 무가드 캐스트가 raw `TypeError`로 크래시한다(NR0016 §3 MINOR).
/// 이를 generic `MALFORMED_RESPONSE` 예외로 우아하게 환원한다.
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

/// [expectMapData]의 List 대응 — 성공 봉투의 `data`가 배열임을 보장한다.
/// `null`은 빈 리스트로 허용(목록 응답에서 data 생략 가능)하되, 비-List 비정상
/// 응답은 raw `TypeError` 대신 `MALFORMED_RESPONSE` 예외로 환원한다.
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

/// 성공 봉투의 `meta`(목록 페이지네이션 등)를 꺼낸다. 없으면 null.
Map<String, dynamic>? envelopeMeta(dynamic body) {
  if (body is Map) {
    return (body['meta'] as Map?)?.cast<String, dynamic>();
  }
  return null;
}
