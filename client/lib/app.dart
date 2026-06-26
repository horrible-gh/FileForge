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

/// text text text
/// MaterialApp.router + MultiProvider text
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
    // AuthProvidertext translated text Dio(Bearer translated text text)text translated text.
    _storageProvider = StorageProvider(_authProvider.dio);
    _fileProvider = FileProvider(
      _authProvider.dio,
      initialViewMode: widget.initialViewMode,
    );
    _uploadProvider = UploadProvider(_authProvider.dio);
    _selectionProvider = SelectionProvider();
    _shareLinkProvider = ShareLinkProvider(_authProvider.dio);
    // MailAnchor(Go) text Dio — FileForge session tokentext translated text(NR0003 §1/§3.3).
    _mailApiClient = MailApiClient()
      ..configure(
        getAccessToken: () => _authProvider.accessToken,
        onRefreshToken: _authProvider.refreshAccessToken,
        onSessionExpired: _authProvider.logout,
      );
    _mailProvider = MailProvider(_mailApiClient.dio);
    // account translated text — MailProvider text text MailApiClient Dio(session token text)text text.
    // account text translated text translated text text translated text screentext text translated text(TR0005 §symptom1).
    _accountProvider = AccountProvider(
      _mailApiClient.dio,
      cache: SharedPrefsAccountCache(),
    );
    // T074: logout/session expired text storage·file·mail·account state initialize text
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
        // i18n(mailanchor.ui.0002) — text translated text translated text ko/ja/en text translated text.
        // translated text text translated text supportedLocales text text text(en)text translated text.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _routerConfig,
      ),
    );
  }
}
