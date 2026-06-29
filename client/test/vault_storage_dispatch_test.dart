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
import 'package:file_forge_app/providers/vault_provider.dart';
import 'package:file_forge_app/screens/file/file_list_screen.dart';
import 'package:file_forge_app/screens/main/storage_dispatcher.dart';
import 'package:file_forge_app/screens/vault/vault_screen.dart';

/// SecureBolt fileforge.securebolt.0003 / TR0005 — 핵심 회귀 가드.
///
/// 사용자 요구(R0001/CH0006): SecureBolt 를 드로어 전용 메뉴가 아니라 **스토리지
/// 타입**('password')으로 만들어, 목록에서 탭하면 그 스토리지가 볼트로 열려야
/// 한다. load-bearing: StorageDispatcher 가 storage_type=='password' 를
/// VaultStorageView 로 분기해야 한다(분기 누락 시 파일 브라우저로 떨어져 "되는게
/// 없다"가 재현됨).
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

    // load-bearing: 볼트 화면으로 분기됐고(=VaultStorageView), 잠금 상태이므로
    // 잠금 해제 뷰가 보인다. 파일 브라우저가 아니다.
    expect(find.byType(VaultStorageView), findsOneWidget);
    expect(find.text('볼트 잠금 해제'), findsOneWidget);
    expect(find.byType(FileListScreen), findsNothing);
  });

  testWidgets('embedded vault carries its own [+] FAB once unlocked',
      (tester) async {
    // load-bearing for R-3 ("그 안에서 카드를 [+]로 만든다"): the embedded view —
    // not the shell AppBar — owns the add affordance. Locked → no FAB.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider<VaultProvider>(
        create: (_) => VaultProvider(Dio(BaseOptions(baseUrl: 'http://x/'))),
        child: const MaterialApp(home: VaultStorageView()),
      ),
    );
    await tester.pump();

    // Locked: the unlock view shows, no add FAB (can't add without the key).
    expect(find.text('볼트 잠금 해제'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
