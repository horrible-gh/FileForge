import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../models/mail_account.dart';
import '../../providers/account_provider.dart';
import '../../services/mail_envelope.dart';
import '../../widgets/app_toast.dart';

/// 메일 계정 연결 화면 — NR0003 §5.4 / TR0005 §증상2(브라우저 OAuth 전환).
///
/// OAuth 제공자(gmail/outlook)는 "동의 URL 발급(GET /accounts/oauth/authorize)
/// → 브라우저 로그인 → 서버 콜백이 백채널로 코드 교환·계정연결" 경로로 연결한다.
/// 사용자는 코드를 손으로 만지지 않는다(CH0007 "인증코드 붙여넣기" 제거). 브라우저
/// 에서 돌아오면(앱 resume) 계정 목록을 자동 재조회해 연결을 감지한다 — 레거시
/// MailAnchor 의 "팝업 + 폴링" 패턴을 모바일에 맞춘 형태(NR0003 §4 레퍼런스).
///
/// imap 은 비밀번호 기반이라 동의 URL 이 없어, 기존 코드/비밀번호 직접 입력 경로를
/// 쓴다. OAuth 제공자에서도 "고급: 코드 직접 입력"으로 폴백 경로를 남겨 둔다(서버
/// 의 POST /accounts {auth_code} 가 하위호환으로 유지됨).
class AccountConnectScreen extends StatefulWidget {
  const AccountConnectScreen({super.key});

  @override
  State<AccountConnectScreen> createState() => _AccountConnectScreenState();
}

class _AccountConnectScreenState extends State<AccountConnectScreen>
    with WidgetsBindingObserver {
  String _provider = kMailProviders.first;
  final TextEditingController _authCode = TextEditingController();
  bool _connecting = false; // 수동(코드) 연결 진행 중
  bool _oauthBusy = false; // 동의 URL 발급/브라우저 실행 중
  bool _awaitingReturn = false; // 브라우저로 나갔고 복귀 대기 중
  bool _showAdvanced = false; // OAuth 제공자에서 코드 직접 입력 펼침
  MailApiException? _oauthError; // 동의 URL 발급 실패(인라인 배너 — NR0007 §6 L3)

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

  /// 브라우저에서 동의 후 앱으로 복귀하면(resumed) 계정을 자동 재조회해 연결을
  /// 감지한다(딥링크 없이도 "코드 안 만지는" 흐름을 닫는 핵심 — TR0005 §증상2).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _refreshAfterReturn();
    }
  }

  /// OAuth 시작: 동의 URL 을 받아 외부 브라우저로 연다.
  Future<void> _startOAuth() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _oauthBusy = true;
      _oauthError = null; // 재시도 시 직전 실패 배너 제거
    });
    final res = await context.read<AccountProvider>().oauthAuthorizeUrl(_provider);
    if (!mounted) return;
    if (res.url == null) {
      // 토스트-후-막힘(NR0007 §5.4) 대신 분화된 인라인 실패 배너로 남긴다 —
      // 원인(L1)+진단(L2)+재시도/대체경로(L3)를 한자리에서 제공한다.
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

  /// 복귀 후(또는 "연결 확인" 탭) 계정 목록을 재조회해 새 계정을 감지한다.
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
    // 수동(코드) 경로도 분화된 문구 + 진단 꼬리표(L1·L2)로 알린다.
    AppToast.error(context, '${_connectErrorMessage(t, err)}  (${diagnosticLabel(err)})');
  }

  /// 서버 에러를 사용자 문구로 — NR0007 §6 L1. catch-all 단일 토스트를 원인별로
  /// 분화한다(분류는 [classifyConnectFailure], mail_envelope §순수함수).
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
          // ── 온보딩 안내(무계정일 때 강조) ──────────────────────────────
          if (!accounts.hasAccounts) ...[
            _OnboardingHeader(
              title: t.accountOnboardingTitle,
              body: t.accountOnboardingBody,
            ),
            const SizedBox(height: 24),
          ],

          // ── 연결된 계정 ────────────────────────────────────────────────
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

          // ── 계정 추가 ──────────────────────────────────────────────────
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

  // ── OAuth(브라우저) 경로 ──────────────────────────────────────────────
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

  /// 동의 URL 발급 실패 인라인 배너 — NR0007 §6 L3. 토스트만 띄우고 막다른
  /// 화면으로 두던 것 대신, OAuth 섹션에 **원인(L1) + 진단 꼬리표(L2) + 다시 시도
  /// / 코드 직접 입력 전환** 을 한자리에 둔다(게이트 인라인 배너 패턴 재사용).
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
            // 진단 꼬리표(code · HTTP status · requestId) — 지원/디버그용.
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

  // ── 수동(코드/비밀번호 직접 입력) 경로 ─────────────────────────────────
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
