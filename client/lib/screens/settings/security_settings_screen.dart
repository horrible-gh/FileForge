import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/auth_exception.dart';
import '../../providers/auth_provider.dart';
import '../../services/download_save_service.dart';
import '../../services/totp_service.dart';
import '../../widgets/app_toast.dart';

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

  bool _isLoadingStatus = true;
  bool _totpEnabled = false;

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
      _loadStatus();
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
      AppToast.error(context, 'Failed to retrieve TOTP status');
    }
  }

  Future<void> _startSetup() async {
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
      AppToast.error(context, 'Setup failed. Please try again');
    } catch (_) {
      if (!mounted) return;
      setState(() => _setupPhase = _SetupPhase.idle);
      AppToast.error(context, 'Setup failed. Please try again');
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
    final code = _setupCodeController.text.trim();
    if (code.length != 6) {
      setState(() => _setupError = 'Enter 6-digit code');
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
      AppToast.success(context, 'Two-step authentication has been enabled');
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.detail == 'invalid_code') {
        setState(() {
          _setupError = 'Invalid code';
          _setupCodeController.clear();
        });
        return;
      }
      AppToast.error(context, 'Setup failed. Please try again');
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Setup failed. Please try again');
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
    final code = _disableCodeController.text.trim();
    if (code.length != 6) {
      setState(() => _disableError = 'Enter 6-digit code');
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
      AppToast.success(context, 'Two-step authentication has been disabled');
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.detail == 'invalid_code') {
        setState(() {
          _disableError = 'Invalid code';
          _disableCodeController.clear();
        });
        return;
      }
      AppToast.error(context, 'Setup failed. Please try again');
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Setup failed. Please try again');
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
    final code = _regenCodeController.text.trim();
    if (code.length != 6) {
      setState(() => _regenError = 'Enter 6-digit code');
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
      AppToast.success(context, 'Recovery codes have been regenerated');
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.detail == 'invalid_code') {
        setState(() {
          _regenError = 'Invalid code';
          _regenCodeController.clear();
        });
        return;
      }
      AppToast.error(context, 'Setup failed. Please try again');
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Setup failed. Please try again');
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

    return RefreshIndicator(
      onRefresh: _loadStatus,
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
                      const Expanded(
                        child: Text(
                          'Two-Step Authentication (TOTP)',
                          style: TextStyle(
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
                    'Extra security using authenticator apps like Google Authenticator',
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
        ],
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context) {
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
        enabled ? 'Enabled' : 'Disabled',
        style: TextStyle(
          color: fgColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSetupSection(BuildContext context) {
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
          child: const Text('Enable Two-Step Authentication'),
        ),
      );
    }

    final setup = _setupResponse!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Step 1. Scan QR Code',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('Scan the QR code below with your authenticator app.'),
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
                child: const Text('Unable to display QR image'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Step 2. Save Recovery Codes',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('If you lose access, recovery codes can help you regain account access.'),
        const SizedBox(height: 10),
        _buildCodeGrid(setup.recoveryCodes),
        const SizedBox(height: 20),
        const Text(
          'Step 3. Enter Authentication Code',
          style: TextStyle(fontWeight: FontWeight.w600),
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
          decoration: const InputDecoration(
            labelText: 'Authentication Code',
            border: OutlineInputBorder(),
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
              child: const Text('Enable'),
            ),
            OutlinedButton(
              onPressed: _cancelSetup,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDisableSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        const Text(
          'Disable Two-Step Authentication',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (_disablePhase == _DisablePhase.idle)
          FilledButton.tonal(
            onPressed: _startDisable,
            child: const Text('Disable Two-Step Authentication'),
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
                decoration: const InputDecoration(
                  labelText: 'Current Code',
                  border: OutlineInputBorder(),
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
                    child: const Text('Disable'),
                  ),
                  OutlinedButton(
                    onPressed: _cancelDisable,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildRegenerateSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        const Text(
          'Regenerate Recovery Codes',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (_regenPhase == _RegenPhase.idle)
          FilledButton.tonal(
            onPressed: _startRegenerate,
            child: const Text('Regenerate Recovery Codes'),
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
                decoration: const InputDecoration(
                  labelText: 'Current Code',
                  border: OutlineInputBorder(),
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
                    child: const Text('Regenerate'),
                  ),
                  OutlinedButton(
                    onPressed: _cancelRegenerate,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        if (_regenPhase == _RegenPhase.done) ...[
          const Text('New recovery codes. Store them in a safe place.'),
          const SizedBox(height: 10),
          _buildCodeGrid(_regeneratedCodes),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _closeRegeneratedCodes,
            child: const Text('Close'),
          ),
        ],
      ],
    );
  }

  Future<void> _copyRecoveryCodes(List<String> codes) async {
    await Clipboard.setData(ClipboardData(text: codes.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recovery codes copied')),
    );
  }

  Future<void> _downloadRecoveryCodes(List<String> codes) async {
    await DownloadSaveService.saveBytes(
      bytes: utf8.encode(codes.join('\n')),
      filename: 'recovery_codes.txt',
    );
  }

  Widget _buildCodeGrid(List<String> codes) {
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
              label: const Text('Copy'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _downloadRecoveryCodes(codes),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download'),
            ),
          ],
        ),
      ],
    );
  }
}
