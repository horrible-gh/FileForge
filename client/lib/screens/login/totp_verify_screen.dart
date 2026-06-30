import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/auth_exception.dart';
import '../../config/routes.dart';
import '../../l10n/app_localizations.dart';

class TotpVerifyScreen extends StatefulWidget {
  final String tempToken;

  const TotpVerifyScreen({super.key, required this.tempToken});

  @override
  State<TotpVerifyScreen> createState() => _TotpVerifyScreenState();
}

class _TotpVerifyScreenState extends State<TotpVerifyScreen> {
  final _codeController = TextEditingController();
  String? _errorMessage;
  bool _useRecovery = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _useRecovery = !_useRecovery;
      _codeController.clear();
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final code = _codeController.text.trim();
    final expectedLength = _useRecovery ? 8 : 6;
    if (code.length != expectedLength) {
      setState(() => _errorMessage = _useRecovery ? t.totpEnterRecoveryCodeError : t.totpEnterCodeError);
      return;
    }

    setState(() => _errorMessage = null);

    final authProvider = context.read<AuthProvider>();
    try {
      await authProvider.verifyTotp(widget.tempToken, code);
      // success — isAuthenticatedtext true → GoRouter redirecttext /login → /home text.
      // translated text navigatetext text text.
      if (!mounted) return;
      context.go(AppRoutes.home);
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.detail == 'token_expired') {
        // L002 ST-01 Row 10: "authentication translated text expiredtranslated text" → login screen navigate
        context.go(AppRoutes.login);
      } else {
        // L002 ST-01 Row 9: invalid_code → screen keep, translated text allowed
        setState(() {
          _errorMessage = t.totpInvalidCode;
          _codeController.clear();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = t.totpAuthError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.totpTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text(
                _useRecovery ? t.totpRecoveryPrompt : t.totpCodePrompt,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: t.totpCodeLabel,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
                keyboardType:
                    _useRecovery ? TextInputType.text : TextInputType.number,
                inputFormatters: _useRecovery
                    ? [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9]')),
                        LengthLimitingTextInputFormatter(8),
                      ]
                    : [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, letterSpacing: 8),
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              Consumer<AuthProvider>(
                builder: (_, auth, _) => FilledButton(
                  onPressed: auth.isLoading ? null : _submit,
                  child: auth.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(t.totpVerify),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _toggleMode,
                child: Text(
                  _useRecovery ? t.totpUseAuthCode : t.totpUseRecovery,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
