import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/auth_exception.dart';
import '../../providers/auth_provider.dart';
import '../../services/download_save_service.dart';
import '../../services/session_service.dart';
import '../../services/totp_service.dart';
import '../../models/user_session.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/note_card.dart' show formatRelativeDate;
import '../../l10n/app_localizations.dart';

enum _SetupPhase { idle, loading, qr }
enum _DisablePhase { idle, confirm }
enum _RegenPhase { idle, confirm, done }

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final TextEditingController _setupCodeController = TextEditingController();
  final TextEditingController _disableCodeController = TextEditingController();
  final TextEditingController _regenCodeController = TextEditingController();

  late TotpService _totpService;
  late SessionService _sessionService;

  bool _isLoadingStatus = true;
  bool _totpEnabled = false;

  // Signed-in devices (fileforge.default.0004 T3). Never cached across visits:
  // a stale list shows sessions the user already ended (D0003 §7.5).
  bool _isLoadingSessions = true;
  List<UserSession> _sessions = const [];
  bool _sessionsUnavailable = false;
  String? _busySid;
  bool _revokingOthers = false;

  _SetupPhase _setupPhase = _SetupPhase.idle;
  _DisablePhase _disablePhase = _DisablePhase.idle;
  _RegenPhase _regenPhase = _RegenPhase.idle;

  TotpSetupResponse? _setupResponse;
  List<String> _regeneratedCodes = [];

  String? _setupError;
  String? _disableError;
  String? _regenError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();
      _totpService = TotpService(authProvider.dio);
      _sessionService = SessionService(authProvider.dio);
      _loadStatus();
      _loadSessions();
    });
  }

  @override
  void dispose() {
    _setupCodeController.dispose();
    _disableCodeController.dispose();
    _regenCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final t = AppLocalizations.of(context);
    setState(() => _isLoadingStatus = true);
    try {
      final enabled = await _totpService.getStatus();
      if (!mounted) return;
      setState(() {
        _totpEnabled = enabled;
        _isLoadingStatus = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingStatus = false);
      AppToast.error(context, t.securityTotpStatusFailed);
    }
  }

  Future<void> _loadSessions() async {
    final t = AppLocalizations.of(context);
    setState(() => _isLoadingSessions = true);
    try {
      final result = await _sessionService.list();
      if (!mounted) return;
      setState(() {
        _sessions = result.sessions;
        _sessionsUnavailable = result.sessionUnavailable;
        _isLoadingSessions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingSessions = false);
      AppToast.error(context, t.sessionsLoadFailed);
    }
  }

  Future<bool> _confirm(String message) async {
    final t = AppLocalizations.of(context);
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.commonConfirm),
          ),
        ],
      ),
    );
    return answer == true;
  }

  Future<void> _revokeSession(UserSession session) async {
    final t = AppLocalizations.of(context);
    if (!await _confirm(t.sessionsSignOutConfirm(session.deviceLabel))) return;
    if (!mounted) return;

    setState(() => _busySid = session.sid);
    try {
      // `was_current` means we just ended our own session; the shared 401
      // interceptor will route to login on the next request, so there is no list
      // left worth reloading.
      final wasCurrent = await _sessionService.revoke(session.sid);
      if (!mounted) return;
      setState(() => _busySid = null);
      AppToast.success(context, t.sessionsSignedOutOne);
      if (!wasCurrent) await _loadSessions();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busySid = null);
      AppToast.error(context, t.sessionsActionFailed);
      // The failure may be "already gone" (404), so resync rather than leaving a
      // card the server no longer knows about.
      await _loadSessions();
    }
  }

  Future<void> _revokeOtherSessions() async {
    final t = AppLocalizations.of(context);
    if (!await _confirm(t.sessionsSignOutOthersConfirm)) return;
    if (!mounted) return;

    setState(() => _revokingOthers = true);
    try {
      final revoked = await _sessionService.revokeOthers();
      if (!mounted) return;
      setState(() => _revokingOthers = false);
      AppToast.success(context, t.sessionsSignedOutOthers(revoked));
      await _loadSessions();
    } catch (_) {
      if (!mounted) return;
      setState(() => _revokingOthers = false);
      AppToast.error(context, t.sessionsActionFailed);
    }
  }

  Future<void> _startSetup() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _setupPhase = _SetupPhase.loading;
      _setupError = null;
      _setupCodeController.clear();
    });

    try {
      final setupResp = await _totpService.setup();
      if (!mounted) return;
      setState(() {
        _setupResponse = setupResp;
        _setupPhase = _SetupPhase.qr;
      });
    } on AuthException {
      if (!mounted) return;
      setState(() => _setupPhase = _SetupPhase.idle);
      AppToast.error(context, t.securitySetupFailed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _setupPhase = _SetupPhase.idle);
      AppToast.error(context, t.securitySetupFailed);
    }
  }

  void _cancelSetup() {
    setState(() {
      _setupPhase = _SetupPhase.idle;
      _setupResponse = null;
      _setupError = null;
      _setupCodeController.clear();
    });
  }

  Future<void> _activateSetup() async {
    final t = AppLocalizations.of(context);
    final code = _setupCodeController.text.trim();
    if (code.length != 6) {
      setState(() => _setupError = t.totpEnterCodeError);
      return;
    }

    setState(() => _setupError = null);
    try {
      await _totpService.activate(code);
      if (!mounted) return;
      setState(() {
        _totpEnabled = true;
        _setupPhase = _SetupPhase.idle;
        _setupResponse = null;
        _setupCodeController.clear();
        _setupError = null;
      });
      AppToast.success(context, t.security2faEnabled);
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.detail == 'invalid_code') {
        setState(() {
          _setupError = t.securityInvalidCode;
          _setupCodeController.clear();
        });
        return;
      }
      AppToast.error(context, t.securitySetupFailed);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, t.securitySetupFailed);
    }
  }

  void _startDisable() {
    setState(() {
      _disablePhase = _DisablePhase.confirm;
      _disableError = null;
      _disableCodeController.clear();
    });
  }

  void _cancelDisable() {
    setState(() {
      _disablePhase = _DisablePhase.idle;
      _disableError = null;
      _disableCodeController.clear();
    });
  }

  Future<void> _confirmDisable() async {
    final t = AppLocalizations.of(context);
    final code = _disableCodeController.text.trim();
    if (code.length != 6) {
      setState(() => _disableError = t.totpEnterCodeError);
      return;
    }

    setState(() => _disableError = null);
    try {
      await _totpService.disable(code);
      if (!mounted) return;
      setState(() {
        _totpEnabled = false;
        _disablePhase = _DisablePhase.idle;
        _regenPhase = _RegenPhase.idle;
        _regeneratedCodes = [];
        _disableError = null;
        _regenError = null;
        _disableCodeController.clear();
        _regenCodeController.clear();
      });
      AppToast.success(context, t.security2faDisabled);
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.detail == 'invalid_code') {
        setState(() {
          _disableError = t.securityInvalidCode;
          _disableCodeController.clear();
        });
        return;
      }
      AppToast.error(context, t.securitySetupFailed);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, t.securitySetupFailed);
    }
  }

  void _startRegenerate() {
    setState(() {
      _regenPhase = _RegenPhase.confirm;
      _regenError = null;
      _regenCodeController.clear();
    });
  }

  void _cancelRegenerate() {
    setState(() {
      _regenPhase = _RegenPhase.idle;
      _regenError = null;
      _regenCodeController.clear();
    });
  }

  Future<void> _confirmRegenerate() async {
    final t = AppLocalizations.of(context);
    final code = _regenCodeController.text.trim();
    if (code.length != 6) {
      setState(() => _regenError = t.totpEnterCodeError);
      return;
    }

    setState(() => _regenError = null);
    try {
      final codes = await _totpService.regenerate(code);
      if (!mounted) return;
      setState(() {
        _regeneratedCodes = codes;
        _regenPhase = _RegenPhase.done;
        _regenCodeController.clear();
      });
      AppToast.success(context, t.securityRecoveryRegenerated);
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.detail == 'invalid_code') {
        setState(() {
          _regenError = t.securityInvalidCode;
          _regenCodeController.clear();
        });
        return;
      }
      AppToast.error(context, t.securitySetupFailed);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, t.securitySetupFailed);
    }
  }

  void _closeRegeneratedCodes() {
    setState(() {
      _regenPhase = _RegenPhase.idle;
      _regeneratedCodes = [];
      _regenError = null;
      _regenCodeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingStatus) {
      return const Center(child: CircularProgressIndicator());
    }
    final t = AppLocalizations.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        await _loadStatus();
        await _loadSessions();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.key_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.securitySectionTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _buildStatusChip(context),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.securitySectionDesc,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!_totpEnabled) _buildSetupSection(context),
                  if (_totpEnabled) ...[
                    _buildDisableSection(context),
                    const SizedBox(height: 20),
                    _buildRegenerateSection(context),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSessionCard(context),
        ],
      ),
    );
  }

  /// "Signed-in devices" — added to the existing security screen rather than a
  /// new route, since it belongs to the same "my account's security state"
  /// context as 2FA (D0003 §8).
  Widget _buildSessionCard(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.sessionsSectionTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t.sessionsSectionDesc,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _buildSessionSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingSessions) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Token predates multi-session support: the server cannot say which session
    // this is, so tell the user how to get the list (D0003 §6/§8).
    if (_sessionsUnavailable) {
      return Text(
        t.sessionsUnavailable,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      );
    }

    // Server order is last-used first; the current session is pinned to the top
    // regardless of when it was last touched (D0003 §8).
    final ordered = [
      ..._sessions.where((s) => s.isCurrent),
      ..._sessions.where((s) => !s.isCurrent),
    ];
    final hasOthers = ordered.any((s) => !s.isCurrent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final session in ordered) _buildSessionTile(context, session),
        if (!hasOthers)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t.sessionsEmpty,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        if (hasOthers) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _revokingOthers ? null : _revokeOtherSessions,
              icon: const Icon(Icons.logout_rounded),
              label: Text(t.sessionsSignOutOthers),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSessionTile(BuildContext context, UserSession session) {
    final t = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleStyle = TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontSize: 12,
    );
    final busy = _busySid == session.sid;

    final location = session.ipDisplay.isEmpty ? '' : '${session.ipDisplay} · ';
    final lastUsed = formatRelativeDate(session.lastUsedAt, t);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.deviceLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text('$location${t.sessionsLastUsed(lastUsed)}',
                    style: subtitleStyle),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // The current session gets a badge, not a button: ending the session
          // you are using is what Logout is for (D0003 §8).
          if (session.isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                t.sessionsCurrentBadge,
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton(
              onPressed: () => _revokeSession(session),
              child: Text(t.sessionsSignOut),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = _totpEnabled;
    final bgColor = enabled
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final fgColor = enabled
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        enabled ? t.securityStatusEnabled : t.securityStatusDisabled,
        style: TextStyle(
          color: fgColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSetupSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_setupPhase == _SetupPhase.loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_setupPhase == _SetupPhase.idle || _setupResponse == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: _startSetup,
          child: Text(t.securityEnable2fa),
        ),
      );
    }

    final setup = _setupResponse!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.securityStep1,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(t.securityScanQr),
        const SizedBox(height: 12),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              base64Decode(setup.qrImage),
              width: 220,
              height: 220,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 220,
                height: 220,
                color: Colors.black12,
                alignment: Alignment.center,
                child: Text(t.securityQrUnavailable),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          t.securityStep2,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(t.securityRecoveryInfo),
        const SizedBox(height: 10),
        _buildCodeGrid(setup.recoveryCodes),
        const SizedBox(height: 20),
        Text(
          t.securityStep3,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _setupCodeController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onSubmitted: (_) => _activateSetup(),
          decoration: InputDecoration(
            labelText: t.securityAuthCode,
            border: const OutlineInputBorder(),
            counterText: '',
          ),
        ),
        if (_setupError != null) ...[
          const SizedBox(height: 8),
          Text(
            _setupError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _activateSetup,
              child: Text(t.securityEnable),
            ),
            OutlinedButton(
              onPressed: _cancelSetup,
              child: Text(t.cancel),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDisableSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text(
          t.securityDisable2fa,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (_disablePhase == _DisablePhase.idle)
          FilledButton.tonal(
            onPressed: _startDisable,
            child: Text(t.securityDisable2fa),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _disableCodeController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onSubmitted: (_) => _confirmDisable(),
                decoration: InputDecoration(
                  labelText: t.securityCurrentCode,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              if (_disableError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _disableError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _confirmDisable,
                    child: Text(t.securityDisable),
                  ),
                  OutlinedButton(
                    onPressed: _cancelDisable,
                    child: Text(t.cancel),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildRegenerateSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text(
          t.securityRegenRecovery,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (_regenPhase == _RegenPhase.idle)
          FilledButton.tonal(
            onPressed: _startRegenerate,
            child: Text(t.securityRegenRecovery),
          ),
        if (_regenPhase == _RegenPhase.confirm)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _regenCodeController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onSubmitted: (_) => _confirmRegenerate(),
                decoration: InputDecoration(
                  labelText: t.securityCurrentCode,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              if (_regenError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _regenError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _confirmRegenerate,
                    child: Text(t.securityRegenerate),
                  ),
                  OutlinedButton(
                    onPressed: _cancelRegenerate,
                    child: Text(t.cancel),
                  ),
                ],
              ),
            ],
          ),
        if (_regenPhase == _RegenPhase.done) ...[
          Text(t.securityNewRecoveryInfo),
          const SizedBox(height: 10),
          _buildCodeGrid(_regeneratedCodes),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _closeRegeneratedCodes,
            child: Text(t.commonClose),
          ),
        ],
      ],
    );
  }

  Future<void> _copyRecoveryCodes(List<String> codes) async {
    final t = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: codes.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.securityRecoveryCopied)),
    );
  }

  Future<void> _downloadRecoveryCodes(List<String> codes) async {
    await DownloadSaveService.saveBytes(
      bytes: utf8.encode(codes.join('\n')),
      filename: 'recovery_codes.txt',
    );
  }

  Widget _buildCodeGrid(List<String> codes) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: codes
              .map(
                (code) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.black.withValues(alpha: 0.05),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => _copyRecoveryCodes(codes),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(t.commonCopy),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _downloadRecoveryCodes(codes),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(t.commonDownload),
            ),
          ],
        ),
      ],
    );
  }
}
