import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'motion.dart';

/// Responds on touch-DOWN (not on release): the child shrinks a little at once
/// and springs back, with a tiny overshoot, when the finger lifts. It runs on
/// a spring, so pressing again mid-way carries on from where it is. It only
/// watches raw touches, so taps and swipes underneath work as before.
///
/// [highlight] also lights a soft shape behind the child while it is held.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.scale = 0.96,
    this.highlight = false,
    this.round = false,
  });

  final Widget child;
  final double scale;

  /// a soft glow behind the child while pressed
  final bool highlight;

  /// the glow is a circle instead of a rounded square
  final bool round;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  int _pointers = 0;
  double _glow = 0;

  void _to(double target, {required bool down}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = target;
    } else {
      _c.animateWith(
        SpringSimulation(
          // quick and firm going down, a little bounce coming back
          appleSpring(damping: down ? 1 : 0.62, response: down ? 0.12 : 0.34),
          _c.value,
          target,
          _c.velocity,
        ),
      );
    }
    if (widget.highlight && mounted) setState(() => _glow = down ? 1 : 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _up() {
    _pointers = (_pointers - 1).clamp(0, 99);
    if (_pointers == 0) _to(1, down: false);
  }

  @override
  Widget build(BuildContext context) {
    Widget out = AnimatedBuilder(
      animation: _c,
      builder: (context, child) =>
          Transform.scale(scale: _c.value, child: child),
      child: widget.child,
    );
    if (widget.highlight) {
      out = Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _glow,
                duration: Duration(milliseconds: _glow > 0 ? 80 : 220),
                curve: easeOutStrong,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: widget.round ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: widget.round
                        ? null
                        : BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          out,
        ],
      );
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _pointers++;
        _to(widget.scale, down: true);
      },
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: out,
    );
  }
}
