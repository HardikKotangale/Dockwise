import 'package:flutter/material.dart';

import '../../../../core/apple.dart';
import '../../../../domain/standby_models.dart';
import 'clock_text.dart';

/// Apple "Float": big bubbly numerals, one pastel per digit. Hours over
/// minutes in a tall panel, side by side in a wide one, gliding between the
/// two when the shape changes.
class FloatClockFace extends StatelessWidget {
  const FloatClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.onPartTap,
    this.stacked = true,
  });

  final DateTime time;
  final StandbySettings settings;
  final PartTap? onPartTap;

  /// hours over minutes (a tall panel) instead of side by side
  final bool stacked;

  static const _pastels = [
    Color(0xFFFFB3C7),
    Color(0xFFFF9EBB),
    Color(0xFFFFE680),
    Color(0xFFC9B8F5),
  ];

  @override
  Widget build(BuildContext context) {
    final t = clockText(time, settings);
    final parts = t.text.split(':');
    final digits = [...parts[0].split(''), ...parts[1].split('')];
    final plain = settings.theme.id != 'aurora';
    // a picked hours/minutes color overrides the pastels for that row
    Color colorAt(int i, bool minutesRow) {
      final picked = minutesRow ? settings.minutesColor : settings.hoursColor;
      if (picked != 0) return Color(picked);
      return plain ? settings.theme.clockColor : _pastels[i % _pastels.length];
    }

    Widget row(List<String> chars, int offset) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chars.length; i++)
          Text(
            chars[i],
            style: TextStyle(
              color: colorAt(offset + i, offset > 0),
              fontSize: 150,
              height: 0.86,
              fontWeight: FontWeight.w900,
              letterSpacing: -6,
            ),
          ),
      ],
    );
    final h = parts[0].length;
    return MorphLayout(
      stacked: stacked,
      rowGap: 18,
      hours: tapPart(onPartTap, ClockPart.hours, row(digits.sublist(0, h), 0)),
      minutes: tapPart(onPartTap, ClockPart.minutes, row(digits.sublist(h), h)),
      trailing: t.suffix == null
          ? null
          : tapPart(
              onPartTap,
              ClockPart.detail,
              Text(
                t.suffix!,
                style: TextStyle(
                  color: settings.detailInk,
                  shadows: glowShadows(
                    settings.detailInk,
                    settings.glowIntensity,
                  ),
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
    );
  }
}
