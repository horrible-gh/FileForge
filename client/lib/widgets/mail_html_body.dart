/// Mail HTML body renderer with layout-stable images (0009 R0001).
///
/// R0001 reported an endless flood of `mouse_tracker.dart:199 Assertion failed`
/// while a mail detail was open (NR0003). Root cause: the detail body's bare
/// [HtmlWidget] renders each `<img>` as a plain [Image] with **no pre-set
/// size**. When the image's `ImageStream` resolves (or fails), the Image jumps
/// from its placeholder size to the picture's natural size, forcing a
/// **synchronous relayout of the subtree the pointer is hovering over**. That
/// relayout re-enters Flutter's mouse device-update phase, tripping the
/// framework's debug-only re-entrancy `assert` once per frame/pointer event.
///
/// The fix (NR0003 §5.1, primary recommendation): give every image a
/// **deterministic box whose size does not depend on whether the stream is
/// resolved**, so resolving the stream never relayouts the hovered subtree and
/// the re-entrancy trigger disappears.
///
/// - `<img>` with `width`+`height` attributes → a tight box from the first
///   frame (no relayout ever), aspect preserved, width capped to the available
///   space.
/// - `<img>` without usable dimensions → the natural size is measured once,
///   off-band, via the image stream; the box settles to that size in a single
///   `setState` on a normal frame (outside the device-update phase). After that
///   the box is tight and constant, so hovering/scrolling never relayouts it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

/// Renders an HTML mail body. Two invariants keep image loading from tripping
/// the framework's debug assertions (R0001 / NR0003, and the 0005-TR rev0
/// regression):
///
///  1. Every `<img>` is forced to **`display:block`**. fwfh renders an inline
///     image as a `WidgetSpan` inside a `RenderParagraph`; computing that line's
///     baseline calls `getDryBaseline` on the image's render box, which trips
///     `box.dart:2292` (`RenderBox.size accessed in computeDryBaseline`) for any
///     box that isn't a trivial leaf (our [AspectRatio]/[Align] wrapper is not).
///     For image-heavy mail (e.g. SMBC card statements) this fires once per
///     image per layout pass — a continuous exception storm that *froze the
///     app*. As a block, the image is laid out as an ordinary column child; its
///     baseline is never queried, so that assert can no longer fire. `display`
///     routes through fwfh `parseStyleDisplay` → `StyleSizing.registerBlockOp`.
///  2. Every image is rendered through [StableImage], whose box size does not
///     depend on whether the image stream has resolved, so loading an image
///     cannot relayout the hovered subtree and trip the `mouse_tracker.dart:199`
///     re-entrancy assert.
class MailHtmlBody extends StatelessWidget {
  const MailHtmlBody(this.html, {super.key});

  /// Table-family tags forced to `display:block` so fwfh's collapsing column
  /// width algorithm is never entered (0020 R0001 / NR0003).
  static const Set<String> _tableTags = {
    'table',
    'thead',
    'tbody',
    'tfoot',
    'tr',
    'td',
    'th',
  };

  final String html;

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      html,
      factoryBuilder: () => MailImageFactory(),
      // Per-element style overrides:
      //  - `<img>`: force block-level. An inline image becomes a WidgetSpan
      //    whose baseline the RenderParagraph computes via getDryBaseline,
      //    tripping box.dart:2292 for our wrapped box. As a block the baseline
      //    is never queried. (`max-width:100%` keeps wide images in the
      //    viewport.)
      //  - table family (`table`/`thead`/`tbody`/`tfoot`/`tr`/`td`/`th`): force
      //    block-level (0020 R0001 / NR0003). fwfh 0.17.2's table column-width
      //    algorithm (`html_table.dart`) collapses the content column of a
      //    `min-width` nested table — the layout Google's security-alert mail
      //    uses (outer min-width table + a nested table whose content cell is
      //    flanked by ~8px spacer columns) — down to ~1 character per line, so
      //    the body renders "vertically, one glyph per row". Rendering the
      //    cells as ordinary block children bypasses that algorithm entirely
      //    and the content takes the available width. Mail-layout tables are
      //    near-linear reading flows, so block-stacking costs little
      //    readability. (`width:auto` clears any inline cell width that would
      //    otherwise pin the block narrow.)
      customStylesBuilder: (element) {
        if (element.localName == 'img') {
          return const {'display': 'block', 'max-width': '100%'};
        }
        if (_tableTags.contains(element.localName)) {
          return const {'display': 'block', 'width': 'auto'};
        }
        return null;
      },
      // Non-image render errors still fall back to a small broken-image glyph,
      // matching the previous detail-screen behaviour.
      onErrorBuilder: (context, element, error) =>
          const Icon(Icons.broken_image_outlined, size: 32),
    );
  }
}

/// [WidgetFactory] that renders `<img>` through [StableImage] instead of a bare,
/// free-sizing [Image]. Everything else (text, tables, inline CSS) is unchanged.
class MailImageFactory extends WidgetFactory {
  @override
  Widget? buildImage(BuildTree tree, ImageMetadata data) {
    final src = data.sources.isNotEmpty ? data.sources.first : null;
    if (src == null) {
      return null;
    }
    final provider = _providerFor(src.url);
    if (provider == null) {
      // Unknown scheme (e.g. an un-inlined cid:) — defer to the default path.
      return super.buildImage(tree, data);
    }
    final image = src.image;
    return StableImage(
      provider: provider,
      // fwfh exposes the `<img>` width/height attributes here when present.
      attrWidth: src.width,
      attrHeight: src.height,
      semanticLabel: image?.alt ?? image?.title,
    );
  }

