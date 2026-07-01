import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/providers/mail_provider.dart';

/// R0001/0039 — "매우매우 느린 리프레시": scrolling down triggered a refresh that
/// "fetched only a few items yet took forever". Root cause (client side): the 10s
/// background poll fired `syncInbox`, whose `loadInbox` *cleared* the list and
/// reloaded page 1 — snapping a deeply-scrolled list back to ~20 items every 10s
/// and discarding the pages the user had scrolled into. The fix routes the poll
/// through a *quiet* sync that merges the fresh head into the loaded list instead
/// of clearing it. These tests pin that the quiet refresh preserves already-loaded
/// pages, the load-more cursor, and surfaces newly received mail at the head.
class _CursorAdapter implements HttpClientAdapter {
  /// GET /mails responses keyed by the `cursor` query param ('' = first page).
  final Map<String, (int, Object?)> mailsByCursor;
  final List<String> calls = [];

  _CursorAdapter(this.mailsByCursor);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST' && options.path == '/sync') {
      calls.add('POST /sync');
      return _json({
        'ok': true,
        'data': {'state': 'idle', 'applied': 0}
      }, 202);
    }
    if (options.method == 'GET' && options.path == '/mails') {
      final cursor = (options.queryParameters['cursor'] ?? '').toString();
      calls.add('GET /mails?cursor=$cursor');
      final entry = mailsByCursor[cursor];
      if (entry == null) {
        return _json({
          'ok': true,
          'data': <dynamic>[],
          'meta': {'has_more': false}
        }, 200);
      }
      final (status, body) = entry;
      return _json(body, status);
    }
    calls.add('${options.method} ${options.path}');
    return _json({
      'ok': false,
      'error': {'code': 'MAIL_NOT_FOUND', 'message': 'no route'}
    }, 404);
  }

  ResponseBody _json(Object? body, int status) => ResponseBody.fromString(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        },
      );

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _mail(String id) => {
      'mail_id': id,
      'from': {'email': '$id@example.com', 'name': id},
      'subject': 'subject $id',
      'is_read': false,
    };

(int, Object?) _page(List<String> ids, {String? nextCursor}) => (
      200,
      {
        'ok': true,
        'data': ids.map(_mail).toList(),
        'meta': {
          'next_cursor': nextCursor,
          'has_more': nextCursor != null,
          'count': ids.length,
        }
      }
    );

Dio _dio(_CursorAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  group('MailProvider quiet background refresh (R0001/0039)', () {
    test(
        'quiet refresh preserves already-loaded pages + cursor (does NOT reset to page 1)',
        () async {
      final adapter = _CursorAdapter({
        // First page (initial load).
        '': _page(['m1', 'm2'], nextCursor: '2'),
        // Second page (after one loadMore).
        '2': _page(['m3', 'm4'], nextCursor: '4'),
      });
      final provider = MailProvider(_dio(adapter));

      // Initial load + one scroll load-more → 4 mails across two pages.
      await provider.loadInbox();
      await provider.loadMore();
      expect(provider.mails.map((m) => m.mailId).toList(),
          ['m1', 'm2', 'm3', 'm4']);
      expect(provider.hasMore, isTrue);

      // A new mail (m0) arrives; the quiet poll's fresh first page now leads with it.
      adapter.mailsByCursor[''] = _page(['m0', 'm1', 'm2'], nextCursor: '2');

      await provider.syncInbox(quiet: true);

      // ★ Load-bearing: the deeper pages (m3, m4) the user scrolled into are STILL
      // present — the list was NOT snapped back to page 1. The new mail (m0) shows
      // at the head, and the load-more cursor is not rewound (continued scroll works).
      expect(provider.mails.map((m) => m.mailId).toList(),
          ['m0', 'm1', 'm2', 'm3', 'm4'],
          reason:
              '조용한 백그라운드 리프레시가 이미 로드된 페이지(m3,m4)를 버리고 1페이지로 리셋하면 안 된다');
      expect(provider.hasMore, isTrue);

      // The quiet refresh went through sync + a single first-page fetch (cursor '').
      expect(adapter.calls, contains('POST /sync'));
      expect(adapter.calls.last, 'GET /mails?cursor=');
    });

    test('quiet refresh is a no-op while a non-quiet load is already in flight',
        () async {
      final adapter = _CursorAdapter({
        '': _page(['m1'], nextCursor: null),
      });
      final provider = MailProvider(_dio(adapter));
      await provider.loadInbox();

      // Kick off a non-quiet sync (sets _isLoading) but do not await it, then fire a
      // quiet refresh: the quiet one must bail immediately without a second sync.
      final pending = provider.syncInbox(); // non-quiet, in flight
      await provider.syncInbox(quiet: true); // should early-return (guarded)
      await pending;

      // Exactly one POST /sync happened (from the non-quiet call); the quiet call
      // did not add a second sync.
      expect(adapter.calls.where((c) => c == 'POST /sync').length, 1);
    });
  });
}
