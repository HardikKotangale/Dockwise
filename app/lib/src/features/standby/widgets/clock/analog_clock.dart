import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/palette.dart';
import '../../../../domain/standby_models.dart';

class AnalogClockFace extends StatelessWidget {
  const AnalogClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.numerals = true,
  });

  final DateTime time;
  final StandbySettings settings;

  /// the twelve numbers; off for small dials where they would be unreadable
  final bool numerals;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AnalogClockPainter(time, settings, numerals: numerals),
        child: const SizedBox.square(dimension: 310),
      ),
    );
  }
}

class _AnalogClockPainter extends CustomPainter {
  _AnalogClockPainter(this.time, this.settings, {this.numerals = true});

  final DateTime time;
  final StandbySettings settings;
  final bool numerals;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final theme = settings.theme;
    // each part: a picked color, else the theme default
    final marks = settings.colonColor == 0
        ? theme.clockColor.withValues(alpha: 0.62)
        : Color(settings.colonColor);
    final hourInk = settings.hoursColor == 0
        ? theme.clockAccent
        : Color(settings.hoursColor);
    final minuteInk = settings.minutesColor == 0
        ? theme.clockColor
        : Color(settings.minutesColor);
    final secondInk = settings.detailColor == 0
        ? Palette.orange
        : Color(settings.detailColor);
    final tickPaint = Paint()
      ..color = marks
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 60; i++) {
      final angle = (i / 60) * math.pi * 2;
      final inner = radius - (i % 5 == 0 ? 20 : 12);
      final outer = radius - 4;
      canvas.drawLine(
        center + Offset(math.sin(angle) * inner, -math.cos(angle) * inner),
        center + Offset(math.sin(angle) * outer, -math.cos(angle) * outer),
        tickPaint..strokeWidth = i % 5 == 0 ? 4 : 1.4,
      );
    }

    // all twelve numerals, just inside the ticks
    final numeralInk = settings.colonColor == 0
        ? theme.clockColor
        : Color(settings.colonColor);
    for (var n = 1; n <= (numerals ? 12 : 0); n++) {
      final angle = (n / 12) * math.pi * 2;
      final tp = TextPainter(
        text: TextSpan(
          text: '$n',
          style: TextStyle(
            color: numeralInk,
            fontSize: radius * 0.17,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final at =
          center + Offset(math.sin(angle), -math.cos(angle)) * (radius * 0.74);
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    final hour = (time.hour % 12 + time.minute / 60) / 12;
    final minute = (time.minute + time.second / 60) / 60;
    _hand(
      canvas,
      center,
      radius * 0.42,
      hour,
      Paint()
        ..color = hourInk
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    _hand(
      canvas,
      center,
      radius * 0.68,
      minute,
      Paint()
        ..color = minuteInk
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    if (settings.secondsVisible) {
      _hand(
        canvas,
        center,
        radius * 0.8,
        time.second / 60,
        Paint()
          ..color = secondInk
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
      center,
      settings.secondsVisible ? 5 : 7,
      Paint()..color = settings.secondsVisible ? secondInk : hourInk,
    );
  }

  void _hand(
    Canvas canvas,
    Offset center,
    double length,
    double turn,
    Paint p,
  ) {
    final angle = turn * math.pi * 2;
    final end =
        center + Offset(math.sin(angle) * length, -math.cos(angle) * length);
    final g = settings.glowIntensity;
    if (g > 0.01) {
      // a soft halo in the hand's own color, under the hand
      canvas.drawLine(
        center,
        end,
        Paint()
          ..color = p.color.withValues(alpha: g)
          ..strokeWidth = p.strokeWidth + 8 * g
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 9 * g),
      );
    }
    canvas.drawLine(center, end, p);
  }

  @override
  bool shouldRepaint(covariant _AnalogClockPainter oldDelegate) {
    return oldDelegate.time.minute != time.minute ||
        (settings.secondsVisible && oldDelegate.time.second != time.second) ||
        oldDelegate.settings != settings;
  }
}
