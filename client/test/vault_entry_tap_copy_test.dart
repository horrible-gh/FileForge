import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:file_forge_app/l10n/app_localizations.dart';
import 'package:file_forge_app/models/vault.dart';
import 'package:file_forge_app/providers/auth_provider.dart';
import 'package:file_forge_app/providers/vault_provider.dart';
import 'package:file_forge_app/services/vault_local_store.dart';
import 'package:file_forge_app/services/vault_service.dart';
import 'package:file_forge_app/screens/vault/vault_screen.dart';

/// SecureBolt fileforge.securebolt.0005 / R0001 ("기능을 반대로") — load-bearing.
///
/// R0001 reverses the entry-tile interaction:
///   1) tapping a tile must COPY the password (it used to open the editor);
///   2) the trailing row must carry THREE buttons — copy, edit, delete.
/// Without the rewire (onTap → copy, + an edit IconButton) these expectations
/// fail: the old build opened the editor on tap and had only copy+delete.
class _FakeBoltAdapter implements HttpClientAdapter {
  final Map<String, Map<String, String>> store = {};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.endsWith('/bolt/push')) {
      final body = options.data as Map;
      store['${body['data_type']}'] = {
        'content': '${body['content']}',
        'version': '${body['version']}',
      };
      return ResponseBody.fromString('{"status":"success"}', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    }
    if (options.path.endsWith('/bolt/pull')) {
      final items = store.entries
          .map((e) =>
              '{"data_type":"${e.key}","encrypted_data":"${e.value['content']}","version":"${e.value['version']}"}')
          .join(',');
      return ResponseBody.fromString('{"status":"success","data":[$items]}', 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    }
    return ResponseBody.fromString('{}', 404);
  }
}

Future<VaultProvider> _unlockedWithEntry(WidgetTester tester) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://x/fileforge'))
    ..httpClientAdapter = _FakeBoltAdapter();
  final provider =
      VaultProvider.withService(VaultService(dio, localStore: InMemoryVaultLocalStore()));
  // Real HTTP (fake adapter) must run outside testWidgets' fake-async zone.
  await tester.runAsync(() async {
    await provider.unlock('fileforge', 'P@ssw0rd!');
    await provider.savePassword(const VaultPasswordEntry(
      id: 42,
      title: 'GitHub',
      username: 'octocat',
      password: 's3cr3t-pw',
    ));
  });
  return provider;
}

Widget _mount(VaultProvider provider) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<VaultProvider>.value(value: provider),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const VaultStorageView(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Capture what the app writes to the system clipboard.
  String? clipboardText;
  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('each entry tile carries copy + edit + delete buttons', (tester) async {
    final provider = await _unlockedWithEntry(tester);
    await tester.pumpWidget(_mount(provider));
    await tester.pumpAndSettle();

    // load-bearing for R0001 requirement (2): three trailing actions, not two.
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('tapping a tile copies the password (not opening the editor)',
      (tester) async {
    final provider = await _unlockedWithEntry(tester);
    await tester.pumpWidget(_mount(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();

    // load-bearing for R0001 requirement (1): tap → password on the clipboard,
    // and the editor dialog ("항목 편집") did NOT open.
    expect(clipboardText, 's3cr3t-pw');
    expect(find.text('항목 편집'), findsNothing);

    // Drain the success-toast timer so it doesn't outlive the widget tree.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the trailing edit button opens the editor dialog', (tester) async {
    final provider = await _unlockedWithEntry(tester);
    await tester.pumpWidget(_mount(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    // Editing is still reachable — now via the explicit button.
    expect(find.text('항목 편집'), findsOneWidget);
  });
}
