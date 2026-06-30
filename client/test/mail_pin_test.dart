import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/models/mail.dart';
import 'package:file_forge_app/providers/mail_provider.dart';

/// R0001 — mail pin feature (fileforge.mailanchorpython.0027). Pins down the client end of
/// the wiring gap NR0003 identified: (1) MailSummary/MailDetail parse the server's `is_pinned`,
/// (2) MailProvider.togglePin sends PATCH `{is_pinned}` and optimistically floats the pin
/// to the top of the list (same visual result as the server's `ORDER BY is_pinned DESC`),
/// (3) reverts to the original state on server PATCH failure.
class _StubAdapter implements HttpClientAdapter {
  final Map<String, (int, Object?)> routes;
  final List<String> calls = [];
  final List<Object?> bodies = [];
  bool failPatch;

  _StubAdapter(this.routes, {this.failPatch = false});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    calls.add(key);
    bodies.add(options.data);
    if (failPatch && options.method == 'PATCH') {
      throw DioException(requestOptions: options, message: 'boom');
    }
    final entry = routes[key];
    if (entry == null) {
      return ResponseBody.fromString(
          '{"ok":false,"error":{"code":"MAIL_NOT_FOUND","message":"no route"}}',
          404,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    }
    final (status, body) = entry;
    final text = body == null ? '' : jsonEncode(body);
    return ResponseBody.fromString(text, status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_StubAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = adapter;
  return dio;
}

Map<String, dynamic> _row(String id, {bool pinned = false}) => {
      'mail_id': id,
      'from': {'address': '$id@ext.com'},
      'subject': 's_$id',
      'received_at': '2026-06-21T08:00:00Z',
      'is_read': true,
      'is_pinned': pinned,
    };

void main() {
  group('MailSummary/MailDetail pin parsing', () {
    test('parses is_pinned (defaults false when absent)', () {
      expect(MailSummary.fromJson(_row('m1', pinned: true)).isPinned, true);
      expect(MailSummary.fromJson(_row('m2')).isPinned, false);
      expect(MailSummary.fromJson({'mail_id': 'm3'}).isPinned, false);

      final d = MailDetail.fromJson({
        'mail_id': 'm4',
        'from': {'address': 'a@b'},
        'is_pinned': true,
      });
      expect(d.isPinned, true);
    });

    test('copyWithPinned flips only the pin flag and preserves the rest', () {
      final s = MailSummary.fromJson(_row('m1'));
      final p = s.copyWithPinned(true);
      expect(p.isPinned, true);
      expect(p.mailId, 'm1');
      expect(p.isRead, s.isRead);
      // copyWithRead must not disturb the pin flag.
      expect(p.copyWithRead(false).isPinned, true);
    });
  });

  group('MailProvider.togglePin', () {
    test('sends PATCH {is_pinned:true} and floats the pinned mail to the top',
        () async {
      final adapter = _StubAdapter({
        'GET /mails': (
          200,
          {
            'ok': true,
            'data': [_row('m1'), _row('m2'), _row('m3')],
            'meta': {'has_more': false}
          }
        ),
        'PATCH /mails/m3': (200, {'ok': true, 'data': {'mail_id': 'm3', 'is_pinned': true}}),
      });
      final provider = MailProvider(_dioWith(adapter));
      await provider.loadInbox();
      expect(provider.mails.map((m) => m.mailId).toList(), ['m1', 'm2', 'm3']);

      await provider.togglePin('m3');

      // PATCH issued with the pin flag.
      expect(adapter.calls, contains('PATCH /mails/m3'));
      final patchBody =
          adapter.bodies[adapter.calls.indexOf('PATCH /mails/m3')] as Map;
      expect(patchBody['is_pinned'], true);
      // m3 now pinned and floated to the front; the rest keep their order.
      expect(provider.mails.first.mailId, 'm3');
      expect(provider.mails.first.isPinned, true);
      expect(provider.mails.map((m) => m.mailId).toList(), ['m3', 'm1', 'm2']);
    });

    test(
        'partitions into pinned tray / chronological rest (R0001/0027 tray UX)',
        () async {
      final adapter = _StubAdapter({
        'GET /mails': (
          200,
          {
            'ok': true,
            'data': [
              _row('m1', pinned: true),
              _row('m2'),
              _row('m3', pinned: true),
              _row('m4'),
            ],
            'meta': {'has_more': false}
          }
        ),
        'PATCH /mails/m2': (200, {'ok': true, 'data': {'mail_id': 'm2', 'is_pinned': true}}),
        'PATCH /mails/m1': (200, {'ok': true, 'data': {'mail_id': 'm1', 'is_pinned': false}}),
      });
      final provider = MailProvider(_dioWith(adapter));
      await provider.loadInbox();

      // Initial partition: pinned go to the tray, the rest to the body list —
      // pinned are NOT duplicated into the chronological list.
      expect(provider.pinnedMails.map((m) => m.mailId).toList(), ['m1', 'm3']);
      expect(provider.unpinnedMails.map((m) => m.mailId).toList(), ['m2', 'm4']);

      // Pinning m2 moves it from the body list into the tray immediately.
      // The tray keeps the stable original position order (m2 sits between the
      // already-pinned m1 and m3, matching the server's is_pinned-first sort).
      await provider.togglePin('m2');
      expect(provider.pinnedMails.map((m) => m.mailId).toList(),
          ['m1', 'm2', 'm3']);
      expect(provider.unpinnedMails.map((m) => m.mailId).toList(), ['m4']);

      // Unpinning m1 drops it back out of the tray into the body list.
      await provider.togglePin('m1');
      expect(provider.pinnedMails.any((m) => m.mailId == 'm1'), false);
      expect(provider.unpinnedMails.map((m) => m.mailId).toList(),
          contains('m1'));
    });

    test('reverts optimistic pin when the server PATCH fails', () async {
      final adapter = _StubAdapter({
        'GET /mails': (
          200,
          {
            'ok': true,
            'data': [_row('m1'), _row('m2')],
            'meta': {'has_more': false}
          }
        ),
      }, failPatch: true);
      final provider = MailProvider(_dioWith(adapter));
      await provider.loadInbox();

      await provider.togglePin('m2');

      // PATCH was attempted but failed → state rolled back (no pin, order intact).
      expect(adapter.calls, contains('PATCH /mails/m2'));
      final m2 = provider.mails.firstWhere((m) => m.mailId == 'm2');
      expect(m2.isPinned, false);
      expect(provider.mails.map((m) => m.mailId).toList(), ['m1', 'm2']);
    });
  });
}
