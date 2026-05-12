import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/routes.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/storage_provider.dart';
import 'providers/file_provider.dart';
import 'providers/upload_provider.dart';
import 'providers/selection_provider.dart';
import 'providers/share_link_provider.dart';

/// 앱 루트 위젯
/// MaterialApp.router + MultiProvider 래핑
class App extends StatefulWidget {
  const App({super.key, required this.initialViewMode, this.initialServerUrl = ''});

  final FileViewMode initialViewMode;
  final String initialServerUrl;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AuthProvider _authProvider;
  late final StorageProvider _storageProvider;
  late final FileProvider _fileProvider;
  late final UploadProvider _uploadProvider;
  late final SelectionProvider _selectionProvider;
  late final ShareLinkProvider _shareLinkProvider;
  late final RouterConfig<Object> _routerConfig;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    if (widget.initialServerUrl.isNotEmpty) {
      _authProvider.setServerUrl(widget.initialServerUrl);
    }
    // AuthProvider의 구성된 Dio(Bearer 인터셉터 포함)을 공유한다.
    _storageProvider = StorageProvider(_authProvider.dio);
    _fileProvider = FileProvider(
      _authProvider.dio,
      initialViewMode: widget.initialViewMode,
    );
    _uploadProvider = UploadProvider(_authProvider.dio);
    _selectionProvider = SelectionProvider();
    _shareLinkProvider = ShareLinkProvider(_authProvider.dio);
    // T074: 로그아웃/세션 만료 시 storage·file 상태 초기화 연결
    _authProvider.setProviderResetCallback(() {
      _storageProvider.reset();
      _fileProvider.reset();
    });
    _routerConfig = AppRoutes.createRouter(_authProvider);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _authProvider),
        ChangeNotifierProvider<StorageProvider>.value(value: _storageProvider),
        ChangeNotifierProvider<FileProvider>.value(value: _fileProvider),
        ChangeNotifierProvider<UploadProvider>.value(value: _uploadProvider),
        ChangeNotifierProvider<SelectionProvider>.value(value: _selectionProvider),
        ChangeNotifierProvider<ShareLinkProvider>.value(value: _shareLinkProvider),
      ],
      child: MaterialApp.router(
        title: 'FileForge',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        routerConfig: _routerConfig,
      ),
    );
  }
}
