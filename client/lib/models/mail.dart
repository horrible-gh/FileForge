/// MailAnchor 도메인 모델 — P0007(프로토콜 마스터) §3 공통 DTO 와이어 형태.
///
/// 설계 출처: mailanchor.design.0002.0007-P §3.1~§3.8, §4 페이지네이션.
/// 식별자는 서버 발급 불투명(opaque) 문자열로 취급하고, 클라이언트는 형식을
/// 가정하지 않는다(P0007 표기 규칙). 시각은 ISO-8601 UTC 문자열이다.
library;

/// P0007 §3.3 — 메일 주소.
/// `name`은 없을 수 있고(빈 문자열/생략), `address`는 필수다.
class MailAddress {
  final String name;
  final String address;

  const MailAddress({this.name = '', required this.address});

  factory MailAddress.fromJson(Map<String, dynamic> json) {
    return MailAddress(
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
    );
  }

  /// 표시용 — name이 있으면 name, 없으면 address.
  String get display => name.isNotEmpty ? name : address;
}

/// P0007 §3.4 — 첨부 메타.
class MailAttachment {
  final String attachmentId;
  final String filename;
  final int sizeBytes;
  final String contentType;

  const MailAttachment({
    required this.attachmentId,
    required this.filename,
    this.sizeBytes = 0,
    this.contentType = '',
  });

  factory MailAttachment.fromJson(Map<String, dynamic> json) {
    return MailAttachment(
      attachmentId: json['attachment_id'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      contentType: json['content_type'] as String? ?? '',
    );
  }
}

/// P0007 §3.5 — 라벨.
/// `type`: "system"(inbox/sent/draft 등 고정) | "user"(사용자 생성).
class MailLabel {
  final String labelId;
  final String name;
  final String type;
  final String? color;

  const MailLabel({
    required this.labelId,
    required this.name,
    this.type = 'user',
    this.color,
  });

  factory MailLabel.fromJson(Map<String, dynamic> json) {
    return MailLabel(
      labelId: json['label_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'user',
      color: json['color'] as String?,
    );
  }

  bool get isSystem => type == 'system';
}

/// P0007 §3.2 — 본문(텍스트/HTML).
class MailBody {
  /// "text" | "html" (P0007 §3.2). 미지원 포맷은 빈 본문으로 처리한다.
  final String format;
  final String content;

  const MailBody({this.format = 'text', this.content = ''});

  factory MailBody.fromJson(Map<String, dynamic> json) {
    return MailBody(
      format: json['format'] as String? ?? 'text',
      content: json['content'] as String? ?? '',
    );
  }

  bool get isHtml => format == 'html';
}

/// P0007 §3.1 — 목록 항목(MailSummary).
class MailSummary {
  final String mailId;
  final String threadId;
  final MailAddress from;
  final String subject;
  final String snippet;
  final String receivedAt;
  final bool isRead;
  final bool hasAttachment;
  final List<String> labels;

  const MailSummary({
    required this.mailId,
    this.threadId = '',
    required this.from,
    this.subject = '',
    this.snippet = '',
    this.receivedAt = '',
    this.isRead = false,
    this.hasAttachment = false,
    this.labels = const [],
  });

