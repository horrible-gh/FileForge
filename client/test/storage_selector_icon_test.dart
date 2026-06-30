import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/providers/storage_provider.dart';
import 'package:file_forge_app/widgets/storage_selector.dart';

/// R0001 (fileforge.mailanchorpython.0034) / NR0004 §3 — the storage switcher used
/// to render *every* storage type with the same `Icons.storage_rounded`, so a mail
/// box / SecureBolt vault was visually indistinguishable from a plain file storage.
/// This guard is load-bearing: revert `_storageTypeIcon` to a single glyph and the
/// per-type expectations below go RED.
class _StoragesStub implements HttpClientAdapter {
  final List<Map<String, dynamic>> storages;
  _StoragesStub(this.storages);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('get_user_storages')) {
      return ResponseBody.fromString(jsonEncode(storages), 200,
          headers: {Headers.contentTypeHeader: ['application/json']});
    }
    return ResponseBody.fromString('[]', 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _storage(String uuid, String name, String type) => {
      'storage_uuid': uuid,
      'storage_name': name,
      'storage_type': type,
      'storage_path': '/$name',
      'quota_limit': 10485760,
      'is_default': 0,
      'used_size': 0,
    };

Widget _mount(StorageProvider sp) => MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageProvider>.value(value: sp),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StorageSelector(onStorageSelected: (_) {}),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('storage switcher uses a distinct icon per storage type',
      (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api'))
      ..httpClientAdapter = _StoragesStub([
        _storage('s-file', 'Docs', 'file'),
        _storage('s-mail', 'Mail', 'mail'),
        _storage('s-bolt', 'SecureBolt', 'password'),
      ]);
    final sp = StorageProvider(dio);
    // Real HTTP (fake adapter) must run outside testWidgets' fake-async zone.
    await tester.runAsync(() => sp.loadStorages('user-1'));

    await tester.pumpWidget(_mount(sp));
    await tester.pump();

    // Three different glyphs — not three identical `storage_rounded`.
    expect(find.byIcon(Icons.storage_rounded), findsOneWidget); // file
    expect(find.byIcon(Icons.mark_email_unread_rounded), findsOneWidget); // mail
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget); // password
  });
}
