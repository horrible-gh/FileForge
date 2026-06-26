import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/models/mail.dart';
import 'package:file_forge_app/services/mail_envelope.dart';

void main() {
  group('MailAddress', () {
    test('parses name+address and falls back to address for display', () {
      final a = MailAddress.fromJson({'name': 'Billing Team', 'address': 'b@shop.com'});
      expect(a.name, 'Billing Team');
      expect(a.display, 'Billing Team');
      final b = MailAddress.fromJson({'address': 'b@shop.com'});
      expect(b.name, '');
      expect(b.display, 'b@shop.com');
    });
  });

  group('MailSummary', () {
    test('parses P0007 §3.1 shape', () {
      final s = MailSummary.fromJson({
        'mail_id': 'm_8f21',
        'thread_id': 't_4a90',
        'from': {'name': 'Billing Team', 'address': 'billing@shop.com'},
        'subject': 'June receipt',
        'snippet': 'Review details',
        'received_at': '2026-06-21T08:03:11Z',
        'is_read': false,
        'has_attachment': true,
        'labels': ['inbox', 'lbl_receipt'],
      });
      expect(s.mailId, 'm_8f21');
      expect(s.from.display, 'Billing Team');
      expect(s.isRead, false);
      expect(s.hasAttachment, true);
      expect(s.labels, ['inbox', 'lbl_receipt']);
    });

    test('copyWithRead flips read flag only', () {
      final s = MailSummary(mailId: 'm1', from: const MailAddress(address: 'a@b'));
      expect(s.isRead, false);
      final r = s.copyWithRead(true);
      expect(r.isRead, true);
      expect(r.mailId, 'm1');
    });

    test('tolerates missing fields', () {
      final s = MailSummary.fromJson({'mail_id': 'm2'});
      expect(s.mailId, 'm2');
      expect(s.subject, '');
      expect(s.labels, isEmpty);
      expect(s.from.address, '');
    });
  });

  group('MailDetail', () {
    test('parses to/cc/body/attachments (P0007 §3.2)', () {
      final d = MailDetail.fromJson({
        'mail_id': 'm_8f21',
        'from': {'name': 'Billing Team', 'address': 'billing@shop.com'},
        'to': [
          {'name': 'Hong Gil Dong', 'address': 'user@example.com'}
        ],
        'cc': [],
        'subject': 'June receipt',
        'received_at': '2026-06-21T08:03:11Z',
        'is_read': true,
        'body': {'format': 'html', 'content': '<p>Details</p>'},
        'attachments': [
          {
            'attachment_id': 'a_77c1',
            'filename': 'receipt.pdf',
            'size_bytes': 84213,
            'content_type': 'application/pdf'
          }
        ],
        'labels': ['inbox'],
      });
      expect(d.to.single.display, 'Hong Gil Dong');
      expect(d.cc, isEmpty);
      expect(d.body.isHtml, true);
      expect(d.attachments.single.sizeBytes, 84213);
    });
  });

  group('MailDraft (P0007 §6.2/§7.9)', () {
    test('parses to/cc/bcc/body/attachments + updated_at', () {
      final d = MailDraft.fromJson({
        'draft_id': 'd_5510',
        'to': [
          {'address': 'boss@example.com'}
        ],
        'cc': [
          {'address': 'peer@example.com'}
        ],
        'bcc': [],
        'subject': 'Weekly report(drafting)',
        'body': {'format': 'text', 'content': 'Draft...'},
        'attachments': [
          {'attachment_id': 'a_91be', 'filename': 'report.pdf', 'size_bytes': 10}
        ],
        'updated_at': '2026-06-21T10:30:00Z',
      });
      expect(d.draftId, 'd_5510');
      expect(d.to.single.address, 'boss@example.com');
      expect(d.cc.single.address, 'peer@example.com');
      expect(d.bcc, isEmpty);
      expect(d.subject, 'Weekly report(drafting)');
      expect(d.body.content, 'Draft...');
      expect(d.attachments.single.attachmentId, 'a_91be');
      expect(d.updatedAt, '2026-06-21T10:30:00Z'); // base_updated_at text
    });

    test('tolerates missing fields (merge stage Go backend compatibility)', () {
      final d = MailDraft.fromJson({'draft_id': 'd_1'});
      expect(d.draftId, 'd_1');
      expect(d.to, isEmpty);
      expect(d.attachments, isEmpty);
      expect(d.body.format, 'text');
      expect(d.updatedAt, '');
    });
  });

  group('MailPage (cursor pagination, P0007 §4)', () {
    test('builds from data + meta with next_cursor', () {
      final page = MailPage.fromEnvelopeParts(
        [
          {'mail_id': 'm1', 'from': {'address': 'a@b'}},
          {'mail_id': 'm2', 'from': {'address': 'c@d'}},
        ],
        {'next_cursor': 'c_xyz', 'has_more': true, 'count': 2},
      );
      expect(page.items.length, 2);
      expect(page.nextCursor, 'c_xyz');
      expect(page.hasMore, true);
      expect(page.count, 2);
    });

    test('last page: has_more false, next_cursor null', () {
      final page = MailPage.fromEnvelopeParts(
        [
          {'mail_id': 'm3', 'from': {'address': 'a@b'}},
        ],
        {'next_cursor': null, 'has_more': false, 'count': 1},
      );
      expect(page.hasMore, false);
      expect(page.nextCursor, isNull);
    });
  });

  group('Envelope (P0007 §1) + classification (L0010 §2.3)', () {
    test('unwrapEnvelope returns data on success', () {
      final data = unwrapEnvelope({
        'ok': true,
        'data': {'mail_id': 'm1'},
        'meta': {'count': 1},
      });
      expect((data as Map)['mail_id'], 'm1');
    });

    test('envelopeMeta extracts meta', () {
      final meta = envelopeMeta({
        'ok': true,
        'data': [],
        'meta': {'next_cursor': 'c_1', 'has_more': true},
      });
      expect(meta?['next_cursor'], 'c_1');
    });

    test('unwrapEnvelope throws typed exception on error envelope', () {
      expect(
        () => unwrapEnvelope({
          'ok': false,
          'error': {
            'code': 'MAIL_NOT_FOUND',
            'message': 'None',
            'request_id': 'req_1',
          },
        }, httpStatus: 404),
        throwsA(isA<MailApiException>()
            .having((e) => e.code, 'code', 'MAIL_NOT_FOUND')
            .having((e) => e.category, 'category', MailErrorCategory.notFound)
            .having((e) => e.httpStatus, 'httpStatus', 404)
            .having((e) => e.requestId, 'requestId', 'req_1')),
      );
    });

    test('malformed body → MALFORMED_RESPONSE generic', () {
      expect(
        () => unwrapEnvelope('not-a-map'),
        throwsA(isA<MailApiException>()
            .having((e) => e.code, 'code', 'MALFORMED_RESPONSE')
            .having((e) => e.category, 'category', MailErrorCategory.generic)),
      );
    });

    test('expectMapData returns typed map for object data', () {
      final m = expectMapData({'draft_id': 'd1', 'updated_at': 't'});
      expect(m, isA<Map<String, dynamic>>());
      expect(m['draft_id'], 'd1');
    });

    test('expectMapData on non-Map success data → MALFORMED_RESPONSE (not TypeError)',
        () {
      // NR0016 §3 MINOR #2: ok:true text datatext text-Maptext translated text successtext.
      expect(
        () => expectMapData('not-an-object', httpStatus: 200),
        throwsA(isA<MailApiException>()
            .having((e) => e.code, 'code', 'MALFORMED_RESPONSE')
            .having((e) => e.httpStatus, 'httpStatus', 200)),
      );
      expect(() => expectMapData([1, 2, 3]),
          throwsA(isA<MailApiException>()));
    });

    test('expectListData returns list for array data; null → empty', () {
      expect(expectListData([1, 2]), [1, 2]);
      expect(expectListData(null), isEmpty);
    });

    test('expectListData on non-List success data → MALFORMED_RESPONSE', () {
      expect(
        () => expectListData({'not': 'a list'}, httpStatus: 200),
        throwsA(isA<MailApiException>()
            .having((e) => e.code, 'code', 'MALFORMED_RESPONSE')),
      );
    });

    test('classifyMailErrorCode maps all P0007 §5 catalogue codes', () {
      expect(classifyMailErrorCode('TOKEN_EXPIRED'),
          MailErrorCategory.refreshable);
      expect(classifyMailErrorCode('TOKEN_INVALID'), MailErrorCategory.auth);
      expect(classifyMailErrorCode('FORBIDDEN'), MailErrorCategory.auth);
      expect(classifyMailErrorCode('AUTH_INVALID_CREDENTIALS'),
          MailErrorCategory.auth);
      expect(classifyMailErrorCode('UPSTREAM_UNAVAILABLE'),
          MailErrorCategory.transient);
      expect(classifyMailErrorCode('SEND_FAILED'), MailErrorCategory.transient);
      expect(classifyMailErrorCode('VALIDATION_FAILED'),
          MailErrorCategory.userAction);
      expect(classifyMailErrorCode('RECIPIENT_INVALID'),
          MailErrorCategory.userAction);
      expect(classifyMailErrorCode('DRAFT_CONFLICT'),
          MailErrorCategory.userAction);
      expect(classifyMailErrorCode('LABEL_DUPLICATE'),
          MailErrorCategory.userAction);
      expect(classifyMailErrorCode('ATTACHMENT_NOT_FOUND'),
          MailErrorCategory.notFound);
      expect(classifyMailErrorCode('LABEL_NOT_FOUND'),
          MailErrorCategory.notFound);
      expect(classifyMailErrorCode('SOMETHING_NEW'),
          MailErrorCategory.generic);
    });
  });
}
