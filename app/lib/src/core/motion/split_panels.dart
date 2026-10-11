import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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

  @override
  void didUpdateWidget(SplitPanels old) {
    super.didUpdateWidget(old);
    if (old.duo == widget.duo) return;
    final target = widget.duo ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = target;
      return;
    }
    _c.animateWith(
      SpringSimulation(
        appleSpring(damping: 0.9, response: 0.5),
        _c.value,
        target,
        _c.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final first = KeyedSubtree(key: _firstKey, child: widget.first);
    final second = KeyedSubtree(key: _secondKey, child: widget.second);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value.clamp(0.0, 1.0);
        if (!widget.duo && t <= 0.001) return first;
        final gap = widget.gap;
        if (widget.duo && t >= 0.999) {
          final kids = [
            Expanded(child: first),
            SizedBox(width: gap, height: gap),
            Expanded(child: second),
          ];
          return widget.vertical ? Column(children: kids) : Row(children: kids);
        }
        return LayoutBuilder(
          builder: (context, c) {
            final total = widget.vertical ? c.maxHeight : c.maxWidth;
            final half = (total - gap) / 2;
            final firstSize = total + (half - total) * t;
            final secondSize = half * t;
            Widget sized(double size, Widget child) => SizedBox(
              width: widget.vertical ? null : size,
              height: widget.vertical ? size : null,
              child: child,
            );
            final kids = [
              sized(firstSize, first),
              SizedBox(width: gap * t, height: gap * t),
              sized(
                secondSize,
                ClipRect(
                  // full size inside, so it is revealed rather than squashed
                  child: OverflowBox(
                    alignment: widget.vertical
                        ? Alignment.topCenter
                        : Alignment.centerLeft,
                    minWidth: widget.vertical ? null : half,
                    maxWidth: widget.vertical ? null : half,
                    minHeight: widget.vertical ? half : null,
                    maxHeight: widget.vertical ? half : null,
                    child: Opacity(opacity: t, child: second),
                  ),
                ),
              ),
            ];
            return widget.vertical
                ? Column(children: kids)
                : Row(children: kids);
          },
        );
      },
    );
  }
}
