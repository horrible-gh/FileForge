import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/node.dart';
import '../providers/share_link_provider.dart';
import '../config/env.dart';
import 'app_toast.dart';

/// D004 §2-1 — Create a shared link BottomSheet
/// - text text translated text + name display
/// - password translated text/translated text text
/// - text create (POST /share/create via ShareLinkProvider)
/// - create URL display + translated text text + 2text translated text
/// - BottomSheet text translated text state initialize (StatefulWidget)
class ShareLinkBottomSheet extends StatefulWidget {
  final Node node;

  const ShareLinkBottomSheet({super.key, required this.node});

  @override
  State<ShareLinkBottomSheet> createState() => _ShareLinkBottomSheetState();
}

class _ShareLinkBottomSheetState extends State<ShareLinkBottomSheet> {
  bool _usePassword = false;
  final _passwordController = TextEditingController();

  String? _generatedUrl;
  bool _copied = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  /// P005 §1 text: Env.shareBaseUrltext /share/{token} text
  String _buildShareUrl(String token) {
    return '${Env.shareBaseUrl}/share/$token';
  }

  Future<void> _createLink() async {
    final provider = context.read<ShareLinkProvider>();
    final nodeUuid = widget.node.nodeUuid ?? '';
    final nodeType = widget.node.type;
    final password = _usePassword ? _passwordController.text : null;

    final result = await provider.createLink(nodeUuid, nodeType, password);
    if (!mounted) return;
    if (result != null) {
      final token = result['token'] as String? ?? '';
      setState(() {
        _generatedUrl = _buildShareUrl(token);
      });
    } else if (provider.error != null) {
      AppToast.error(context, 'Failed to create link: ${provider.error}');
    }
  }

  Future<void> _copyUrl() async {
    if (_generatedUrl == null) return;
    await Clipboard.setData(ClipboardData(text: _generatedUrl!));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select<ShareLinkProvider, bool>(
      (p) => p.isLoading,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                'Create Share Link',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            // text text display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    widget.node.isFolder
                        ? Icons.folder_rounded
                        : Icons.insert_drive_file_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.node.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // password translated text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Set Password'),
                  Switch(
                    value: _usePassword,
                    onChanged: isLoading
                        ? null
                        : (v) => setState(() {
                              _usePassword = v;
                              if (!v) _passwordController.clear();
                            }),
                  ),
                ],
              ),
            ),
            // password text text — translated text ONtext text display
            if (_usePassword)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _passwordController,
                  enabled: !isLoading,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Enter password',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            // text create text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _createLink,
                  child: isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Link'),
                ),
              ),
            ),
            // create result URL + text text
            if (_generatedUrl != null) ...[
              const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _generatedUrl!,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _copied ? null : _copyUrl,
                      icon: Icon(
                        _copied
                            ? Icons.check_circle_rounded
                            : Icons.content_copy_rounded,
                        size: 18,
                      ),
                      label: Text(_copied ? 'Copied' : 'Copy'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
