/// A plain-text mail body whose URLs are tappable (R0001 / 0031, NR0003 B).
///
/// The detail screen wraps the body in a [SelectionArea]; a `Text.rich` here
/// stays drag-selectable while link runs carry a [TapGestureRecognizer] that
/// routes through [confirmAndOpenMailLink] (scheme allow-list + confirm). The
/// recognizers are owned by this [State] and disposed with it.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/mail_link_launcher.dart';
import '../utils/mail_text_linkify.dart';

class MailLinkedText extends StatefulWidget {
  const MailLinkedText(this.text, {super.key});

  final String text;

  @override
  State<MailLinkedText> createState() => _MailLinkedTextState();
}

class _MailLinkedTextState extends State<MailLinkedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final runs = linkifyPlainText(widget.text);

    // No links → a plain Text, identical to the previous rendering.
    if (runs.length == 1 && !runs.first.isLink) {
      return Text(widget.text);
    }

    final linkStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );

    final spans = <InlineSpan>[];
    for (final run in runs) {
      if (!run.isLink) {
        spans.add(TextSpan(text: run.text));
        continue;
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => confirmAndOpenMailLink(context, run.url!);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: run.text,
        style: linkStyle,
        recognizer: recognizer,
      ));
    }
    return Text.rich(TextSpan(children: spans));
  }
}
