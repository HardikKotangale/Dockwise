import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import 'motion.dart';

/// One panel or two. Going between them is a spring: the second panel grows
/// out of (or folds into) the edge while the first glides over to make room,
/// instead of one popping in or out. Interruptible like everything else here.
class SplitPanels extends StatefulWidget {
  const SplitPanels({
    super.key,
    required this.duo,
    required this.vertical,
    required this.first,
    required this.second,
    this.gap = 12,
  });

  final bool duo;

  /// stacked top to bottom (portrait) instead of side by side
  final bool vertical;
  final Widget first;
  final Widget second;
  final double gap;

  @override
  State<SplitPanels> createState() => _SplitPanelsState();
}

class _SplitPanelsState extends State<SplitPanels>
    with SingleTickerProviderStateMixin {
  // 1 = two panels, 0 = one panel
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.duo ? 1 : 0,
  );
  final _firstKey = GlobalKey();
  final _secondKey = GlobalKey();
  final _firstBoundary = GlobalKey();

  // The first panel is laid out at its final size at once and stays that way
  // while the layout glides; what you see until it lands is a picture of how
  // it was, stretched into the moving place and fading away. A card that was
  // laid out afresh on every frame (and its big text drawn again at every
  // size) is what made the switch stutter.
  ui.Image? _before;

  void _dropPicture() {
    _before?.dispose();
    _before = null;
  }

  @override
  void didUpdateWidget(SplitPanels old) {
    super.didUpdateWidget(old);
    if (old.duo == widget.duo) return;
    final target = widget.duo ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _dropPicture();
      _c.value = target;
      return;
    }
    // the first panel as it is now, before this rebuild changes its size
    _dropPicture();
    final box = _firstBoundary.currentContext?.findRenderObject();
    if (box is RenderRepaintBoundary && box.hasSize && !box.size.isEmpty) {
      try {
        _before = box.toImageSync(
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
      } catch (_) {
        _before = null;
      }
    }
    _c
        .animateWith(
          SpringSimulation(
            appleSpring(damping: 0.9, response: 0.5),
            _c.value,
            target,
            _c.velocity,
          ),
        )
        .whenComplete(() {
          if (!mounted || _c.isAnimating) return;
          setState(_dropPicture);
        });
  }

  @override
  void dispose() {
    _c.dispose();
    _before?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final first = KeyedSubtree(
      key: _firstKey,
      child: RepaintBoundary(key: _firstBoundary, child: widget.first),
    );
    final second = KeyedSubtree(key: _secondKey, child: widget.second);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value.clamp(0.0, 1.0);
        final gap = widget.gap;
        final showSecond = widget.duo || t > 0.001;
        return LayoutBuilder(
          builder: (context, c) {
            final vertical = widget.vertical;
            final total = vertical ? c.maxHeight : c.maxWidth;
            final cross = vertical ? c.maxWidth : c.maxHeight;
            final half = (total - gap) / 2;
            // where the split is right now (for the second panel and the
            // picture), and where the first panel will stay
            final firstNow = total + (half - total) * t;
            final firstFinal = widget.duo ? half : total;
            final secondNow = half * t;
            // how far the glide is towards where it is going (0 to 1)
            final done = (widget.duo ? t : 1 - t).clamp(0.0, 1.0);

            Widget place({
              required double at,
              required double along,
              required Widget child,
            }) => Positioned(
              left: vertical ? 0 : at,
              top: vertical ? at : 0,
              width: vertical ? cross : along,
              height: vertical ? along : cross,
              child: child,
            );

            final before = _before;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // the first panel, at its final size, brought in as the
                // picture of how it was fades away
                place(
                  at: 0,
                  along: firstFinal,
                  child: before == null
                      ? first
                      : Opacity(opacity: done, child: first),
                ),
                if (before != null)
                  place(
                    at: 0,
                    along: firstNow,
                    child: IgnorePointer(
                      child: RawImage(
                        image: before,
                        fit: BoxFit.fill,
                        opacity: AlwaysStoppedAnimation(1 - done),
                      ),
                    ),
                  ),
                if (showSecond)
                  place(
                    at: firstNow + gap * t,
                    along: secondNow,
                    child: ClipRect(
                      // full size inside, so it is revealed rather than
                      // squashed
                      child: OverflowBox(
                        alignment: vertical
                            ? Alignment.topCenter
                            : Alignment.centerLeft,
                        minWidth: vertical ? null : half,
                        maxWidth: vertical ? null : half,
                        minHeight: vertical ? half : null,
                        maxHeight: vertical ? half : null,
                        child: Opacity(opacity: t, child: second),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
