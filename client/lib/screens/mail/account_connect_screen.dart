import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../models/mail_account.dart';
import '../../providers/account_provider.dart';
import '../../services/mail_envelope.dart';
import '../../widgets/app_toast.dart';

/// text account text screen — NR0003 §5.4 / TR0005 §symptom2(browser OAuth text).
///
/// OAuth provider(gmail/outlook)text "consent URL issue(GET /accounts/oauth/authorize)
/// → browser login → server translated text translated text text text·accounttext" pathtext translated text.
/// translated text translated text translated text translated text translated text(CH0007 "authenticationtext translated text" text). browser
/// text translated text(text resume) account translated text text textlookuptext translated text translated text — translated text
/// MailAnchor text "text + text" translated text translated text text text(NR0003 §4 translated text).
///
/// imap text password translated text consent URL text text, text text/password manual entry pathtext
/// text. OAuth providertranslated text "text: text manual entry"text text pathtext text text(server
/// text POST /accounts {auth_code} text backward compatibilitytext keeptext).
class AccountConnectScreen extends StatefulWidget {
  const AccountConnectScreen({super.key});

  @override
  State<AccountConnectScreen> createState() => _AccountConnectScreenState();
}

class _AccountConnectScreenState extends State<AccountConnectScreen>
    with WidgetsBindingObserver {
  String _provider = kMailProviders.first;
  final TextEditingController _authCode = TextEditingController();
  bool _connecting = false; // text(text) text text text
  bool _oauthBusy = false; // consent URL issue/browser text text
  bool _awaitingReturn = false; // browsertext translated text text text text
  bool _showAdvanced = false; // OAuth providertext text manual entry text
  MailApiException? _oauthError; // consent URL issue failed(translated text banner — NR0007 §6 L3)

  bool get _isOAuthProvider => kOAuthProviders.contains(_provider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authCode.dispose();
    super.dispose();
  }

  /// browsertext text text translated text translated text(resumed) accounttext text textlookuptext translated text
  /// translated text(translated text translated text "text text translated text" translated text text core — TR0005 §symptom2).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _refreshAfterReturn();
    }
  }

  /// OAuth text: consent URL text text text browsertext text.
  Future<void> _startOAuth() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _oauthBusy = true;
      _oauthError = null; // retry text text failed banner text
    });
    final res = await context.read<AccountProvider>().oauthAuthorizeUrl(_provider);
    if (!mounted) return;
    if (res.url == null) {
      // toast-text-text(NR0007 §5.4) text minutestext translated text failed bannertext translated text —
      // text(L1)+diagnostic(L2)+retry/fallback path(L3)text translated text translated text.
      setState(() {
        _oauthBusy = false;
        _oauthError = res.error;
      });
      return;
    }
    bool launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(res.url!),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!mounted) return;
    setState(() {
      _oauthBusy = false;
      _awaitingReturn = launched;
    });
    if (!launched) AppToast.error(context, t.accountOAuthLaunchFailed);
  }

  /// text text(text "text text" text) account translated text textlookuptext text accounttext translated text.
  Future<void> _refreshAfterReturn() async {
    final t = AppLocalizations.of(context);
    final accounts = context.read<AccountProvider>();
    final before = accounts.accounts.length;
    await accounts.load();
    if (!mounted) return;
    if (accounts.accounts.length > before) {
      setState(() => _awaitingReturn = false);
      AppToast.success(context, t.accountConnected);
    }
  }

  Future<void> _connect() async {
    final t = AppLocalizations.of(context);
    final code = _authCode.text.trim();
    if (code.isEmpty) {
      AppToast.warning(context, t.accountAuthCodeRequired);
      return;
    }
    setState(() => _connecting = true);
    final err = await context
        .read<AccountProvider>()
        .connect(provider: _provider, authCode: code);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (err == null) {
      _authCode.clear();
      AppToast.success(context, t.accountConnected);
      return;
    }
    // text(text) pathtext minutestext message + diagnostic translated text(L1·L2)text translated text.
    AppToast.error(context, '${_connectErrorMessage(t, err)}  (${diagnosticLabel(err)})');
  }

  /// server errortext translated text messagetext — NR0007 §6 L1. catch-all text toasttext translated text
  /// minutestranslated text(minutestext [classifyConnectFailure], mail_envelope §translated text).
  String _connectErrorMessage(AppLocalizations t, MailApiException e) {
    switch (classifyConnectFailure(e)) {
      case ConnectFailureKind.conflict:
        return t.accountConflict;
      case ConnectFailureKind.oauthNotConfigured:
        return t.accountOAuthNotConfigured;
      case ConnectFailureKind.oauthExchangeFailed:
        return t.accountOAuthExchangeFailed;
      case ConnectFailureKind.session:
        return t.accountConnectSessionExpired;
      case ConnectFailureKind.network:
        return t.accountConnectUnreachable;
      case ConnectFailureKind.malformed:
        return t.accountConnectMalformed;
      case ConnectFailureKind.invalid:
        return t.accountConnectInvalid;
      case ConnectFailureKind.generic:
        return t.accountConnectFailed;
    }
  }

  Future<void> _remove(MailAccount account) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.accountRemoveConfirmTitle),
        content: Text(t.accountRemoveConfirmBody(account.email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.removeLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await context.read<AccountProvider>().remove(account.accountId);
    if (!mounted) return;
    if (ok) {
      AppToast.success(context, t.accountRemoved);
    } else {
      AppToast.error(context, t.accountRemoveFailed);
    }
  }

  String _providerDisplay(String p) => switch (p) {
        'gmail' => 'Google',
        'outlook' => 'Outlook',
        _ => p,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final accounts = context.watch<AccountProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(t.accountConnectTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── translated text text(textaccounttext text text) ──────────────────────────────
          if (!accounts.hasAccounts) ...[
            _OnboardingHeader(
              title: t.accountOnboardingTitle,
              body: t.accountOnboardingBody,
            ),
            const SizedBox(height: 24),
          ],

          // ── translated text account ────────────────────────────────────────────────
          Text(t.accountSectionConnected,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (accounts.accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(t.accountEmpty,
                  style: Theme.of(context).textTheme.bodyMedium),
            )
          else
            ...accounts.accounts.map((a) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.alternate_email_rounded),
                    title: Text(a.email),
                    subtitle: Text(a.provider),
                    trailing: IconButton(
                      icon: const Icon(Icons.link_off_rounded),
                      tooltip: t.accountRemoveTooltip,
                      onPressed: () => _remove(a),
                    ),
                  ),
                )),

          const Divider(height: 32),

          // ── account add ──────────────────────────────────────────────────
          Text(t.accountSectionAdd,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _provider,
            decoration: InputDecoration(
              labelText: t.accountProviderLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final p in kMailProviders)
                DropdownMenuItem(value: p, child: Text(p)),
            ],
            onChanged: (_connecting || _oauthBusy)
                ? null
                : (v) => setState(() {
                      _provider = v ?? _provider;
                      _awaitingReturn = false;
                      _showAdvanced = false;
                      _oauthError = null;
                    }),
          ),
          const SizedBox(height: 16),

          if (_isOAuthProvider)
            ..._buildOAuthSection(t)
          else
            ..._buildManualSection(t),
        ],
      ),
    );
  }

  // ── OAuth(browser) path ──────────────────────────────────────────────
  List<Widget> _buildOAuthSection(AppLocalizations t) {
    if (_awaitingReturn) {
      return [
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.accountOAuthAwaitTitle,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(t.accountOAuthAwaitBody),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _refreshAfterReturn,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(t.accountOAuthCheckAction),
                    ),
                    TextButton(
                      onPressed: _oauthBusy ? null : _startOAuth,
                      child: Text(t.accountOAuthReopen),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildAdvancedToggle(t),
      ];
    }
    return [
      if (_oauthError != null) ...[
        _buildOAuthError(t, _oauthError!),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(
        onPressed: _oauthBusy ? null : _startOAuth,
        icon: _oauthBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.login_rounded),
        label: Text(_oauthBusy
            ? t.accountOAuthLaunching
            : t.accountOAuthConnectWith(_providerDisplay(_provider))),
      ),
      const SizedBox(height: 8),
      _buildAdvancedToggle(t),
    ];
  }

  /// consent URL issue failed translated text banner — NR0007 §6 L3. toasttext translated text translated text
  /// screentext text text text, OAuth translated text **text(L1) + diagnostic translated text(L2) + again text
  /// / text manual entry text** text translated text text(translated text translated text banner text translated text).
  Widget _buildOAuthError(AppLocalizations t, MailApiException e) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _connectErrorMessage(t, e),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // diagnostic translated text(code · HTTP status · requestId) — text/translated text.
            Text(
              diagnosticLabel(e),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _oauthBusy ? null : _startOAuth,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(t.accountGateRetry),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _showAdvanced = true;
                    _oauthError = null;
                  }),
                  child: Text(t.accountAdvancedToggle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedToggle(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
          icon: Icon(_showAdvanced
              ? Icons.expand_less_rounded
              : Icons.expand_more_rounded),
          label: Text(t.accountAdvancedToggle),
        ),
        if (_showAdvanced) ..._buildManualSection(t),
      ],
    );
  }

  // ── text(text/password manual entry) path ─────────────────────────────────
  List<Widget> _buildManualSection(AppLocalizations t) {
    return [
      const SizedBox(height: 4),
      TextField(
        controller: _authCode,
        enabled: !_connecting,
        maxLines: 2,
        minLines: 1,
        decoration: InputDecoration(
          labelText: t.accountAuthCodeLabel,
          hintText: t.accountAuthCodeHint,
          helperText: t.accountAuthCodeHelp,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _connecting ? null : _connect,
        icon: _connecting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_link_rounded),
        label: Text(_connecting ? t.accountConnecting : t.accountConnectAction),
      ),
    ];
  }
}

class _OnboardingHeader extends StatelessWidget {
  final String title;
  final String body;

  const _OnboardingHeader({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.mark_email_unread_rounded,
            size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(body, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
