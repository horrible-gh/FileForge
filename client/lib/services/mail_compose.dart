import '../models/mail.dart';

/// compose/text translated text text + text verify — P0007 §7.5/§7.6, L0012 §1/§2.4/§4.1.
///
/// translated text verifytext best-effort translated text(text translated text server — L0012 §2.4).
/// servertext RECIPIENT_INVALID(422)/VALIDATION_FAILED(400)text translated text compose contenttext
/// preservedtext text translated text displaytext(P0007 §7.7 / L0010 USER_ACTION).

/// L0012 §2.4.1 — compose text. text/translated text translated text translated text·translated text translated text.
enum ComposeMode { newMail, reply, replyAll, forward }

/// L0012 §1 text.
const int kRecipientsMax = 100; // to+cc+bcc text
const int kSubjectMaxChars = 998; // RFC 5322 text text

/// text translated text text text(L0012 §2.4 is_valid_emailtext text translated text).
/// server verifytext translated text translated text — translated text translated text translated text.
final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isValidEmail(String address) => _emailRe.hasMatch(address.trim());

/// text text stringtext text translated text minutestranslated text(text/translated text/text/translated text textminutes).
/// empty token·text(translated text text)text translated text text translated text preservedtext. text verifytext
/// text translated text — text display stagetext `isValidEmail` text text translated text translated text.
/// translated text text text text(RecipientField)text compose screentext translated text text text.
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

/// verify result — text translated text text.
class ComposeValidation {
  /// translated text translated text text(text string).
  final List<String> invalidAddresses;

  /// translated text 0text.
  final bool noRecipients;

  /// translated text text exceeded.
  final bool tooManyRecipients;

  /// text text exceeded(text text).
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

/// text translated text — P0007 §7.5(text text)/§7.6(text·text).
class SendPayload {
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final String subject;
  final MailBody body;
  final List<String> attachmentIds;

  /// text/translated text text — text text id.
  final String? inReplyTo;

  /// "reply" | "reply_all" | "forward" (P0007 §7.6). text translated text null.
  final String? replyType;

  /// Drafttext translated text text — text text servertext Draft delete·text translated text(L0012 §2.4).
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

  /// text text text verify(L0012 §4.1 text translated text translated text translated text).
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

/// L0012 §2.4.1 — text translated text text/text text text translated text.
/// `selfAddress`text reply_alltext text translated text cctext translated text text text.
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
