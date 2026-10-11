import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'motion.dart';

/// Something arriving as a material: it scales up, un-blurs and fades in on a
/// spring (and the reverse on the way out), instead of a plain fade.
class Materialize extends StatefulWidget {
  const Materialize({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<Materialize> createState() => _MaterializeState();
}

class _MaterializeState extends State<Materialize>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.visible ? 1 : 0,
  );

  @override
  void didUpdateWidget(Materialize old) {
    super.didUpdateWidget(old);
    if (old.visible == widget.visible) return;
    final target = widget.visible ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = target;
      return;
    }
    // from wherever it is right now, carrying its current velocity
    _c.animateWith(
      SpringSimulation(
        appleSpring(response: 0.35),
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
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final p = _c.value;
        final q = p.clamp(0.0, 1.0);
        if (q <= 0.001 && !widget.visible) return const SizedBox.shrink();
        Widget out = child!;
        if (!still) {
          final sigma = (1 - q) * 6;
          if (sigma > 0.2) {
            out = ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.decal,
              ),
              child: out,
            );
          }
          out = Transform.scale(scale: 0.92 + 0.08 * p, child: out);
        }
        return Opacity(opacity: q, child: out);
      },
      child: widget.child,
    );
  }
}
