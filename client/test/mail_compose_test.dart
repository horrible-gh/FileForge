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

  group('parseAddresses (수신자 태그 입력)', () {
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

    test('keeps malformed tokens (검증은 칩 표시 단계 담당)', () {
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
        to: [const MailAddress(name: '보스', address: 'boss@x.com')],
        subject: '주간 보고',
        body: const MailBody(format: 'text', content: '본문'),
      ).toJson();
      expect(json['to'], [
        {'name': '보스', 'address': 'boss@x.com'}
      ]);
      expect(json.containsKey('cc'), false);
      expect(json.containsKey('in_reply_to'), false);
      expect(json['body'], {'format': 'text', 'content': '본문'});
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

    test('html body carries format=html (HTML 작성)', () {
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
      from: const MailAddress(name: '결제팀', address: 'billing@shop.com'),
      to: [
        const MailAddress(address: 'me@example.com'),
        const MailAddress(address: 'peer@example.com'),
      ],
      cc: [const MailAddress(address: 'cc@example.com')],
      subject: '6월 영수증',
      body: const MailBody(format: 'text', content: '원문 본문'),
    );

    test('reply → to=원본 from, Re: 프리픽스, in_reply_to', () {
      final r = composeFrom(ComposeMode.reply, original);
      expect(r.to.single.address, 'billing@shop.com');
      expect(r.subject, 'Re: 6월 영수증');
      expect(r.inReplyTo, 'm_orig');
      expect(r.replyType, 'reply');
    });

    test('reply_all → cc=원본 to+cc 에서 self·from 제외', () {
      final r = composeFrom(ComposeMode.replyAll, original,
          selfAddress: 'me@example.com');
      expect(r.to.single.address, 'billing@shop.com');
      final ccAddrs = r.cc.map((a) => a.address).toList();
      expect(ccAddrs.contains('me@example.com'), false); // self 제외
      expect(ccAddrs.contains('billing@shop.com'), false); // from 제외
      expect(ccAddrs.contains('peer@example.com'), true);
      expect(ccAddrs.contains('cc@example.com'), true);
    });

    test('forward → Fwd: 프리픽스, 본문에 원문 인용, to 비움', () {
      final r = composeFrom(ComposeMode.forward, original);
      expect(r.subject, 'Fwd: 6월 영수증');
      expect(r.to, isEmpty);
      expect(r.body.content.contains('원문 본문'), true);
      expect(r.replyType, 'forward');
    });

    test('이미 Re: 가 붙은 제목은 중복 프리픽스 안 함', () {
      final once = composeFrom(ComposeMode.reply, original);
      final twice = composeFrom(
        ComposeMode.reply,
        MailDetail(
            mailId: 'm2',
            from: const MailAddress(address: 'x@y.com'),
            subject: once.subject),
      );
      expect(twice.subject, 'Re: 6월 영수증'); // Re: Re: 아님
    });
  });
}
