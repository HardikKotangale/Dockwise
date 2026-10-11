import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/apple.dart';
import '../../../../domain/standby_models.dart';
import 'clock_text.dart';

class FlipClockFace extends StatelessWidget {
  const FlipClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.onPartTap,
    this.stacked = false,
  });

  final DateTime time;
  final StandbySettings settings;
  final PartTap? onPartTap;

  /// hour tiles over minute tiles (a tall panel) instead of on one line
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    // a third tile for seconds when "Show seconds" is on
    final t = clockText(time, settings, seconds: settings.secondsVisible);
    final parts = t.text.split(':');
    // stacked in 12-hour time: two digits for the hour ("09", not "9")
    if (stacked && !settings.use24HourTime) parts[0] = parts[0].padLeft(2, '0');
    final colon = TextStyle(
      color: settings.colonInk,
      shadows: glowShadows(settings.colonInk, settings.glowIntensity),
      fontSize: 86,
      fontWeight: FontWeight.w900,
    );
    // one card per digit: the ones flip every tick, the tens only when they change
    Widget digits(String v, ClockPart role) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < v.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          FlipCard(
            key: ValueKey('${role.name}$i'),
            value: v[i],
            settings: settings,
            role: role,
          ),
        ],
      ],
    );
    Widget colonDots() => tapPart(
      onPartTap,
      ClockPart.colon,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(':', style: colon),
      ),
    );
    return MorphLayout(
      stacked: stacked,
      stackGap: 16,
      suffixGap: 14,
      hours: tapPart(
        onPartTap,
        ClockPart.hours,
        digits(parts[0], ClockPart.hours),
      ),
      separator: colonDots(),
      minutes: tapPart(
        onPartTap,
        ClockPart.minutes,
        digits(parts[1], ClockPart.minutes),
      ),
      // seconds (when shown): on a line, or a smaller row under the minutes
      trailing: parts.length > 2
          ? TweenAnimationBuilder<double>(
              tween: Tween(end: stacked ? 0.55 : 1.0),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: easeOutStrong,
              builder: (context, k, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!stacked) colonDots(),
                  SizedBox(
                    width:
                        88 * parts[2].length * k +
                        6 * (parts[2].length - 1) * k,
                    height: 174 * k,
                    child: FittedBox(
                      child: tapPart(
                        onPartTap,
                        ClockPart.detail,
                        digits(parts[2], ClockPart.detail),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
      // AM/PM is a small flip card of its own, hanging off the end of the last
      // line at its bottom edge; it flips when the day turns over
      suffix: t.suffix == null
          ? null
          : tapPart(
              onPartTap,
              ClockPart.detail,
              FlipCard(
                key: const ValueKey('suffix'),
                value: t.suffix!,
                settings: settings,
                role: ClockPart.detail,
                width: 74,
                height: 78,
                fontSize: 34,
                radius: 14,
              ),
            ),
    );
  }
}

/// One flip card (a digit, or AM/PM at a smaller size). When its value
/// changes it flips like a real one: the old top half falls forward and
/// darkens as it goes, then the new bottom half drops into place with a tiny
/// settle. A hinge sits at the seam, and each flap is shaded by how far it has
/// turned, so it reads as a solid card with depth.
/// One flip card (also used by the timer).
class FlipCard extends StatefulWidget {
  const FlipCard({
    super.key,
    required this.value,
    required this.settings,
    required this.role, // hours, minutes or detail
    this.width = 88,
    this.height = 174,
    this.fontSize = 92,
    this.radius = 18,
  });

  final String value;
  final StandbySettings settings;
  final ClockPart role;
  final double width;
  final double height;
  final double fontSize;
  final double radius;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 720),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _previous = null);
        }
      });
  String? _previous; // the value being flipped away from

  // the top falls (speeding up, like gravity); the bottom drops and settles
  static const _topCurve = Curves.easeInCubic;
  static const _bottomCurve = Cubic(0.25, 1.0, 0.4, 1.12);
  static const _split = 0.42; // when the top flap is edge-on

  @override
  void didUpdateWidget(FlipCard old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value) return;
    if (MediaQuery.disableAnimationsOf(context)) return; // respect the setting
    _previous = old.value;
    _flip.forward(from: 0);
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  // The full card showing [value]: the face, the digits, the seam and hinge.
  Widget _face(String value) {
    final theme = widget.settings.theme;
    // Color-block themes invert: ink card, panel-colored digits.
    final onPanel = theme.panelColor != null;
    final base = onPanel ? theme.clockColor : const Color(0xFF111116);
    final ink = onPanel
        ? theme.panelColor!
        : switch (widget.role) {
            ClockPart.minutes => widget.settings.minutesInk,
            ClockPart.detail => widget.settings.detailInk,
            _ => widget.settings.hoursInk,
          };
    Color shade(Color c, double k) =>
        Color.lerp(c, k > 0 ? Colors.white : Colors.black, k.abs())!;
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        // a faint light from above: the top a touch lighter than the bottom
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [shade(base, 0.07), base, shade(base, -0.12)],
          stops: const [0, 0.5, 1],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: ink,
              shadows: glowShadows(ink, widget.settings.glowIntensity),
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          // the seam: a dark gap with a light edge under it
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Container(
                height: math.max(1.5, widget.height / 90),
                decoration: BoxDecoration(
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.10),
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // the hinge pins at each end of the seam
          for (final left in [true, false])
            Positioned(
              left: left ? 0 : null,
              right: left ? null : 0,
              top: widget.height / 2 - widget.height / 40,
              child: Container(
                width: widget.width / 18,
                height: widget.height / 20,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.horizontal(
                    left: left ? Radius.zero : const Radius.circular(2),
                    right: left ? const Radius.circular(2) : Radius.zero,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Top or bottom half of the card for [value], darkened by [dark] (0..1).
  Widget _half(String value, {required bool top, double dark = 0}) {
    final half = SizedBox(
      width: widget.width,
      height: widget.height / 2,
      // the whole face at its full size, of which only this half shows (an
      // Align alone would squeeze the face into the half's height)
      child: ClipRect(
        child: OverflowBox(
          alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
          minWidth: widget.width,
          maxWidth: widget.width,
          minHeight: widget.height,
          maxHeight: widget.height,
          child: _face(value),
        ),
      ),
    );
    if (dark <= 0.01) return half;
    return Stack(
      children: [
        half,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: dark.clamp(0.0, 1.0)),
                borderRadius: BorderRadius.vertical(
                  top: top ? Radius.circular(widget.radius) : Radius.zero,
                  bottom: top ? Radius.zero : Radius.circular(widget.radius),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Matrix4 _tilt(double angle) => Matrix4.identity()
    ..setEntry(3, 2, 0.0034) // perspective
    ..rotateX(angle);

  @override
  Widget build(BuildContext context) {
    final old = _previous;
    if (old == null) return _face(widget.value);
    final half = widget.height / 2;
    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final t = _flip.value;
        final p = (t / _split).clamp(0.0, 1.0); // the top flap, 0..1
        final q = ((t - _split) / (1 - _split)).clamp(0.0, 1.0); // the bottom
        final fall = _topCurve.transform(p);
        final drop = _bottomCurve.transform(q);
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // behind: the new top half (shadowed while the old flap is over
              // it) and the old bottom half (shadowed as the new one lands)
              Positioned(
                top: 0,
                left: 0,
                child: _half(
                  widget.value,
                  top: true,
                  dark: p < 1 ? 0.45 * (1 - fall) : 0,
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                child: _half(old, top: false, dark: q > 0 ? 0.35 * q : 0),
              ),
              if (p < 1)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: _tilt(-math.pi / 2 * fall),
                    child: _half(old, top: true, dark: 0.55 * fall),
                  ),
                )
              else
                Positioned(
                  top: half,
                  left: 0,
                  child: Transform(
                    alignment: Alignment.topCenter,
                    transform: _tilt(math.pi / 2 * (1 - drop)),
                    child: _half(
                      widget.value,
                      top: false,
                      dark: 0.5 * (1 - drop).clamp(0.0, 1.0),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
