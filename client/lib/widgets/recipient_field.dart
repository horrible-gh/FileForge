import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mail.dart';
import '../services/mail_compose.dart';

/// translated text text text text — text textminutes text translated text text(text)text translated text.
/// (TR0007 §4 "translated text text text text" remaining worktext.)
///
/// - text/translated text/text/translated text current translated text translated text translated text(`parseAddresses`).
/// - translated text translated text translated text text errortranslated text translated text(`isValidEmail` translated text).
/// - empty translated text translated text translated text text text statetext translated text.
/// - translated text translated text text translated text translated text translated text.
///
/// text translated text text translated text text(compose screen)text — change text [onChanged]text translated text
/// translated text translated text translated text [addresses]text again translated text.
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

  /// translated text translated text translated text translated text.
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
    // textminutestext translated text text translated text(text text UX).
    if (value.isNotEmpty && RegExp(r'[,;\s]$').hasMatch(value)) {
      _commitPending();
    }
  }

  /// empty translated text translated text → translated text text translated text translated text text.
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
