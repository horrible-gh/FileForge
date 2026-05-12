import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';

class ServerSettingsDialog extends StatefulWidget {
  const ServerSettingsDialog({super.key});

  @override
  State<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _loadSavedValue();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSavedValue() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('server_url') ?? '';
    if (!mounted) return;
    setState(() => _controller.text = saved);
  }

  /// 입력값 검증. null 반환 시 유효.
  ///
  /// 유효한 형식:
  ///   1. `scheme://host:port` — Uri.tryParse() 사용, hasAuthority == true
  ///   2. `scheme://host`      — 포트 없는 도메인 URL
  ///   3. `host:port`          — scheme 없음, 포트는 숫자 1~65535
  String? _validate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final hasScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://');

    if (hasScheme) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null || !uri.hasAuthority) return 'Invalid format';
      return null;
    }

    // scheme 없음 → host:port 형식 필요
    final colonIndex = trimmed.lastIndexOf(':');
    if (colonIndex == -1) {
      return 'Port number is required (e.g., 192.168.1.10:8000 or https://example.com)';
    }

    final portStr = trimmed.substring(colonIndex + 1);
    final port = int.tryParse(portStr);
    if (port == null) return 'Port number must be numeric';
    if (port < 1 || port > 65535) return 'Port out of range (1-65535)';

    return null;
  }

  /// http:// 시작이거나 scheme 없는 입력(→ http 처리)이면 경고 표시.
  bool get _showHttpWarning {
    final t = _controller.text.trim();
    if (t.isEmpty) return false;
    return !t.startsWith('https://');
  }

  bool get _isSaveDisabled => _validate(_controller.text) != null;

  Future<void> _testConnection() async {
    final trimmed = _controller.text.trim();
    final String testUrl;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      testUrl = '$trimmed/fileforge/health';
    } else {
      testUrl = 'http://$trimmed/fileforge/health';
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));
      final response = await dio.get<Map<String, dynamic>>(testUrl);
      final version = response.data?['version'] ?? '';
      if (!mounted) return;
      setState(() {
        _testResult = '✓ Connection succeeded (Version: $version)';
        _testSuccess = true;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = '✗ Connection failed: ${e.message ?? e.toString()}';
        _testSuccess = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = '✗ Connection failed: $e';
        _testSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _save() async {
    final trimmed = _controller.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', trimmed);
    if (!mounted) return;
    context.read<AuthProvider>().setServerUrl(trimmed);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final validationError = _validate(_controller.text);

    return AlertDialog(
      title: const Text('Server Settings'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Server Address',
                hintText: '192.168.1.10:8000 or https://example.com',
                border: const OutlineInputBorder(),
                errorText: validationError,
              ),
            ),
            if (_showHttpWarning) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠ Unsecured connection',
                        style: TextStyle(color: Colors.amber, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testSuccess ? colorScheme.primary : colorScheme.error,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _isTesting ? null : _testConnection,
          child: _isTesting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Test Connection'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_isTesting || _isSaveDisabled) ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
