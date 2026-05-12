import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/node.dart';
import '../providers/share_link_provider.dart';
import '../config/env.dart';
import 'app_toast.dart';

/// D004 §2-1 — 공유 링크 생성 BottomSheet
/// - 대상 노드 아이콘 + 이름 표시
/// - 비밀번호 스위치/조건부 입력
/// - 링크 생성 (POST /share/create via ShareLinkProvider)
/// - 생성 URL 표시 + 클립보드 복사 + 2초 피드백
/// - BottomSheet 열릴 때마다 상태 초기화 (StatefulWidget)
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

  /// P005 §1 기준: Env.shareBaseUrl에 /share/{token} 조합
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
            // 헤더
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
            // 대상 노드 표시
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
            // 비밀번호 스위치
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
            // 비밀번호 입력 필드 — 스위치 ON일 때만 표시
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
            // 링크 생성 버튼
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
            // 생성 결과 URL + 복사 버튼
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
