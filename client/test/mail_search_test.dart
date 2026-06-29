import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_forge_app/providers/mail_provider.dart';

/// B0001 / 0026 — "말 안듣는 검색엔진". 메일 검색이 MailProvider로 배선되지 않아
/// 메일 화면 검색이 무반응이었다(검색창이 FileProvider에만 연결). 이 테스트는
/// MailProvider의 검색 동작을 고정한다:
///   (1) searchMails 가 `GET /mails?q=` 를 보내고 목록을 결과로 교체하며 검색 모드가 됨
///   (2) 검색 중 loadMore 가 같은 `q` 를 유지함(다음 페이지도 검색 결과)
///   (3) clearSearch 가 q 없는 일반 목록으로 복귀하고 검색 모드를 해제함
class _RecordingAdapter implements HttpClientAdapter {
  /// (METHOD path) → (status, jsonBody).
  final Map<String, (int, Object?)> routes;

  /// 호출된 요청의 전체 URI(쿼리 포함)를 순서대로 기록 — `q` 전달을 검증한다.
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
