import 'package:flutter/material.dart';

import '../../../../core/palette.dart';
import '../../../../domain/standby_models.dart';
import 'dial_painter.dart';

class AnalogClockFace extends StatelessWidget {
  const AnalogClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.numerals = true,
  });

  final DateTime time;
  final StandbySettings settings;

  /// the numbers 12, 3, 6 and 9; off for small dials where they would be unreadable
  final bool numerals;

  @override
  Widget build(BuildContext context) {
    final theme = settings.theme;
    // each part: a picked color, else the theme default
    final marks = settings.colonColor == 0
        ? theme.clockColor.withValues(alpha: 0.75)
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
    return RepaintBoundary(
      child: CustomPaint(
        painter: DialPainter(
          time,
          hourInk: hourInk,
          minuteInk: minuteInk,
          markInk: marks,
          accentInk: settings.secondsVisible ? secondInk : hourInk,
          numeralInk: settings.colonColor == 0
              ? theme.clockColor
              : Color(settings.colonColor),
          showSeconds: settings.secondsVisible,
          numerals: numerals,
          glow: settings.glowIntensity,
        ),
        child: const SizedBox.square(dimension: 310),
      ),
    );
  }
}
