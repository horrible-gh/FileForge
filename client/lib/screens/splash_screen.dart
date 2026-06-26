import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../config/routes.dart';

/// text text screen — SecureStorage token text text text text logintext branch
/// [redirectPath]: text login success text navigatetext text text path (translated text F5 translated text)
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
      // tryAutoLogin exampletext text login screentext navigate (branch text)
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
