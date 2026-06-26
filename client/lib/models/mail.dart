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

  /// text displaytext text text — local translated text refreshtext.
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
