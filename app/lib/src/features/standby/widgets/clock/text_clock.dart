import 'package:flutter/material.dart';

import '../../../../domain/standby_models.dart';
import 'clock_text.dart';

class TextClockFace extends StatelessWidget {
  const TextClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.onPartTap,
  });

  final DateTime time;
  final StandbySettings settings;
  final PartTap? onPartTap;

  @override
  Widget build(BuildContext context) {
    final hour = settings.use24HourTime
        ? time.hour
        : (time.hour % 12 == 0 ? 12 : time.hour % 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tapPart(
          onPartTap,
          ClockPart.hours,
          Text(numberWord(hour), style: _textStyle(settings, 72)),
        ),
        tapPart(
          onPartTap,
          ClockPart.minutes,
          Text(
            numberWord(time.minute),
            style: _textStyle(settings, 56).copyWith(
              color: settings.minutesColor == 0
                  ? settings.theme.clockSecondary
                  : settings.minutesInk,
            ),
          ),
        ),
        if (!settings.use24HourTime)
          tapPart(
            onPartTap,
            ClockPart.detail,
            Text(
              time.hour < 12 ? 'AM' : 'PM',
              style: _textStyle(
                settings,
                28,
              ).copyWith(color: settings.detailInk),
            ),
          ),
      ],
    );
  }
}

TextStyle _textStyle(StandbySettings settings, double size) {
  return TextStyle(
    color: settings.hoursInk,
    fontSize: size,
    fontWeight: FontWeight.w900,
    height: 0.95,
    letterSpacing: 0,
    shadows: glowShadows(settings.hoursInk, settings.glowIntensity),
  );
}
