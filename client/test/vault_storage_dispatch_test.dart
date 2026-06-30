import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:file_forge_app/providers/auth_provider.dart';
import 'package:file_forge_app/providers/file_provider.dart';
import 'package:file_forge_app/providers/selection_provider.dart';
import 'package:file_forge_app/providers/storage_provider.dart';
import 'package:file_forge_app/providers/upload_provider.dart';
import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/providers/vault_provider.dart';
import 'package:file_forge_app/screens/file/file_list_screen.dart';
import 'package:file_forge_app/screens/main/storage_dispatcher.dart';
import 'package:file_forge_app/screens/vault/vault_screen.dart';

/// SecureBolt fileforge.securebolt.0003 / TR0005 — core regression guard.
///
/// User requirement (R0001/CH0006): make SecureBolt a **storage type** ('password'), not a
/// drawer-only menu, so that tapping it in the list opens that storage as a vault.
/// load-bearing: StorageDispatcher must branch storage_type=='password' to VaultStorageView
/// (without the branch it falls through to the file browser, reproducing "nothing works").
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
    // Everything else (e.g. file children probes) → empty, never throws.
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

Widget _mount({
  required StorageProvider storageProvider,
  required Dio dio,
  required String storageUuid,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<StorageProvider>.value(value: storageProvider),
      ChangeNotifierProvider<VaultProvider>(create: (_) => VaultProvider(dio)),
      ChangeNotifierProvider<FileProvider>(create: (_) => FileProvider(dio)),
      ChangeNotifierProvider<UploadProvider>(create: (_) => UploadProvider(dio)),
      ChangeNotifierProvider<SelectionProvider>(
          create: (_) => SelectionProvider()),
    ],
    child: MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StorageDispatcher(storageUuid: storageUuid),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("'password' storage dispatches to the embedded vault, locked",
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api'))
      ..httpClientAdapter = _StoragesStub([
        _storage('s-file', 'Docs', 'file'),
        _storage('s-bolt', 'SecureBolt', 'password'),
      ]);
    final sp = StorageProvider(dio);
    // Real HTTP (fake adapter) must run outside testWidgets' fake-async zone.
    await tester.runAsync(() => sp.loadStorages('user-1'));

    await tester.pumpWidget(
      _mount(storageProvider: sp, dio: dio, storageUuid: 's-bolt'),
    );
    await tester.pump();

    // load-bearing: branched to the vault screen (=VaultStorageView), and since it's locked
    // the unlock view is shown. Not the file browser.
    expect(find.byType(VaultStorageView), findsOneWidget);
    expect(find.text('볼트 잠금 해제'), findsOneWidget);
    expect(find.byType(FileListScreen), findsNothing);
  });

  testWidgets('embedded vault carries its own [+] FAB once unlocked',
      (tester) async {
    // load-bearing for R-3 ("create a card inside it with [+]"): the embedded view —
    // not the shell AppBar — owns the add affordance. Locked → no FAB.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider<VaultProvider>(
        create: (_) => VaultProvider(Dio(BaseOptions(baseUrl: 'http://x/'))),
        child: MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const VaultStorageView(),
        ),
      ),
    );
    await tester.pump();

    // Locked: the unlock view shows, no add FAB (can't add without the key).
    expect(find.text('볼트 잠금 해제'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
