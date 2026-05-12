import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/login/totp_verify_screen.dart';
import '../screens/main/main_screen.dart';
import '../screens/file/file_list_screen.dart';
import '../screens/share/share_links_screen.dart';
import '../screens/share/share_page.dart';
import '../screens/settings/security_settings_screen.dart';
import '../screens/settings/server_settings_screen.dart';

class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String loginTotp = '/login/totp';
  static const String home = '/';
  static const String settings = '/settings';
  static const String serverSettings = '/settings/server';

  static GoRouter createRouter(AuthProvider authProvider) {
    return GoRouter(
      initialLocation: splash,
      refreshListenable: authProvider,
      redirect: (context, state) {
        final isAuthenticated = authProvider.isAuthenticated;
        final location = state.matchedLocation;

        // 인증되지 않은 상태에서 보호된 경로 접근 → splash 경유 후 자동 로그인 시도
        // /share/:token은 공개 경로이므로 /share/ prefix 전체를 인증 우회 처리.
        // /share-links는 /share/ 시작이 아니므로 별도 예외 불필요.
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
        // 인증된 상태에서 로그인 페이지 접근 → 메인
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
                // tempToken은 extra(String)로 전달한다.
                final tempToken = state.extra as String? ?? '';
                return TotpVerifyScreen(tempToken: tempToken);
              },
            ),
          ],
        ),
        // ── Phase 5 딥링크 공개 라우트 — ShellRoute 앞에 배치, /share/ 경로 우선 매칭 보장 ──
        GoRoute(
          path: '/share/:token',
          builder: (context, state) => SharePage(
            token: state.pathParameters['token'] ?? '',
          ),
        ),
        // ── Phase 3 파일 탐색기 ShellRoute ───────────────────────────────────
        // MainScreen(Drawer + AppBar)이 shell 역할. 내부 라우트에 따라 body 변경.
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
            GoRoute(
              path: '/:storageUuid',
              builder: (context, state) => FileListScreen(
                storageUuid: state.pathParameters['storageUuid'],
              ),
            ),
            GoRoute(
              path: '/:storageUuid/:nodeUuid',
              builder: (context, state) => FileListScreen(
                storageUuid: state.pathParameters['storageUuid'],
                nodeUuid: state.pathParameters['nodeUuid'],
              ),
            ),
          ],
        ),
        GoRoute(
          path: serverSettings,
          builder: (context, state) => const ServerSettingsScreen(),
        ),
      ],
    );
  }
}

