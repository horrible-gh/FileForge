import 'package:flutter/material.dart';

/// toast text.
enum ToastType { success, error, warning, info }

/// text text toast text.
///
/// translated text:
/// ```dart
/// AppToast.success(context, 'file upload complete');
/// AppToast.error(context, 'server Connection failed');
/// AppToast.warning(context, 'save translated text translated text');
/// AppToast.info(context, 'text resulttext translated text');
/// ```
class AppToast {
  // ── translated text API ─────────────────────────────────────────────────────────────

  static void success(BuildContext context, String message,
          {Duration duration = const Duration(seconds: 2)}) =>
      _show(context, message, type: ToastType.success, duration: duration);

  static void error(BuildContext context, String message,
          {Duration duration = const Duration(seconds: 4)}) =>
      _show(context, message, type: ToastType.error, duration: duration);

  static void warning(BuildContext context, String message,
          {Duration duration = const Duration(seconds: 3)}) =>
      _show(context, message, type: ToastType.warning, duration: duration);

  static void info(BuildContext context, String message,
          {Duration duration = const Duration(seconds: 2)}) =>
      _show(context, message, type: ToastType.info, duration: duration);

  // ── text text ───────────────────────────────────────────────────────────────

  static void _show(
    BuildContext context,
    String message, {
    required ToastType type,
    required Duration duration,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        type: type,
        duration: duration,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

// ── text text ───────────────────────────────────────────────────────────────

class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _bgColor {
    switch (widget.type) {
      case ToastType.success:
        return const Color(0xFF10b981);
      case ToastType.error:
        return const Color(0xFFef4444);
      case ToastType.warning:
        return const Color(0xFFf59e0b);
      case ToastType.info:
        return const Color(0xFF3b82f6);
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case ToastType.success:
        return Icons.check_circle_outline;
      case ToastType.error:
        return Icons.error_outline;
      case ToastType.warning:
        return Icons.warning_amber_outlined;
      case ToastType.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 60,
      left: 24,
      right: 24,
      child: FadeTransition(
        opacity: _opacity,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _bgColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 8),
              ],
            ),
            child: Row(
              children: [
                Icon(_icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