  factory MailSummary.fromJson(Map<String, dynamic> json) {
    return MailSummary(
      mailId: json['mail_id'] as String? ?? '',
      threadId: json['thread_id'] as String? ?? '',
      from: MailAddress.fromJson(
          (json['from'] as Map?)?.cast<String, dynamic>() ?? const {}),
      subject: json['subject'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      receivedAt: json['received_at'] as String? ?? '',
      isRead: json['is_read'] as bool? ?? false,
      hasAttachment: json['has_attachment'] as bool? ?? false,
      labels: (json['labels'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// 읽음 표시만 바꾼 사본 — 로컬 낙관적 갱신용.
  MailSummary copyWithRead(bool read) => MailSummary(
        mailId: mailId,
        threadId: threadId,
        from: from,
        subject: subject,
        snippet: snippet,
        receivedAt: receivedAt,
        isRead: read,
        hasAttachment: hasAttachment,
        labels: labels,
      );
}

/// P0007 §3.2 — 상세(MailDetail).
class MailDetail {
  final String mailId;
  final String threadId;
  final MailAddress from;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final String subject;
  final String receivedAt;
  final bool isRead;
  final MailBody body;
  final List<MailAttachment> attachments;
  final List<String> labels;

  const MailDetail({
    required this.mailId,
    this.threadId = '',
    required this.from,
    this.to = const [],
    this.cc = const [],
    this.subject = '',
    this.receivedAt = '',
    this.isRead = false,
    this.body = const MailBody(),
    this.attachments = const [],
    this.labels = const [],
  });

  factory MailDetail.fromJson(Map<String, dynamic> json) {
    List<MailAddress> addrs(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((e) => MailAddress.fromJson(
                (e as Map?)?.cast<String, dynamic>() ?? const {}))
            .toList();
    return MailDetail(
      mailId: json['mail_id'] as String? ?? '',
      threadId: json['thread_id'] as String? ?? '',
      from: MailAddress.fromJson(
          (json['from'] as Map?)?.cast<String, dynamic>() ?? const {}),
      to: addrs('to'),
      cc: addrs('cc'),
      subject: json['subject'] as String? ?? '',
      receivedAt: json['received_at'] as String? ?? '',
      isRead: json['is_read'] as bool? ?? false,
      body: MailBody.fromJson(
          (json['body'] as Map?)?.cast<String, dynamic>() ?? const {}),
      attachments: (json['attachments'] as List<dynamic>? ?? const [])
          .map((e) => MailAttachment.fromJson(
              (e as Map?)?.cast<String, dynamic>() ?? const {}))
          .toList(),
      labels: (json['labels'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// P0007 §4 — 커서 페이지네이션 한 묶음.
/// `meta.next_cursor`가 null이거나 `has_more`가 false면 마지막 묶음.
class MailPage {
  final List<MailSummary> items;
  final String? nextCursor;
  final bool hasMore;
  final int count;

  const MailPage({
    this.items = const [],
    this.nextCursor,
    this.hasMore = false,
    this.count = 0,
  });

  /// P0007 §1.1 성공 봉투의 `data`(배열)+`meta`로부터 한 묶음을 만든다.
  /// [data]는 이미 봉투에서 벗긴 `data`(List), [meta]는 `meta`(Map|null).
  factory MailPage.fromEnvelopeParts(
    List<dynamic> data,
    Map<String, dynamic>? meta,
  ) {
    return MailPage(
      items: data
          .map((e) => MailSummary.fromJson(
              (e as Map?)?.cast<String, dynamic>() ?? const {}))
          .toList(),
      nextCursor: meta?['next_cursor'] as String?,
      hasMore: meta?['has_more'] as bool? ?? false,
      count: (meta?['count'] as num?)?.toInt() ?? data.length,
    );
  }
}

/// P0007 §6.2/§7.9 — 초안(GET /drafts/{id} 의 data).
///
/// 발송 페이로드와 같은 필드(받는이·제목·본문·첨부)에 더해 낙관적 경합용
/// `updated_at`(§7.10 base_updated_at 의 출처)을 보유한다. 서버가 일부 필드를
/// 생략해도 견디도록(흡수 단계 Go 백엔드 정합) 모든 키를 관용적으로 읽는다.
class MailDraft {
  final String draftId;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final String subject;
  final MailBody body;
  final List<MailAttachment> attachments;

  /// 갱신 시 base_updated_at 으로 되돌려보내 경합을 감지한다(§7.10).
  final String updatedAt;

  const MailDraft({
    required this.draftId,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.body = const MailBody(),
    this.attachments = const [],
    this.updatedAt = '',
  });

  factory MailDraft.fromJson(Map<String, dynamic> json) {
    List<MailAddress> addrs(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((e) => MailAddress.fromJson(
                (e as Map?)?.cast<String, dynamic>() ?? const {}))
            .toList();
    return MailDraft(
      draftId: json['draft_id'] as String? ?? '',
      to: addrs('to'),
      cc: addrs('cc'),
      bcc: addrs('bcc'),
      subject: json['subject'] as String? ?? '',
      body: MailBody.fromJson(
          (json['body'] as Map?)?.cast<String, dynamic>() ?? const {}),
      attachments: (json['attachments'] as List<dynamic>? ?? const [])
          .map((e) => MailAttachment.fromJson(
              (e as Map?)?.cast<String, dynamic>() ?? const {}))
          .toList(),
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}
