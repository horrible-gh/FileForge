import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/routes.dart';
import 'config/theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/storage_provider.dart';
import 'providers/file_provider.dart';
import 'providers/upload_provider.dart';
import 'providers/selection_provider.dart';
import 'providers/share_link_provider.dart';
import 'providers/mail_provider.dart';
import 'providers/account_provider.dart';
import 'services/account_cache.dart';
import 'services/mail_api_client.dart';

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
  late final MailApiClient _mailApiClient;
  late final MailProvider _mailProvider;
  late final AccountProvider _accountProvider;
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
    // MailAnchor(Go) 전용 Dio — FileForge 세션 토큰을 공유한다(NR0003 §1/§3.3).
    _mailApiClient = MailApiClient()
      ..configure(
        getAccessToken: () => _authProvider.accessToken,
        onRefreshToken: _authProvider.refreshAccessToken,
        onSessionExpired: _authProvider.logout,
      );
    _mailProvider = MailProvider(_mailApiClient.dio);
    // 계정 게이트 — MailProvider 와 같은 MailApiClient Dio(세션 토큰 공유)를 탄다.
    // 계정 유무 캐시를 주입해 콜드 진입에서 화면을 즉시 그린다(TR0005 §증상1).
    _accountProvider = AccountProvider(
      _mailApiClient.dio,
      cache: SharedPrefsAccountCache(),
    );
    // T074: 로그아웃/세션 만료 시 storage·file·mail·account 상태 초기화 연결
    _authProvider.setProviderResetCallback(() {
      _storageProvider.reset();
      _fileProvider.reset();
      _mailProvider.reset();
      _accountProvider.reset();
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
        ChangeNotifierProvider<MailProvider>.value(value: _mailProvider),
        ChangeNotifierProvider<AccountProvider>.value(value: _accountProvider),
      ],
      child: MaterialApp.router(
        title: 'FileForge',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        // i18n(mailanchor.ui.0002) — 기기 로케일을 따르며 ko/ja/en 을 지원한다.
        // 지원하지 않는 로케일은 supportedLocales 의 첫 항목(en)으로 폴백한다.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _routerConfig,
      ),
    );
  }
}
