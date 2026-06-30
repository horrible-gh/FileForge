import 'package:flutter/material.dart';

/// Blocking progress indicator shown while a file download is in flight.
///
/// fileforge.ui.0002 ("고스트 다운로드"): file downloads buffer the whole
/// response before the only feedback (a terminal toast) fires, so the user
/// sees an unchanged ("ghost") screen for the entire transfer. This overlay
/// gives an immediate "downloading…" cue the moment a download starts:
///   - a [ModalBarrier] blocks input (also prevents duplicate-tap restarts),
///   - a [CircularProgressIndicator] that is indeterminate until the first
///     progress callback arrives with a known total, then determinate (%),
///   - the label updates to show the percentage when available.
///
/// Lifecycle is explicit so callers can wrap their existing
/// download-then-save flow without restructuring it:
/// ```dart
/// final progress = DownloadProgressOverlay.show(context, label: t.fileDownloading);
/// try {
///   final res = await service.download(..., onReceiveProgress: progress.onProgress);
///   await DownloadSaveService.saveBytes(...);
/// } finally {
///   progress.hide();
/// }
/// ```
class DownloadProgressOverlay {
  final OverlayEntry _entry;
  final _DownloadProgressController _controller;
  bool _hidden = false;

  DownloadProgressOverlay._(this._entry, this._controller);

  /// Inserts the overlay into the nearest [Overlay] and returns a handle.
  ///
  /// [label] is the indeterminate message (e.g. "Downloading…").
  /// [percentLabel], when provided, formats the determinate message from a
  /// 0–100 integer once the total size is known.
  static DownloadProgressOverlay show(
    BuildContext context, {
    required String label,
    String Function(int percent)? percentLabel,
  }) {
    final controller = _DownloadProgressController(
      label: label,
      percentLabel: percentLabel,
    );
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _DownloadProgressWidget(controller: controller),
    );
    Overlay.of(context).insert(entry);
    return DownloadProgressOverlay._(entry, controller);
  }

  /// Dio-compatible progress callback. [total] is -1 when the server omits
  /// Content-Length; in that case the indicator stays indeterminate.
  void onProgress(int received, int total) {
    if (_hidden) return;
    if (total > 0) {
      final pct = ((received / total) * 100).clamp(0, 100).round();
      _controller.ratio.value = received / total;
      _controller.percent.value = pct;
    }
  }

  /// Removes the overlay. Idempotent.
  void hide() {
    if (_hidden) return;
    _hidden = true;
    _controller.dispose();
    _entry.remove();
  }
}

class _DownloadProgressController {
  final String label;
  final String Function(int percent)? percentLabel;

  /// null = indeterminate; otherwise 0.0–1.0.
  final ValueNotifier<double?> ratio = ValueNotifier<double?>(null);

  /// null = unknown; otherwise 0–100.
  final ValueNotifier<int?> percent = ValueNotifier<int?>(null);

  _DownloadProgressController({required this.label, this.percentLabel});

  void dispose() {
    ratio.dispose();
    percent.dispose();
  }
}

class _DownloadProgressWidget extends StatelessWidget {
  final _DownloadProgressController controller;

  const _DownloadProgressWidget({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ModalBarrier(
          color: Colors.black45,
          dismissible: false,
        ),
        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 16),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<double?>(
                    valueListenable: controller.ratio,
                    builder: (_, ratio, _) => SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(value: ratio),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<int?>(
                    valueListenable: controller.percent,
                    builder: (_, pct, _) {
                      final text = (pct != null &&
                              controller.percentLabel != null)
                          ? controller.percentLabel!(pct)
                          : controller.label;
                      return Text(
                        text,
                        style: Theme.of(context).textTheme.bodyMedium,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
