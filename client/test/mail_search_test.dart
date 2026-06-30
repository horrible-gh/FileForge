import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/providers/mail_provider.dart';

/// B0001 / 0026 — "the search engine that won't listen". Mail search wasn't wired to
/// MailProvider, so search on the mail screen was unresponsive (the search box was only
/// connected to FileProvider). This test pins MailProvider's search behaviour:
///   (1) searchMails sends `GET /mails?q=`, replaces the list with the results, and enters search mode
///   (2) loadMore keeps the same `q` while searching (next page is also a search result)
///   (3) clearSearch returns to the plain q-less list and exits search mode
class _RecordingAdapter implements HttpClientAdapter {
  /// (METHOD path) → (status, jsonBody).
  final Map<String, (int, Object?)> routes;

  /// Records the full URI (incl. query) of each request in order — verifies `q` is passed.
  final List<Uri> uris = [];

  _RecordingAdapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    uris.add(options.uri);
    final key = '${options.method} ${options.path}';
    final entry = routes[key];
    if (entry == null) {
      return ResponseBody.fromString(
        '{"ok":false,"error":{"code":"MAIL_NOT_FOUND","message":"no route"}}',
        404,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        },
      );
    }
    final (status, body) = entry;
    return ResponseBody.fromString(body == null ? '' : jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = adapter;
  return dio;
}

Map<String, Object?> _item(String id, String subject) => {
      'mail_id': id,
      'subject': subject,
      'snippet': '',
      'from': {'name': 'A', 'address': 'a@b.c'},
      'is_read': true,
      'labels': ['inbox'],
    };

Object _page(List<Map<String, Object?>> items,
        {bool hasMore = false, String? next}) =>
    {
      'ok': true,
      'data': items,
      'meta': {'has_more': hasMore, if (next != null) 'next_cursor': next},
    };

void main() {
  group('MailProvider search wiring (B0001/0026)', () {
    test('searchMails sends q and replaces the list, entering search mode',
        () async {
      final adapter = _RecordingAdapter({
        'GET /mails': (200, _page([_item('hit-1', 'invoice')])),
      });
      final provider = MailProvider(_dioWith(adapter));

      await provider.searchMails('invoice');

      // the request carried the search term as ?q=
      expect(adapter.uris.single.queryParameters['q'], 'invoice');
      // the list now holds the search hit and the provider is in search mode
      expect(provider.mails.map((m) => m.mailId), ['hit-1']);
      expect(provider.isSearchMode, isTrue);
      expect(provider.searchQuery, 'invoice');
    });

    test('blank query does not search and is not a search', () async {
      final adapter = _RecordingAdapter({
        'GET /mails': (200, _page([_item('x', 'x')])),
      });
      final provider = MailProvider(_dioWith(adapter));

      await provider.searchMails('   ');
      // blank → clearSearch short-circuits (nothing was searching), no request
      expect(adapter.uris, isEmpty);
      expect(provider.isSearchMode, isFalse);
    });

    test('loadMore keeps q while searching (next page stays scoped)', () async {
      final adapter = _RecordingAdapter({
        'GET /mails': (200, _page([_item('p1', 'a')], hasMore: true, next: '20')),
      });
      final provider = MailProvider(_dioWith(adapter));

      await provider.searchMails('report');
      await provider.loadMore();

      expect(adapter.uris.length, 2);
      // both the first search page and the next page carry q=report
      expect(adapter.uris[0].queryParameters['q'], 'report');
      expect(adapter.uris[1].queryParameters['q'], 'report');
      expect(adapter.uris[1].queryParameters['cursor'], '20');
    });

    test('clearSearch returns to the un-scoped list and exits search mode',
        () async {
      final adapter = _RecordingAdapter({
        'GET /mails': (200, _page([_item('all-1', 'a')])),
      });
      final provider = MailProvider(_dioWith(adapter));

      await provider.searchMails('needle');
      expect(provider.isSearchMode, isTrue);

      await provider.clearSearch();

      expect(provider.isSearchMode, isFalse);
      expect(provider.searchQuery, isEmpty);
      // the reload (loadInbox) did NOT carry q
      expect(adapter.uris.last.queryParameters.containsKey('q'), isFalse);
    });

    test('loadInbox clears a stale search query', () async {
      final adapter = _RecordingAdapter({
        'GET /mails': (200, _page([_item('i', 'i')])),
      });
      final provider = MailProvider(_dioWith(adapter));

      await provider.searchMails('stale');
      expect(provider.isSearchMode, isTrue);

      await provider.loadInbox();
      expect(provider.isSearchMode, isFalse);
    });
  });
}
