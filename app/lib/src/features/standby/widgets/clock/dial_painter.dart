import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The analog dial, used by the Clock card and the Summary clock tiles: a soft
/// glass disc, fine minute ticks, bold hour ticks, the numbers 12, 3, 6 and 9,
/// two thick hands that lift off the disc with a soft shadow, and (when the
/// time has seconds) a thin second hand with a short tail over a little cap.
class DialPainter extends CustomPainter {
  const DialPainter(
    this.time, {
    required this.hourInk,
    required this.minuteInk,
    required this.markInk,
    required this.accentInk,
    required this.numeralInk,
    this.tint,
    this.showSeconds = false,
    this.numerals = true,
    this.glow = 0,
  });

  final DateTime time;
  final Color hourInk;
  final Color minuteInk;

  /// the hour ticks and the ring
  final Color markInk;

  /// the second hand and the cap
  final Color accentInk;
  final Color numeralInk;

  /// a colour wash for the disc; null = a plain glass disc
  final Color? tint;
  final bool showSeconds;
  final bool numerals;

  /// 0..1: a soft halo behind each hand, in the hand's own colour
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final base = tint ?? Colors.white;
    // the face: lighter in the middle, like a glass disc
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            base.withValues(alpha: tint == null ? 0.12 : 0.30),
            base.withValues(alpha: tint == null ? 0.04 : 0.08),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r - 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = markInk.withValues(alpha: 0.35),
    );
    final showNumbers = numerals && r > 52;
    for (var i = 0; i < 60; i++) {
      final hour = i % 5 == 0;
      if (hour && showNumbers && i % 15 == 0) continue; // the number is there
      final a = i * math.pi / 30 - math.pi / 2;
      final outer = r * 0.93;
      final inner = outer - r * (hour ? 0.085 : 0.04);
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * inner,
        c + Offset(math.cos(a), math.sin(a)) * outer,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = hour ? r * 0.028 : r * 0.014
          ..color = (hour ? markInk : Colors.white).withValues(
            alpha: hour ? 0.85 : 0.30,
          ),
      );
    }
    if (showNumbers) {
      for (final n in const [12, 3, 6, 9]) {
        final a = n * math.pi / 6 - math.pi / 2;
        final tp = TextPainter(
          text: TextSpan(
            text: '$n',
            style: TextStyle(
              color: numeralInk.withValues(alpha: 0.9),
              fontSize: r * 0.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          c +
              Offset(math.cos(a), math.sin(a)) * r * 0.70 -
              Offset(tp.width / 2, tp.height / 2),
        );
      }
    }

    void hand(
      double angle,
      double length,
      double width,
      Color color, {
      double tail = 0,
    }) {
      final dir = Offset(math.cos(angle), math.sin(angle));
      final tip = c + dir * length;
      final back = c - dir * tail;
      if (glow > 0.01) {
        canvas.drawLine(
          back,
          tip,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = width + 8 * glow
            ..color = color.withValues(alpha: glow)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 9 * glow),
        );
      }
      // a soft shadow first, so the hand lifts off the disc
      canvas.drawLine(
        back + const Offset(0, 1.5),
        tip + const Offset(0, 1.5),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.6),
      );
      canvas.drawLine(
        back,
        tip,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = color,
      );
    }

    final minute = time.minute + time.second / 60;
    final hour = time.hour % 12 + minute / 60;
    hand(hour * math.pi / 6 - math.pi / 2, r * 0.46, r * 0.075, hourInk);
    hand(minute * math.pi / 30 - math.pi / 2, r * 0.72, r * 0.05, minuteInk);
    if (showSeconds) {
      hand(
        time.second * math.pi / 30 - math.pi / 2,
        r * 0.82,
        math.max(1.6, r * 0.016),
        accentInk,
        tail: r * 0.18,
      );
    }
    canvas.drawCircle(
      c,
      r * (showSeconds ? 0.05 : 0.065),
      Paint()..color = accentInk,
    );
    canvas.drawCircle(c, r * 0.022, Paint()..color = Colors.black87);
  }

  @override
  bool shouldRepaint(DialPainter old) =>
      old.time.minute != time.minute ||
      old.time.hour != time.hour ||
      (showSeconds && old.time.second != time.second) ||
      old.hourInk != hourInk ||
      old.minuteInk != minuteInk ||
      old.markInk != markInk ||
      old.accentInk != accentInk ||
      old.numeralInk != numeralInk ||
      old.tint != tint ||
      old.showSeconds != showSeconds ||
      old.numerals != numerals ||
      old.glow != glow;
}
