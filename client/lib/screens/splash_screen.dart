import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../config/routes.dart';

/// 앱 시작 화면 — SecureStorage 토큰 확인 후 메인 또는 로그인으로 분기
/// [redirectPath]: 자동 로그인 성공 시 이동할 원래 목적 경로 (딥링크 F5 복귀용)
class SplashScreen extends StatefulWidget {
  final String? redirectPath;

  const SplashScreen({super.key, this.redirectPath});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final authProvider = context.read<AuthProvider>();
    // ignore: avoid_print
    print('[T016] SplashScreen._checkAuth redirectPath=${widget.redirectPath}');
    bool loggedIn = false;
    try {
      loggedIn = await authProvider.tryAutoLogin();
    } catch (_) {
      // tryAutoLogin 예외 시 로그인 화면으로 이동 (분기 보강)
    }
    if (!mounted) return;
    if (loggedIn) {
      // ignore: avoid_print
      print('[T016] loggedIn → ${widget.redirectPath ?? AppRoutes.home}');
      context.go(widget.redirectPath ?? AppRoutes.home);
    } else {
      // ignore: avoid_print
      print('[T016] not loggedIn → ${AppRoutes.login}');
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
