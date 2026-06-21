import '../models/mail.dart';

/// 작성/발송 페이로드 조립 + 사전 검증 — P0007 §7.5/§7.6, L0012 §1/§2.4/§4.1.
///
/// 클라이언트 검증은 best-effort 선검사다(최종 권위는 서버 — L0012 §2.4).
/// 서버가 RECIPIENT_INVALID(422)/VALIDATION_FAILED(400)을 돌려주면 작성 내용을
/// 보존하고 해당 필드를 표시한다(P0007 §7.7 / L0010 USER_ACTION).

/// L0012 §2.4.1 — 작성 모드. 답장/전달은 원본에서 수신자·제목을 파생한다.
enum ComposeMode { newMail, reply, replyAll, forward }

/// L0012 §1 한도.
const int kRecipientsMax = 100; // to+cc+bcc 합산
const int kSubjectMaxChars = 998; // RFC 5322 라인 한도

/// 간이 이메일 형식 검사(L0012 §2.4 is_valid_email의 클라 선검사).
/// 서버 검증을 대체하지 않는다 — 명백한 오타만 거른다.
final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isValidEmail(String address) => _emailRe.hasMatch(address.trim());

/// 자유 입력 문자열을 주소 목록으로 분해한다(쉼표/세미콜론/공백/줄바꿈 구분).
/// 빈 토큰·중복(소문자 기준)은 제거하고 입력 순서를 보존한다. 형식 검증은
/// 하지 않는다 — 칩 표시 단계에서 `isValidEmail` 로 무효 주소를 강조한다.
/// 수신자 태그 입력 위젯(RecipientField)과 작성 화면이 공유하는 순수 함수.
List<MailAddress> parseAddresses(String raw) {
  final seen = <String>{};
  final out = <MailAddress>[];
  for (final tok in raw.split(RegExp(r'[,;\s]+'))) {
    final s = tok.trim();
    if (s.isEmpty) continue;
    if (seen.add(s.toLowerCase())) out.add(MailAddress(address: s));
  }
  return out;
}

/// 검증 결과 — 비어 있으면 통과.
class ComposeValidation {
  /// 형식이 잘못된 주소(원본 문자열).
  final List<String> invalidAddresses;

  /// 수신자 0명.
  final bool noRecipients;

  /// 수신자 한도 초과.
  final bool tooManyRecipients;

  /// 제목 길이 초과(절단 권고).
  final bool subjectTooLong;

  const ComposeValidation({
    this.invalidAddresses = const [],
    this.noRecipients = false,
    this.tooManyRecipients = false,
    this.subjectTooLong = false,
  });

  bool get ok =>
      invalidAddresses.isEmpty &&
      !noRecipients &&
      !tooManyRecipients &&
      !subjectTooLong;
}

/// 발송 페이로드 — P0007 §7.5(새 메일)/§7.6(답장·전달).
class SendPayload {
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final String subject;
  final MailBody body;
  final List<String> attachmentIds;

  /// 답장/전달일 때만 — 원본 메일 id.
  final String? inReplyTo;

  /// "reply" | "reply_all" | "forward" (P0007 §7.6). 새 메일이면 null.
  final String? replyType;

  /// 초안에서 발송할 때 — 발송 후 서버가 초안 삭제·첨부 재귀속(L0012 §2.4).
  final String? fromDraftId;

  const SendPayload({
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.body = const MailBody(),
    this.attachmentIds = const [],
    this.inReplyTo,
    this.replyType,
    this.fromDraftId,
  });

  /// 발송 전 사전 검증(L0012 §4.1 평가 순서를 클라에서 선반영).
  ComposeValidation validate() {
    final all = [...to, ...cc, ...bcc];
    final invalid = all
        .where((a) => !isValidEmail(a.address))
        .map((a) => a.address)
        .toList();
    return ComposeValidation(
      invalidAddresses: invalid,
      noRecipients: all.isEmpty,
      tooManyRecipients: all.length > kRecipientsMax,
      subjectTooLong: subject.length > kSubjectMaxChars,
    );
  }

  Map<String, dynamic> toJson() {
    List<Map<String, dynamic>> addrs(List<MailAddress> xs) => xs
        .map((a) => {
              if (a.name.isNotEmpty) 'name': a.name,
              'address': a.address,
            })
        .toList();
    return {
      'to': addrs(to),
      if (cc.isNotEmpty) 'cc': addrs(cc),
      if (bcc.isNotEmpty) 'bcc': addrs(bcc),
      'subject': subject,
      'body': {'format': body.format, 'content': body.content},
      if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
      if (inReplyTo != null) 'in_reply_to': inReplyTo,
      if (replyType != null) 'reply_type': replyType,
      if (fromDraftId != null) 'from_draft_id': fromDraftId,
    };
  }
}

/// L0012 §2.4.1 — 원본 메일에서 답장/전달 초기 폼을 파생한다.
/// `selfAddress`는 reply_all에서 자기 자신을 cc에서 제외하는 데 쓴다.
SendPayload composeFrom(
  ComposeMode mode,
  MailDetail original, {
  String selfAddress = '',
}) {
  String quote(MailDetail m) {
    final header = '\n\n----- Original message -----\n'
        'From: ${m.from.address}\n'
        'Subject: ${m.subject}\n\n';
    return header + m.body.content;
  }

  switch (mode) {
    case ComposeMode.reply:
      return SendPayload(
        to: [original.from],
        subject: _withPrefix('Re: ', original.subject),
        body: const MailBody(),
        inReplyTo: original.mailId,
        replyType: 'reply',
      );
    case ComposeMode.replyAll:
      final cc = [...original.to, ...original.cc]
          .where((a) =>
              a.address.isNotEmpty &&
              a.address != selfAddress &&
              a.address != original.from.address)
          .toList();
      return SendPayload(
        to: [original.from],
        cc: cc,
        subject: _withPrefix('Re: ', original.subject),
        body: const MailBody(),
        inReplyTo: original.mailId,
        replyType: 'reply_all',
      );
    case ComposeMode.forward:
      return SendPayload(
        to: const [],
        subject: _withPrefix('Fwd: ', original.subject),
        body: MailBody(format: 'text', content: quote(original)),
        inReplyTo: original.mailId,
        replyType: 'forward',
      );
    case ComposeMode.newMail:
      return const SendPayload();
  }
}

String _withPrefix(String prefix, String subject) {
  if (subject.toLowerCase().startsWith(prefix.toLowerCase())) return subject;
  return '$prefix$subject';
}
