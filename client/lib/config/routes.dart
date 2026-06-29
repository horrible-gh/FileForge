import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/login/totp_verify_screen.dart';
import '../screens/main/main_screen.dart';
import '../screens/main/storage_dispatcher.dart';
import '../screens/file/file_list_screen.dart';
import '../screens/share/share_links_screen.dart';
import '../screens/share/share_page.dart';
import '../screens/settings/security_settings_screen.dart';
import '../screens/settings/server_settings_screen.dart';
import '../screens/vault/vault_screen.dart';

class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String loginTotp = '/login/totp';
  static const String home = '/';
  static const String settings = '/settings';
  static const String serverSettings = '/settings/server';
  static const String vault = '/vault';

  static GoRouter createRouter(AuthProvider authProvider) {
    return GoRouter(
      initialLocation: splash,
      refreshListenable: authProvider,
      redirect: (context, state) {
        final isAuthenticated = authProvider.isAuthenticated;
        final location = state.matchedLocation;

        // authenticationtext text statetext translated text path text → splash text text text login text
        // /share/:tokentext public pathtranslated text /share/ prefix translated text authentication text text.
        // /share-linkstext /share/ translated text translated text text exampletext translated text.
        if (!isAuthenticated &&
            !location.startsWith('/splash') &&
            !location.startsWith('/login') &&
            !location.startsWith('/share/') &&
            !location.startsWith('/settings/server')) {
          final encodedRedirect = Uri.encodeComponent(state.uri.path);
          // ignore: avoid_print
          print('[T016] redirect → /splash?redirect=$encodedRedirect');
          return '/splash?redirect=$encodedRedirect';
        }
        // authenticationtext statetext login translated text text → text
        if (isAuthenticated && location.startsWith('/login')) {
          return home;
        }
        return null;
      },
      routes: [
        GoRoute(
          path: splash,
          builder: (context, state) => SplashScreen(
            redirectPath: state.uri.queryParameters['redirect'],
          ),
        ),
        GoRoute(
          path: login,
          builder: (context, state) => const LoginScreen(),
          routes: [
            GoRoute(
              path: 'totp',
              builder: (context, state) {
                // tempTokentext extra(String)text translated text.
                final tempToken = state.extra as String? ?? '';
                return TotpVerifyScreen(tempToken: tempToken);
              },
            ),
          ],
        ),
        // ── Phase 5 translated text public translated text — ShellRoute firsttext text, /share/ path text text text ──
        GoRoute(
          path: '/share/:token',
          builder: (context, state) => SharePage(
            token: state.pathParameters['token'] ?? '',
          ),
        ),
        // ── Phase 3 file translated text ShellRoute ───────────────────────────────────
        // MainScreen(Drawer + AppBar)text shell text. text translated text text body change.
        ShellRoute(
          builder: (context, state, child) => MainScreen(child: child),
          routes: [
            GoRoute(
              path: home,
              builder: (context, state) => const FileListScreen(),
            ),
            GoRoute(
              path: '/share-links',
              builder: (context, state) => const ShareLinksScreen(),
            ),
            GoRoute(
              path: settings,
              builder: (context, state) => const SecuritySettingsScreen(),
            ),
            // storage text branch: mail → MailListScreen, text text → FileListScreen.
            // (NR0003 §1.1 — text text translated text, FileListScreen text translated text)
            GoRoute(
              path: '/:storageUuid',
              builder: (context, state) => StorageDispatcher(
                storageUuid: state.pathParameters['storageUuid']!,
              ),
            ),
            GoRoute(
              path: '/:storageUuid/:nodeUuid',
              builder: (context, state) => StorageDispatcher(
                storageUuid: state.pathParameters['storageUuid']!,
                nodeUuid: state.pathParameters['nodeUuid'],
              ),
            ),
          ],
        ),
        GoRoute(
          path: serverSettings,
          builder: (context, state) => const ServerSettingsScreen(),
        ),
        // SecureBolt vault (fileforge.securebolt.0001). Own Scaffold (lock/unlock
        // flow) so it lives outside the file-oriented MainScreen shell. Auth-gated
        // by the redirect above (not in the public allowlist).
        GoRoute(
          path: vault,
          builder: (context, state) => const VaultScreen(),
        ),
      ],
    );
  }
}

