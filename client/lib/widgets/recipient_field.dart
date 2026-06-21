import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mail.dart';
import '../services/mail_compose.dart';

/// 수신자 태그 입력 위젯 — 쉼표 구분 평문 입력을 칩(태그)으로 대체한다.
/// (TR0007 §4 "수신자 태그 입력 위젯" 잔여작업.)
///
/// - 쉼표/세미콜론/공백/엔터로 현재 입력을 칩으로 확정한다(`parseAddresses`).
/// - 형식이 잘못된 주소는 칩을 에러색으로 강조한다(`isValidEmail` 선검사).
/// - 빈 입력에서 백스페이스는 마지막 칩을 편집 상태로 되돌린다.
/// - 포커스를 잃으면 입력 중이던 텍스트를 확정한다.
///
/// 주소 목록의 단일 진실원은 부모(작성 화면)다 — 변경 시 [onChanged]로 통지하고
/// 부모가 보관한 목록을 [addresses]로 다시 주입받는다.
class RecipientField extends StatefulWidget {
  final String label;
  final List<MailAddress> addresses;
  final ValueChanged<List<MailAddress>> onChanged;
  final String? errorText;

  const RecipientField({
    super.key,
    required this.label,
    required this.addresses,
    required this.onChanged,
    this.errorText,
  });

  @override
  State<RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<RecipientField> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commitPending();
  }

  /// 입력창의 텍스트를 칩으로 확정한다.
  void _commitPending() {
    final raw = _input.text.trim();
    if (raw.isEmpty) return;
    _input.clear();
    final added = parseAddresses(raw);
    if (added.isEmpty) return;
    final existing = widget.addresses.map((a) => a.address.toLowerCase()).toSet();
    final merged = [...widget.addresses];
    for (final a in added) {
      if (existing.add(a.address.toLowerCase())) merged.add(a);
    }
    widget.onChanged(merged);
  }

  void _removeAt(int index) {
    final next = [...widget.addresses]..removeAt(index);
    widget.onChanged(next);
  }

  void _onChanged(String value) {
    // 구분자가 들어오면 즉시 확정한다(태그 입력 UX).
    if (value.isNotEmpty && RegExp(r'[,;\s]$').hasMatch(value)) {
      _commitPending();
    }
  }

  /// 빈 입력에서 백스페이스 → 마지막 칩을 입력창으로 되돌려 편집.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _input.text.isEmpty &&
        widget.addresses.isNotEmpty) {
      final last = widget.addresses.last;
      _removeAt(widget.addresses.length - 1);
      _input.text = last.address;
      _input.selection =
          TextSelection.collapsed(offset: _input.text.length);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      isFocused: _focus.hasFocus,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < widget.addresses.length; i++)
            _chip(theme, widget.addresses[i], i),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120),
            child: Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: _input,
                focusNode: _focus,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'a@example.com',
                ),
                onChanged: _onChanged,
                onSubmitted: (_) => _commitPending(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, MailAddress addr, int index) {
    final invalid = !isValidEmail(addr.address);
    final bg = invalid
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final fg = invalid
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;
    return InputChip(
      backgroundColor: bg,
      label: Text(addr.display, style: TextStyle(color: fg)),
      avatar: invalid
          ? Icon(Icons.error_outline, size: 16, color: fg)
          : null,
      onDeleted: () => _removeAt(index),
      deleteIconColor: fg,
    );
  }
}
