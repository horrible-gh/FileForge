import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/models/mail.dart';
import 'package:file_forge_app/services/mail_compose.dart';

void main() {
  group('isValidEmail', () {
    test('accepts well-formed, rejects malformed', () {
      expect(isValidEmail('a@b.com'), true);
      expect(isValidEmail('  user@example.co.kr '), true);
      expect(isValidEmail('broken-address'), false);
      expect(isValidEmail('a@b'), false);
      expect(isValidEmail('a b@c.com'), false);
      expect(isValidEmail(''), false);
    });
  });

  group('parseAddresses (translated text text text)', () {
    test('splits on comma/semicolon/whitespace, drops empties', () {
      final xs = parseAddresses('a@x.com, b@y.com; c@z.com  d@w.com');
      expect(xs.map((e) => e.address).toList(),
          ['a@x.com', 'b@y.com', 'c@z.com', 'd@w.com']);
    });

    test('dedupes case-insensitively, preserves first occurrence order', () {
      final xs = parseAddresses('A@x.com, b@y.com, a@x.com');
      expect(xs.map((e) => e.address).toList(), ['A@x.com', 'b@y.com']);
    });

    test('empty / separators-only → empty list', () {
      expect(parseAddresses(''), isEmpty);
      expect(parseAddresses('  ,; \n '), isEmpty);
    });

    test('keeps malformed tokens (verifytext text display stage text)', () {
      final xs = parseAddresses('ok@x.com, broken-address');
      expect(xs.map((e) => e.address).toList(), ['ok@x.com', 'broken-address']);
    });
  });

  group('SendPayload.validate (L0012 §4.1)', () {
    SendPayload p(List<String> to, {String subject = 'hi'}) => SendPayload(
          to: to.map((a) => MailAddress(address: a)).toList(),
          subject: subject,
        );

    test('no recipients flagged', () {
      final v = p([]).validate();
      expect(v.noRecipients, true);
      expect(v.ok, false);
    });

    test('invalid address flagged', () {
      final v = p(['ok@a.com', 'bad']).validate();
      expect(v.invalidAddresses, ['bad']);
      expect(v.ok, false);
    });

    test('too many recipients flagged', () {
      final many = List.generate(kRecipientsMax + 1, (i) => 'u$i@a.com');
      final v = p(many).validate();
      expect(v.tooManyRecipients, true);
    });

    test('subject too long flagged', () {
      final v = p(['ok@a.com'], subject: 'x' * (kSubjectMaxChars + 1)).validate();
      expect(v.subjectTooLong, true);
    });

    test('valid payload passes', () {
      expect(p(['ok@a.com']).validate().ok, true);
    });
  });

  group('SendPayload.toJson (P0007 §7.5/§7.6)', () {
    test('new mail omits empty cc/bcc/reply fields', () {
      final json = SendPayload(
        to: [const MailAddress(name: 'Boss', address: 'boss@x.com')],
        subject: 'Weekly report',
        body: const MailBody(format: 'text', content: 'Body'),
      ).toJson();
      expect(json['to'], [
        {'name': 'Boss', 'address': 'boss@x.com'}
      ]);
      expect(json.containsKey('cc'), false);
      expect(json.containsKey('in_reply_to'), false);
      expect(json['body'], {'format': 'text', 'content': 'Body'});
    });

    test('attachment_ids included when present, omitted when empty (§7.11)', () {
      final withAtt = SendPayload(
        to: [const MailAddress(address: 'a@b.com')],
        attachmentIds: const ['a_91be', 'a_77c1'],
      ).toJson();
      expect(withAtt['attachment_ids'], ['a_91be', 'a_77c1']);
      final noAtt = SendPayload(
        to: [const MailAddress(address: 'a@b.com')],
      ).toJson();
      expect(noAtt.containsKey('attachment_ids'), false);
    });

    test('html body carries format=html (HTML compose)', () {
      final json = SendPayload(
        to: [const MailAddress(address: 'a@b.com')],
        body: const MailBody(format: 'html', content: '<p>hi</p>'),
      ).toJson();
      expect(json['body'], {'format': 'html', 'content': '<p>hi</p>'});
    });

    test('reply carries in_reply_to + reply_type', () {
      final json = SendPayload(
        to: [const MailAddress(address: 'a@b.com')],
        subject: 'Re: x',
        inReplyTo: 'm_1',
        replyType: 'reply',
      ).toJson();
      expect(json['in_reply_to'], 'm_1');
      expect(json['reply_type'], 'reply');
    });
  });

  group('composeFrom (L0012 §2.4.1)', () {
    final original = MailDetail(
      mailId: 'm_orig',
      from: const MailAddress(name: 'Billing Team', address: 'billing@shop.com'),
      to: [
        const MailAddress(address: 'me@example.com'),
        const MailAddress(address: 'peer@example.com'),
      ],
      cc: [const MailAddress(address: 'cc@example.com')],
      subject: 'June receipt',
      body: const MailBody(format: 'text', content: 'Original body'),
    );

    test('reply → to=text from, Re: translated text, in_reply_to', () {
      final r = composeFrom(ComposeMode.reply, original);
      expect(r.to.single.address, 'billing@shop.com');
      expect(r.subject, 'Re: June receipt');
      expect(r.inReplyTo, 'm_orig');
      expect(r.replyType, 'reply');
    });

    test('reply_all → cc=text to+cc text self·from text', () {
      final r = composeFrom(ComposeMode.replyAll, original,
          selfAddress: 'me@example.com');
      expect(r.to.single.address, 'billing@shop.com');
      final ccAddrs = r.cc.map((a) => a.address).toList();
      expect(ccAddrs.contains('me@example.com'), false); // self text
      expect(ccAddrs.contains('billing@shop.com'), false); // from text
      expect(ccAddrs.contains('peer@example.com'), true);
      expect(ccAddrs.contains('cc@example.com'), true);
    });

    test('forward → Fwd: translated text, Bodytext text text, to text', () {
      final r = composeFrom(ComposeMode.forward, original);
      expect(r.subject, 'Fwd: June receipt');
      expect(r.to, isEmpty);
      expect(r.body.content.contains('Original body'), true);
      expect(r.replyType, 'forward');
    });

    test('text Re: text text translated text text translated text text text', () {
      final once = composeFrom(ComposeMode.reply, original);
      final twice = composeFrom(
        ComposeMode.reply,
        MailDetail(
            mailId: 'm2',
            from: const MailAddress(address: 'x@y.com'),
            subject: once.subject),
      );
      expect(twice.subject, 'Re: June receipt'); // Re: Re: text
    });
  });

  // R0001(0035) — sender (From) account selection across multiple linked accounts.
  group('sender account selection', () {
    test('toJson emits from_account_id only when set', () {
      final without = const SendPayload(
        to: [MailAddress(address: 'x@y.com')],
      ).toJson();
      expect(without.containsKey('from_account_id'), false);

      final withId = const SendPayload(
        to: [MailAddress(address: 'x@y.com')],
        fromAccountId: 'acc-b',
      ).toJson();
      expect(withId['from_account_id'], 'acc-b');
    });

    test('reply/forward default sender to the receiving account', () {
      final original = MailDetail(
        mailId: 'm1',
        accountId: 'acc-b',
        from: const MailAddress(address: 'billing@shop.com'),
        subject: 'Receipt',
        body: const MailBody(format: 'text', content: 'body'),
      );
      expect(composeFrom(ComposeMode.reply, original).fromAccountId, 'acc-b');
      expect(composeFrom(ComposeMode.replyAll, original).fromAccountId, 'acc-b');
      expect(composeFrom(ComposeMode.forward, original).fromAccountId, 'acc-b');
    });

    test('reply leaves sender null when original carries no receiving account', () {
      final original = MailDetail(
        mailId: 'm1',
        from: const MailAddress(address: 'billing@shop.com'),
        subject: 'Receipt',
      );
      expect(composeFrom(ComposeMode.reply, original).fromAccountId, isNull);
    });

    test('MailDetail.fromJson reads account_id', () {
      final d = MailDetail.fromJson({
        'mail_id': 'm1',
        'account_id': 'acc-b',
        'from': {'address': 'a@b.com'},
      });
      expect(d.accountId, 'acc-b');
    });
  });
}
