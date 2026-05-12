import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../config/routes.dart';
import '../../widgets/server_settings_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final authProvider = context.read<AuthProvider>();
    authProvider.clearError();

    final result = await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;

    switch (result) {
      case LoginResult.success:
        context.go(AppRoutes.home);
      case LoginResult.totpRequired:
        final tempToken = authProvider.tempToken ?? '';
        context.go(AppRoutes.loginTotp, extra: tempToken);
      case LoginResult.failed:
        // _error가 AuthProvider에 설정됨 → Consumer가 리빌드하여 표시
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xDD223746);
    const fieldColor = Color(0xFF2C4556);
    const fieldBorderColor = Color(0xFF5E8196);
    const primaryTextColor = Color(0xFFEAF4F8);
    const secondaryTextColor = Color(0xFFAFC4CF);
    const buttonColor = Color(0xFF6FA9C4);
    const buttonForegroundColor = Color(0xFF10222C);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/bg-01.jpg',
            fit: BoxFit.cover,
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x400A1720),
                  Color(0x660A1720),
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0x66A9C9D8),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 24,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    inputDecorationTheme: const InputDecorationTheme(
                      filled: true,
                      fillColor: fieldColor,
                      labelStyle: TextStyle(color: secondaryTextColor),
                      hintStyle: TextStyle(color: secondaryTextColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(color: fieldBorderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(color: fieldBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(
                          color: Color(0xFF8FC2D9),
                          width: 1.6,
                        ),
                      ),
                    ),
                    filledButtonTheme: FilledButtonThemeData(
                      style: FilledButton.styleFrom(
                        backgroundColor: buttonColor,
                        foregroundColor: buttonForegroundColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                const Text(
                  'FileForge',
                  style: TextStyle(
                    color: primaryTextColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your account information to return to your workspace',
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                  ),
                  style: const TextStyle(color: primaryTextColor),
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Please enter your username' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                  ),
                  style: const TextStyle(color: primaryTextColor),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  autofillHints: const [AutofillHints.password],
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter your password' : null,
                ),
                const SizedBox(height: 8),
                // 서버 에러 메시지 (L002 ST-01 기준)
                Consumer<AuthProvider>(
                  builder: (_, auth, _) {
                    if (auth.error == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: Text(
                        auth.error!,
                        style: TextStyle(
                          color: const Color(0xFFFFB4AB),
                          fontSize: 13,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Consumer<AuthProvider>(
                  builder: (_, auth, _) => FilledButton(
                    onPressed: auth.isLoading ? null : _submit,
                    child: auth.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(
                      Icons.dns_outlined,
                      size: 16,
                      color: Color(0xFF7A9BAD),
                    ),
                    label: const Text(
                      'Server Settings',
                      style: TextStyle(
                        color: Color(0xFF7A9BAD),
                        fontSize: 13,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const ServerSettingsDialog(),
                    ),
                  ),
                ),
              ],
            ),
          ),
                ),
        ),
      ),
      ),
        ],
      ),
    );
  }
}