  ImageProvider? _providerFor(String url) {
    if (url.startsWith('asset:')) {
      return imageProviderFromAsset(url);
    }
    if (url.startsWith('data:image/')) {
      return imageProviderFromDataUri(url);
    }
    if (url.startsWith('file:')) {
      return imageProviderFromFileUri(url);
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return imageProviderFromNetwork(url);
    }
    return null;
  }
}

/// An image whose laid-out size is independent of when its bytes resolve, so it
/// never relayouts the subtree under the pointer (R0001 / NR0003).
class StableImage extends StatefulWidget {
  const StableImage({
    super.key,
    required this.provider,
    this.attrWidth,
    this.attrHeight,
    this.semanticLabel,
  });

  final ImageProvider provider;

  /// `<img width>` / `<img height>` in logical pixels, when the markup supplies
  /// them. When both are present and positive the box is fixed from frame one.
  final double? attrWidth;
  final double? attrHeight;
  final String? semanticLabel;

  @override
  State<StableImage> createState() => _StableImageState();
}

class _StableImageState extends State<StableImage> {
  /// The size the box reserves: the `<img>` attributes if given, otherwise the
  /// natural size measured from the stream. `null` until known.
  Size? _natural;
  bool _failed = false;

  ImageStream? _stream;
  ImageStreamListener? _listener;

  bool get _hasAttrSize =>
      (widget.attrWidth ?? 0) > 0 && (widget.attrHeight ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    if (_hasAttrSize) {
      // Deterministic from the first frame — no measurement, no relayout.
      _natural = Size(widget.attrWidth!, widget.attrHeight!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_natural == null && !_failed) {
      _resolveStream();
    }
  }

  @override
  void didUpdateWidget(StableImage old) {
    super.didUpdateWidget(old);
    if (old.provider != widget.provider) {
      _detachStream();
      _natural = _hasAttrSize
          ? Size(widget.attrWidth!, widget.attrHeight!)
          : null;
      _failed = false;
      if (_natural == null) {
        _resolveStream();
      }
    }
  }

  void _resolveStream() {
    final config = createLocalImageConfiguration(context);
    final stream = widget.provider.resolve(config);
    if (stream.key == _stream?.key) {
      return;
    }
    _detachStream();
    final listener = ImageStreamListener(_onImage, onError: _onError);
    _listener = listener;
    _stream = stream;
    stream.addListener(listener);
  }

  void _detachStream() {
    final listener = _listener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }
    _listener = null;
    _stream = null;
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    // We only needed the dimensions; the display Image keeps its own handle.
    info.dispose();
    // Apply the one size transition off-band. A cached image resolves
    // synchronously (synchronousCall == true) while we are still inside build /
    // layout / hit-test; calling setState there would relayout the subtree
    // synchronously and, if the pointer is over it, re-enter the mouse
    // device-update phase (mouse_tracker.dart:199). Deferring to a post-frame
    // callback guarantees the settle lands on a normal frame instead.
    _applySizeSafely(() => _natural = size);
  }

  void _onError(Object error, StackTrace? stack) {
    _applySizeSafely(() => _failed = true);
  }

  /// Runs [mutate] + setState outside the current build/layout/pointer phase.
  void _applySizeSafely(VoidCallback mutate) {
    void apply() {
      if (!mounted) return;
      setState(mutate);
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      apply();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    }
  }

  @override
  void dispose() {
    _detachStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed && _natural == null) {
      // Couldn't size it — a small, fixed fallback that itself never relayouts.
      return const SizedBox(
        height: 32,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.broken_image_outlined, size: 32),
        ),
      );
    }

    final natural = _natural;
    if (natural == null) {
      // Measuring: reserve nothing rather than guess. The one transition to the
      // sized box below happens on a normal frame via setState, not during the
      // pointer device-update phase, so it does not trip the re-entrancy assert.
      return const SizedBox.shrink();
    }
    if (natural.width <= 0 || natural.height <= 0) {
      return const SizedBox.shrink();
    }

    final image = Image(
      image: widget.provider,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      semanticLabel: widget.semanticLabel,
      excludeFromSemantics: widget.semanticLabel == null,
      errorBuilder: (context, error, stack) => const Align(
        alignment: Alignment.centerLeft,
        child: Icon(Icons.broken_image_outlined, size: 32),
      ),
    );

    // A tight box derived purely from constraints + the (cached) natural aspect:
    // width = min(available, natural width), height = width / aspect. [AspectRatio]
    // sizes from constraints, never from the child, so resolving the image stream
    // can't relayout it — and unlike [LayoutBuilder] it is dry-layout safe (fwfh
    // wraps images in a CssSizing box that measures children via dry layout).
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: natural.width),
        child: AspectRatio(
          aspectRatio: natural.width / natural.height,
          child: image,
        ),
      ),
    );
  }
}
