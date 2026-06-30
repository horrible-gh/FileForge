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
import 'providers/vault_provider.dart';
import 'services/account_cache.dart';
import 'services/deep_link_service.dart';
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
  late final VaultProvider _vaultProvider;
  late final DeepLinkService _deepLinkService;
  late final RouterConfig<Object> _routerConfig;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
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
        // Share the AuthProvider's single coalesced rotation with the file Dio
        // so the two never rotate the refresh token concurrently (NR0003 F2).
        ensureFreshToken: _authProvider.ensureFreshToken,
        isSessionExpired: () => _authProvider.lastRefreshWasExpired,
        onSessionExpired: _authProvider.handleSessionExpired,
      );
    // B0001 / NR0003 §3: wire the server-address override so it propagates not
    // only to the file Dio but to the mail Dio too. Without this, changing the
    // server in settings still routes only mail/account requests to the
    // build-baked address (localhost by default), surfacing "connect Google".
    _authProvider.setServerUrlChangeCallback(_mailApiClient.setBaseUrl);
    // Apply the stored server address to both file and mail Dios at once on startup (after the callback is wired).
    if (widget.initialServerUrl.isNotEmpty) {
      _authProvider.setServerUrl(widget.initialServerUrl);
    }
    _mailProvider = MailProvider(_mailApiClient.dio);
    // account translated text — MailProvider text text MailApiClient Dio(session token text)text text.
    // account text translated text translated text text translated text screentext text translated text(TR0005 §symptom1).
    _accountProvider = AccountProvider(
      _mailApiClient.dio,
      cache: SharedPrefsAccountCache(),
    );
    // SecureBolt vault (fileforge.securebolt.0001): uses the session-authenticated
    // file Dio (/fileforge origin → /bolt/*). The master hash is derived in the
    // provider from re-entered credentials and never leaves memory.
    _vaultProvider = VaultProvider(_authProvider.dio);
    // SecureBolt(fileforge.securebolt.0002 / TR0005): on a fresh ID/PW login,
    // derive the vault master key from that password so entering SecureBolt does
    // not show a second password prompt (requirement 2). Token auto-login has no
    // password so this is not called; in that case it falls back to an inline unlock on the vault screen.
    _authProvider.setVaultUnlockCallback(
      (username, password) => _vaultProvider.unlock(username, password),
    );
    // T074: logout/session expired text storage·file·mail·account state initialize text
    _authProvider.setProviderResetCallback(() {
      _storageProvider.reset();
      _fileProvider.reset();
      _mailProvider.reset();
      _accountProvider.reset();
      _vaultProvider.reset(); // wipe in-memory master hash + decrypted vault
    });
    _routerConfig = AppRoutes.createRouter(_authProvider);

    // R0001/NR0003/L0004 §2.5-2.6: start 3rd-gen session keep-alive — proactive
    // pre-expiry rotation + lifecycle-resume re-check — so a long-running app no
    // longer falls back to the login screen (the "bounce-out").
    _authProvider.startSessionKeepAlive();

    // R0001/NR0003/T0004 §Option C: when the fileforge:// deep link from the OAuth
    // success page is received, the app returns to the foreground and reloads the
    // account list to detect the connection immediately.
    // (account_connect_screen's lifecycle-based manual return detection is kept as a fallback.)
    _deepLinkService = DeepLinkService()
      ..onOAuthSuccess = () {
        _accountProvider.load();
      };
    _deepLinkService.init();
  }

  @override
  void dispose() {
    _authProvider.stopSessionKeepAlive();
    _deepLinkService.dispose();
    super.dispose();
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
        ChangeNotifierProvider<VaultProvider>.value(value: _vaultProvider),
      ],
      child: MaterialApp.router(
        title: 'FileForge',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        // i18n (fileforge.default.0003) — gen-l10n delegates drive ko/ja/en.
        // The device locale is followed; unsupported locales fall back to the
        // first supportedLocales entry (en).
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: _routerConfig,
      ),
    );
  }
}
