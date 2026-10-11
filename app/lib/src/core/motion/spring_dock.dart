import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'motion.dart';

/// The settings panel: it takes its space with a spring (the dashboard glides
/// aside as it opens), follows a finger that drags its header, and a flick
/// sends it where the flick was heading. It leaves the way it came in. It can
/// be grabbed again at any moment, including mid-flight.
class SpringDock extends StatefulWidget {
  const SpringDock({
    super.key,
    required this.axis,
    required this.extent,
    required this.onClosed,
    required this.builder,
  });

  /// horizontal: slides in from the right; vertical: up from the bottom
  final Axis axis;

  /// the panel's full width (horizontal) or height (vertical)
  final double extent;

  /// called once it has finished leaving
  final VoidCallback onClosed;

  /// [dismiss] closes it with the animation; [dragStart]/[dragUpdate]/
  /// [dragEnd] are for whatever the user grabs to move it (its header)
  final Widget Function(BuildContext context, SpringDockHandle handle) builder;

  @override
  State<SpringDock> createState() => SpringDockState();
}

/// What a [SpringDock]'s content can ask of it.
class SpringDockHandle {
  const SpringDockHandle({
    required this.dismiss,
    required this.dragUpdate,
    required this.dragEnd,
  });

  final VoidCallback dismiss;
  final void Function(double delta) dragUpdate;
  final void Function(double velocity) dragEnd;
}

class SpringDockState extends State<SpringDock>
    with SingleTickerProviderStateMixin {
  // how far the panel is from fully open, in px along the axis (0 = open)
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.extent,
  );
  bool _closing = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 0;
    } else {
      _spring(0, 0, damping: 1, response: 0.42);
    }
  }

  void _spring(
    double target,
    double velocity, {
    double damping = 1,
    double response = 0.4,
  }) {
    // always from the live value, never from where the last animation was going
    _c.animateWith(
      SpringSimulation(
        appleSpring(damping: damping, response: response),
        _c.value,
        target,
        velocity,
      ),
    );
  }

  void dismiss() {
    if (_closing) return;
    _closing = true;
    tick();
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onClosed();
      return;
    }
    _spring(widget.extent, _c.velocity, response: 0.38);
    _watchClosed();
  }

  AnimationStatusListener? _onStatus;

  void _watchClosed() {
    _unwatch();
    _onStatus = (status) {
      if (status == AnimationStatus.completed &&
          _c.value >= widget.extent - 0.5) {
        _unwatch();
        if (mounted && _closing) widget.onClosed();
      }
    };
    _c.addStatusListener(_onStatus!);
  }

  void _unwatch() {
    final cb = _onStatus;
    if (cb != null) _c.removeStatusListener(cb);
    _onStatus = null;
  }

  void _dragUpdate(double delta) {
    // grabbing it while it is leaving brings it back under the finger
    if (_closing) {
      _closing = false;
      _unwatch();
    }
    _c.stop();
    var next = _c.value + delta;
    // past fully open there is a soft wall instead of a hard stop
    if (next < 0) {
      next = -rubberBand(-next, widget.extent);
    } else if (_c.value < 0) {
      next = _c.value + delta; // coming back from the rubber band
    }
    _c.value = next;
  }

  void _dragEnd(double velocity) {
    if (_closing) return;
    // where the flick is heading decides, not where the finger let go
    final heading = _c.value + projectMomentum(velocity);
    if (heading > widget.extent / 2) {
      _closing = true;
      tick();
      _spring(
        widget.extent,
        velocity,
        damping: velocity.abs() > 500 ? 0.9 : 1,
        response: 0.38,
      );
      _watchClosed();
    } else {
      // a bounce only because a flick came first
      _spring(0, velocity, damping: velocity.abs() > 500 ? 0.8 : 1);
    }
  }

  @override
  void dispose() {
    _unwatch();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final handle = SpringDockHandle(
      dismiss: dismiss,
      dragUpdate: _dragUpdate,
      dragEnd: _dragEnd,
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final shown = (1 - _c.value / widget.extent).clamp(0.0, 1.0);
        // the slot grows and shrinks with the panel; the panel stays at full
        // size inside it, anchored to the near edge, so it slides rather than
        // squashes. Past fully open (rubber band) it just shifts.
        final stretch = _c.value < 0 ? -_c.value : 0.0;
        Widget panel = OverflowBox(
          alignment: horizontal ? Alignment.centerLeft : Alignment.topCenter,
          minWidth: horizontal ? widget.extent : null,
          maxWidth: horizontal ? widget.extent : null,
          minHeight: horizontal ? null : widget.extent,
          maxHeight: horizontal ? null : widget.extent,
          child: Transform.translate(
            offset: horizontal ? Offset(-stretch, 0) : Offset(0, -stretch),
            child: builderChild(context, handle),
          ),
        );
        panel = ClipRect(child: panel);
        return SizedBox(
          width: horizontal ? widget.extent * shown : null,
          height: horizontal ? null : widget.extent * shown,
          child: panel,
        );
      },
    );
  }

  Widget builderChild(BuildContext context, SpringDockHandle h) =>
      widget.builder(context, h);
}
