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
          _FlipTile(
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
                        _FlipTile.width * parts[2].length * k +
                        6 * (parts[2].length - 1) * k,
                    height: _FlipTile.height * k,
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
      // AM/PM hangs off the end of the last line, at its bottom edge
      suffix: t.suffix == null
          ? null
          : tapPart(
              onPartTap,
              ClockPart.detail,
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  t.suffix!,
                  style: TextStyle(
                    color: settings.detailInk,
                    shadows: glowShadows(
                      settings.detailInk,
                      settings.glowIntensity,
                    ),
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
    );
  }
}

/// One flip-clock tile. When its value changes it flips like a real one: the
/// old top half folds down, then the new bottom half unfolds into place.
class _FlipTile extends StatefulWidget {
  const _FlipTile({
    super.key,
    required this.value,
    required this.settings,
    required this.role, // hours, minutes or detail (= seconds)
  });

  final String value;
  final StandbySettings settings;
  final ClockPart role;

  static const width = 88.0;
  static const height = 174.0;

  @override
  State<_FlipTile> createState() => _FlipTileState();
}

class _FlipTileState extends State<_FlipTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 460),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _previous = null);
        }
      });
  String? _previous; // the value being flipped away from

  @override
  void didUpdateWidget(_FlipTile old) {
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

  // The full tile showing [value]: the card, the digits, the centre seam.
  Widget _card(String value) {
    final theme = widget.settings.theme;
    // Color-block themes invert: ink tile, panel-colored digits.
    final onPanel = theme.panelColor != null;
    final tile = onPanel ? theme.clockColor : const Color(0xFF111116);
    final digits = onPanel
        ? theme.panelColor!
        : switch (widget.role) {
            ClockPart.minutes => widget.settings.minutesInk,
            ClockPart.detail => widget.settings.detailInk,
            _ => widget.settings.hoursInk,
          };
    return Container(
      width: _FlipTile.width,
      height: _FlipTile.height,
      decoration: BoxDecoration(
        color: tile,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              color: digits,
              shadows: glowShadows(digits, widget.settings.glowIntensity),
              fontSize: 92,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Container(height: 1.5, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // Top or bottom half of the tile for [value].
  Widget _half(String value, {required bool top}) => SizedBox(
    width: _FlipTile.width,
    height: _FlipTile.height / 2,
    child: ClipRect(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        heightFactor: 0.5,
        child: _card(value),
      ),
    ),
  );

  Matrix4 _tilt(double angle) => Matrix4.identity()
    ..setEntry(3, 2, 0.004) // a little perspective
    ..rotateX(angle);

  @override
  Widget build(BuildContext context) {
    final old = _previous;
    if (old == null) return _card(widget.value);
    const half = _FlipTile.height / 2;
    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final t = _flip.value;
        final first = t < 0.5; // 1st half: old top folds; 2nd: new bottom opens
        return SizedBox(
          width: _FlipTile.width,
          height: _FlipTile.height,
          child: Stack(
            children: [
              // behind: the new top half and the old bottom half
              Positioned(
                top: 0,
                left: 0,
                child: _half(widget.value, top: true),
              ),
              Positioned(bottom: 0, left: 0, child: _half(old, top: false)),
              if (first)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: _tilt(-math.pi / 2 * (t / 0.5)),
                    child: _half(old, top: true),
                  ),
                )
              else
                Positioned(
                  top: half,
                  left: 0,
                  child: Transform(
                    alignment: Alignment.topCenter,
                    transform: _tilt(math.pi / 2 * (1 - (t - 0.5) / 0.5)),
                    child: _half(widget.value, top: false),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
