import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// Apple-style motion and materials, from the WWDC "Designing Fluid
/// Interfaces" ideas: springs (not fixed-duration curves), motion that keeps
/// the finger's velocity, momentum projection, rubber-banding, and feedback on
/// touch-down. Everything here is interruptible: animations start from the
/// live on-screen value.

/// A spring described like Apple does: damping ratio (1 = no bounce) and
/// response in seconds (lower = snappier).
SpringDescription appleSpring({double damping = 1, double response = 0.4}) {
  final stiffness = _sq(2 * 3.141592653589793 / response);
  return SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: stiffness,
    ratio: damping,
  );
}

double _sq(double x) => x * x;

/// Where a flick that lets go at [velocity] (px/s) would come to rest, using
/// scroll-style exponential deceleration.
double projectMomentum(double velocity, {double decelerationRate = 0.998}) =>
    (velocity / 1000) * decelerationRate / (1 - decelerationRate);

/// Resistance past an edge: the further you pull, the less it follows.
double rubberBand(double overshoot, double dimension, {double c = 0.55}) =>
    (overshoot * dimension * c) / (dimension + c * overshoot.abs());

/// A quiet tick for a meaningful moment (a snap, a switch), never for chatter.
void tick() => HapticFeedback.selectionClick();

/// iOS-style scrolling everywhere: content bounces at its ends.
class AppleScrollBehavior extends MaterialScrollBehavior {
  const AppleScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
  };
}

/// Responds on touch-DOWN (not on release): the child shrinks a little while a
/// finger is on it, springing back the moment it lifts. It only watches raw
/// touches, so taps and swipes underneath work as before.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  int _pointers = 0;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _pointers++;
        _set(true);
      },
      onPointerUp: (_) {
        _pointers = (_pointers - 1).clamp(0, 99);
        if (_pointers == 0) _set(false);
      },
      onPointerCancel: (_) {
        _pointers = (_pointers - 1).clamp(0, 99);
        if (_pointers == 0) _set(false);
      },
      child: AnimatedScale(
        scale: _down && !still ? widget.scale : 1,
        // quick in, springy out
        duration: Duration(milliseconds: _down ? 90 : 320),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

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
          final sigma = (1 - q) * 8;
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
          out = Transform.scale(scale: 0.88 + 0.12 * p, child: out);
        }
        return Opacity(opacity: q, child: out);
      },
      child: widget.child,
    );
  }
}

/// A glass-like surface: translucent, with a lit top edge, a hairline border
/// and a soft shadow. Bigger surfaces read as thicker (more blur and shadow).
/// With "increase contrast" on, it turns into a solid, clearly outlined card.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.blur = 0,
    this.tint = const Color(0xFF1C1C1E),
    this.opacity = 0.78,
  });

  final Widget child;
  final double radius;

  /// Background blur. Only worth paying for where there is something behind.
  final double blur;
  final Color tint;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final solid = MediaQuery.highContrastOf(context);
    final r = BorderRadius.circular(radius);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        color: solid ? tint : tint.withValues(alpha: opacity),
        gradient: solid
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0, 0.5],
              ),
        border: Border.all(
          color: Colors.white.withValues(alpha: solid ? 0.45 : 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18 + radius,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: r, child: child),
    );
    if (blur > 0 && !solid) {
      body = ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: body,
        ),
      );
    }
    return body;
  }
}

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
