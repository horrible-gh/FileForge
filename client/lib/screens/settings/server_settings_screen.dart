import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';

class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  final TextEditingController _controller = TextEditingController();
  String _savedValue = '';
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
    setState(() {
      _savedValue = saved;
      _controller.text = saved;
    });
  }

  /// translated text verify. null return text text.
  String? _validate(String value) {
    final t = AppLocalizations.of(context);
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    String hostPort = trimmed;
    if (hostPort.startsWith('http://')) {
      hostPort = hostPort.substring(7);
    } else if (hostPort.startsWith('https://')) {
      hostPort = hostPort.substring(8);
    }

    // text text text
    if (hostPort.startsWith('http://') || hostPort.startsWith('https://')) {
      return t.serverInvalidFormat;
    }

    final colonIndex = hostPort.lastIndexOf(':');
    if (colonIndex == -1) {
      return t.serverPortRequired;
    }

    final portStr = hostPort.substring(colonIndex + 1);
    final port = int.tryParse(portStr);
    if (port == null) return t.serverPortNumeric;
    if (port < 1 || port > 65535) return t.serverPortRange;

    return null;
  }

  bool get _showHttpWarning => _controller.text.trim().startsWith('http://');

  bool get _isSaveDisabled {
    if (_controller.text.trim() == _savedValue) return true;
    if (_validate(_controller.text) != null) return true;
    return false;
  }

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
        _testResult = '✓ Connection successful (Version: $version)';
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
    final t = AppLocalizations.of(context);
    final trimmed = _controller.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', trimmed);
    if (!mounted) return;
    context.read<AuthProvider>().setServerUrl(trimmed);
    setState(() => _savedValue = trimmed);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.commonSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final validationError = _validate(_controller.text);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.navServerSettings),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final authProvider = context.read<AuthProvider>();
            if (authProvider.isAuthenticated) {
              context.pop();
            } else {
              context.go('/login');
            }
          },
        ),
      ),
      body: ListView(
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
                      const Icon(Icons.dns_rounded),
                      const SizedBox(width: 8),
                      Text(
                        t.serverAddress,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.serverAddressDesc,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _controller,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: t.serverAddress,
                      hintText: t.serverAddressHint,
                      border: const OutlineInputBorder(),
                      errorText: validationError,
                    ),
                  ),
                  if (_showHttpWarning) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                              '⚠ HTTP connections are not secure. HTTPS is recommended.',
                              style: TextStyle(
                                  color: Colors.amber, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isTesting ? null : _testConnection,
                          child: _isTesting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Text(t.serverTestConnection),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              (_isTesting || _isSaveDisabled) ? null : _save,
                          child: Text(t.commonSave),
                        ),
                      ),
                    ],
                  ),
                  if (_testResult != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testSuccess
                            ? colorScheme.primary
                            : colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

