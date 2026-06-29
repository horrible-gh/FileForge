/// MailAnchor translated text text — P0007(translated text translated text) §3 text DTO translated text text.
///
/// text text: mailanchor.design.0002.0007-P §3.1~§3.8, §4 translated text.
/// translated text server issue translated text(opaque) stringtext translated text, translated text translated text
/// translated text translated text(P0007 notation rule). translated text ISO-8601 UTC stringtext.
library;

/// P0007 §3.3 — text text.
/// `name`text text text text(empty string/text), `address`text requiredtext.
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

  /// displaytext — nametext translated text name, translated text address.
  String get display => name.isNotEmpty ? name : address;
}

/// P0007 §3.4 — text text.
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

/// P0007 §3.5 — text.
/// `type`: "system"(inbox/sent/draft text text) | "user"(translated text create).
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

/// P0007 §3.2 — Body(translated text/HTML).
class MailBody {
  /// "text" | "html" (P0007 §3.2). translated text translated text empty Bodytext translated text.
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

/// R0001(0013) — 메일이 도착한 *내 계정*의 식별 정보(MailSummary에 부착).
///
/// 다계정 연동 시 리스트에서 "이 메일이 내 어느 메일함(계정)으로 왔는가"를
/// 한눈에 알려면 행마다 계정 단서가 필요하다. 서버 `_summary_to_p0007`이
/// 통합 인박스 JOIN의 계정 컬럼(account_uuid/name/email/display_color)을
/// `account` 객체로 실어 보내며, 이 모델이 그것을 받는다. 송신자(from)와는
/// 별개의 *수신 계정* 정보다.
class MailAccountRef {
  final String accountId;
  final String email;
  final String name;

  /// 서버 display_color(예: `#EA4335`). 비어 있거나 계정마다 동일할 수 있어,
  /// 리스트 색 구분은 이 값에 의존하지 않고 계정 식별자 해시로 파생한다(아래 hasIdentity 라벨이 1차 단서).
  final String color;

  const MailAccountRef({
    this.accountId = '',
    this.email = '',
    this.name = '',
    this.color = '',
  });

  factory MailAccountRef.fromJson(Map<String, dynamic> json) {
    return MailAccountRef(
      accountId: json['account_id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      color: json['color'] as String? ?? '',
    );
  }

  /// 리스트에 표시할 계정 라벨 — 이름이 있으면 이름, 없으면 이메일.
  /// (이름/이메일은 계정마다 본질적으로 다르므로 색이 같아도 구분된다.)
  String get label => name.isNotEmpty ? name : email;

  /// 식별자(색 파생용) — id > email > name 순.
  String get key => accountId.isNotEmpty
      ? accountId
      : (email.isNotEmpty ? email : name);

  bool get hasIdentity => label.isNotEmpty;
}

/// P0007 §3.1 — text text(MailSummary).
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

  /// R0001(0027) — 핀 고정 여부. 서버 `_summary_to_p0007`이 통합 인박스의
  /// `m.is_pinned`를 실어 보내며(통합 목록 SQL은 핀 메일을 `ORDER BY m.is_pinned DESC`로
  /// 최상단에 올린다), 리스트는 이 값으로 핀 배지/토글 상태를 그린다.
  final bool isPinned;

  /// R0001(0013) — 이 메일이 도착한 내 계정. 식별 정보가 없으면 빈 ref.
  final MailAccountRef account;

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
    this.isPinned = false,
    this.account = const MailAccountRef(),
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
      isPinned: json['is_pinned'] as bool? ?? false,
      account: MailAccountRef.fromJson(
          (json['account'] as Map?)?.cast<String, dynamic>() ?? const {}),
    );
  }

  /// text displaytext text text — local translated text refreshtext.
  MailSummary copyWithRead(bool read) => copyWith(isRead: read);

  /// 핀 상태만 바꾼 사본(R0001/0027) — togglePin 낙관적 갱신용.
  MailSummary copyWithPinned(bool pinned) => copyWith(isPinned: pinned);

  MailSummary copyWith({bool? isRead, bool? isPinned}) => MailSummary(
        mailId: mailId,
        threadId: threadId,
        from: from,
        subject: subject,
        snippet: snippet,
        receivedAt: receivedAt,
        isRead: isRead ?? this.isRead,
        hasAttachment: hasAttachment,
        labels: labels,
        isPinned: isPinned ?? this.isPinned,
        account: account,
      );
}

/// P0007 §3.2 — text(MailDetail).
class MailDetail {
  final String mailId;
  final String threadId;
  final MailAddress from;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final String subject;
  final String receivedAt;
  final bool isRead;

  /// R0001(0027) — 핀 고정 여부(상세 AppBar 핀 토글의 현재 상태).
  final bool isPinned;
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
    this.isPinned = false,
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
      isPinned: json['is_pinned'] as bool? ?? false,
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

  /// 핀 상태만 바꾼 사본(R0001/0027) — togglePin 낙관적 갱신용.
  MailDetail copyWithPinned(bool pinned) => MailDetail(
        mailId: mailId,
        threadId: threadId,
        from: from,
        to: to,
        cc: cc,
        subject: subject,
        receivedAt: receivedAt,
        isRead: isRead,
        isPinned: pinned,
        body: body,
        attachments: attachments,
        labels: labels,
      );
}

/// P0007 §4 — text translated text text text.
/// `meta.next_cursor`text nulltranslated text `has_more`text falsetext translated text text.
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

  /// P0007 §1.1 success translated text `data`(text)+`meta`translated text text translated text translated text.
  /// [data]text text translated text text `data`(List), [meta]text `meta`(Map|null).
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

/// P0007 §6.2/§7.9 — Draft(GET /drafts/{id} text data).
///
/// text translated text text text(translated text·text·Body·text)text text translated text translated text
/// `updated_at`(§7.10 base_updated_at text text)text translated text. servertext text translated text
/// translated text translated text(merge stage Go backend compatibility) all text translated text translated text.
class MailDraft {
  final String draftId;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final String subject;
  final MailBody body;
  final List<MailAttachment> attachments;

  /// refresh text base_updated_at text translated text translated text translated text(§7.10).
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
