import 'package:flutter/material.dart';

import '../../../../domain/standby_models.dart';
import 'clock_text.dart';
import 'time_parts.dart';

/// The big digital time. On a wide panel it is one line; on a tall one the
/// hours sit over the minutes (and glide there if you turn the phone).
class DigitalClockFace extends StatelessWidget {
  const DigitalClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.onPartTap,
    this.stacked = false,
  });

  final DateTime time;
  final StandbySettings settings;
  final PartTap? onPartTap;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    return TimeParts(
      time: time,
      settings: settings,
      onPartTap: onPartTap,
      stacked: stacked,
      stackGap: -4,
      style: TextStyle(
        color: settings.theme.clockColor,
        fontSize: 152,
        height: 0.88,
        fontWeight: FontWeight.lerp(
          FontWeight.w500,
          FontWeight.w900,
          settings.fontWeight / 900,
        ),
        letterSpacing: 0,
      ),
    );
  }
}
