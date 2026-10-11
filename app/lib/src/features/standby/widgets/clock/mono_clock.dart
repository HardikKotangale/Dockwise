import 'package:flutter/material.dart';

import '../../../../domain/standby_models.dart';
import 'clock_text.dart';
import 'time_parts.dart';

/// Apple "Minimal Mono": thin monospaced numerals, quiet and low-contrast.
/// One line when wide; hours over minutes when tall.
class MonoClockFace extends StatelessWidget {
  const MonoClockFace({
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
      suffixScale: 0.3,
      style: TextStyle(
        color: settings.theme.clockColor,
        fontFamily: 'monospace',
        fontSize: 120,
        fontWeight: FontWeight.w300,
        letterSpacing: -2,
        height: 1,
      ),
    );
  }
}
