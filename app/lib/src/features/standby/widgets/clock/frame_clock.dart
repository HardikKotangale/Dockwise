import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/motion/motion.dart';
import '../../../../domain/standby_models.dart';
import 'clock_text.dart';

/// The iOS StandBy "digital with seconds" look: a big, heavy, condensed time
/// in a square, with 60 short ticks around the border. The tick for the current
/// second is the brightest; the ones behind it fade away like a comet's tail.
class FrameClockFace extends StatelessWidget {
  const FrameClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.onPartTap,
    this.snug = false,
  });

  final DateTime time;
  final StandbySettings settings;
  final PartTap? onPartTap;

  /// a small tile: ticks hug the edge, so the time gets more of the room
  final bool snug;

  // Used when the face is given no size (e.g. a tiny preview): a square.
  static const _fallback = 300.0;

  @override
  Widget build(BuildContext context) {
    final t = clockText(time, settings);
    // Apple shows 8:13, not 08:13
    final text = t.text.replaceFirst(RegExp(r'^0(?=\d)'), '');
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.hasBoundedWidth ? c.maxWidth : _fallback;
        final h = c.hasBoundedHeight ? c.maxHeight : _fallback;
        final box = Size(w, h);
        // ticks, corners and margins grow with the panel's shorter side
        final unit = (math.min(w, h) / 300).clamp(0.2, 4.0);
        final tick = frameTickSize(settings.tickScale);
        final margin = tick.length * unit + (snug ? 14 : 34) * unit;
        // a wide panel (landscape, one panel) puts AM/PM on the right
        final ratio = (w - 2 * margin) / (h - 2 * margin);
        final wide = ratio > 1.25;
        // a tall panel (portrait, one panel) stacks hours over minutes, so the
        // digits can grow to fill the height instead of floating in empty space
        final tall = ratio < 0.7;
        final timeText = TimeText(
          text: text,
          settings: settings,
          onPartTap: onPartTap,
          solidColon: true,
          style: const TextStyle(
            fontFamily: 'BebasNeue',
            fontSize: 225,
            // a tight line box: digits have no descenders, so the usual spare
            // space above and below would only make them smaller
            height: 0.8,
          ),
        );
        Widget suffixText(double size) => tapPart(
          onPartTap,
          ClockPart.detail,
          Text(
            t.suffix!,
            style: TextStyle(
              fontFamily: 'BebasNeue',
              color: settings.detailInk,
              shadows: glowShadows(settings.detailInk, settings.glowIntensity),
              fontSize: size,
            ),
          ),
        );
        final parts = text.split(':');
        Widget stacked(String digits, Color ink, ClockPart part) => tapPart(
          onPartTap,
          part,
          Text(
            digits,
            style: TextStyle(
              fontFamily: 'BebasNeue',
              fontSize: 225,
              height: 0.8,
              color: ink,
              shadows: glowShadows(ink, settings.glowIntensity),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // only the tick border reacts to taps (see _FramePainter.hitTest),
              // not the empty middle of the frame
              GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onTap: onPartTap == null
                    ? null
                    : () => onPartTap!(ClockPart.label),
                child: CustomPaint(
                  size: box,
                  painter: _FramePainter(
                    second: time.second,
                    ink: settings.ticksInk,
                    scale: settings.tickScale,
                    box: box,
                    unit: unit,
                  ),
                ),
              ),
              // the time is scaled up or down to fill the space inside the
              // ticks, however wide the panel or the time (e.g. 10:09 PM)
              // a fixed inner size, so the time is scaled UP to fill it as well as
              // down to fit it
              SizedBox(
                width: math.max(1, w - 2 * margin),
                height: math.max(1, h - 2 * margin),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: AnimatedSwitcher(
                    // hours over minutes <-> one line: the digits fade and
                    // settle into the new arrangement
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : Motion.slow,
                    switchInCurve: easeOutStrong,
                    child: KeyedSubtree(
                      key: ValueKey(
                        '${tall && parts.length == 2}-${wide && t.suffix != null}',
                      ),
                      child: tall && parts.length == 2
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                stacked(
                                  parts[0],
                                  settings.hoursInk,
                                  ClockPart.hours,
                                ),
                                const SizedBox(height: 10),
                                stacked(
                                  parts[1],
                                  settings.minutesInk,
                                  ClockPart.minutes,
                                ),
                                if (t.suffix != null) ...[
                                  const SizedBox(height: 14),
                                  suffixText(50),
                                ],
                              ],
                            )
                          : wide && t.suffix != null
                          // wide panel: AM/PM beside the digits, so the digits can
                          // use the full height instead of leaving the sides empty
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                timeText,
                                const SizedBox(width: 14),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: suffixText(76),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                timeText,
                                if (t.suffix != null) suffixText(50),
                              ],
                            ),
                    ),
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

/// Length and thickness of a Frame tick at [scale] (1 = default). The default
/// is deliberately small: fine lines like Apple's, not chunky bars.
({double length, double width}) frameTickSize(double scale) {
  final k = scale.clamp(0.5, 1.6);
  return (length: 14 * k, width: 3.2 * k);
}

/// Brightness (0..1) of border tick [i] when it is [second] o'clock-seconds:
/// full at the current second, fading the further behind it a tick is, and
/// darkest just ahead of it (the comet tail of the Frame clock).
double frameTickBrightness(int i, int second) {
  final age = (second - i) % 60; // 0 = now, 59 = about to light up
  final left = (60 - age) / 60;
  return 0.1 + 0.9 * left * left;
}

class _FramePainter extends CustomPainter {
  const _FramePainter({
    required this.second,
    required this.ink,
    required this.scale,
    required this.box,
    required this.unit,
  });

  final int second; // 0..59: the brightest tick
  final Color ink;
  final double scale; // tick size multiplier
  final Size box; // the panel the frame fills
  final double unit; // 1 at 300 px: ticks, corners and margins grow with it

  // Rounded square, drawn clockwise from the top centre.
  static Path _border(Rect r, double radius) {
    final c = r.center.dx;
    return Path()
      ..moveTo(c, r.top)
      ..lineTo(r.right - radius, r.top)
      ..arcToPoint(
        Offset(r.right, r.top + radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(r.right, r.bottom - radius)
      ..arcToPoint(
        Offset(r.right - radius, r.bottom),
        radius: Radius.circular(radius),
      )
      ..lineTo(r.left + radius, r.bottom)
      ..arcToPoint(
        Offset(r.left, r.bottom - radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(r.left, r.top + radius)
      ..arcToPoint(
        Offset(r.left + radius, r.top),
        radius: Radius.circular(radius),
      )
      ..lineTo(c, r.top);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(6 * unit);
    final metric = _border(
      rect,
      math.min(size.width, size.height) * 0.16,
    ).computeMetrics().first;
    final tick = frameTickSize(scale);
    final length = tick.length * unit;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = tick.width * unit;
    for (var i = 0; i < 60; i++) {
      final t = metric.getTangentForOffset(metric.length * i / 60)!;
      final inward = Offset(-t.vector.dy, t.vector.dx); // clockwise path
      paint.color = ink.withValues(alpha: frameTickBrightness(i, second));
      canvas.drawLine(t.position, t.position + inward * length, paint);
    }
  }

  // Tappable only on the tick strip, not the interior.
  @override
  bool? hitTest(Offset position) {
    final outer = Offset.zero & box;
    final strip = (frameTickSize(scale).length + 18) * unit;
    return outer.contains(position) && !outer.deflate(strip).contains(position);
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.second != second ||
      old.ink != ink ||
      old.scale != scale ||
      old.box != box;
}
