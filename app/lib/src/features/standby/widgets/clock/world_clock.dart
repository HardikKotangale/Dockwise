import 'package:flutter/material.dart';

import '../../../../domain/standby_models.dart';
import 'clock_text.dart';
import 'time_parts.dart';
import 'zones.dart';

/// Two times only: this device's local time and one chosen city.
class WorldClockFace extends StatelessWidget {
  const WorldClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.onPartTap,
    this.stacked = false,
  });

  final DateTime time;
  final StandbySettings settings;
  final PartTap? onPartTap;

  /// each time as hours over minutes (a tall panel), so the digits grow to
  /// fill the height instead of sitting small on one line
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    if (settings.worldZone.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(_localLabel, time),
          const SizedBox(height: 28),
          Text(
            'Tap to add a city',
            style: TextStyle(
              color: settings.theme.clockColor.withValues(alpha: 0.5),
              fontSize: 36,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
    final city = settings.worldCity.isNotEmpty
        ? settings.worldCity
        : zoneLabel(settings.worldZone);
    final other = timeInZone(time, settings.worldZone);
    final dayDiff = DateTime(
      other.year,
      other.month,
      other.day,
    ).difference(DateTime(time.year, time.month, time.day)).inDays;
    // another day over there: show which one, e.g. "Tokyo · Wed, Oct 7"
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
    ];
    final note = dayDiff == 0
        ? ''
        : ' · ${days[other.weekday - 1]}, ${months[other.month - 1]} ${other.day}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(_localLabel, time),
        const SizedBox(height: 28),
        _row('$city$note', other),
      ],
    );
  }

  // this phone's city (from the location lookup), else plain "Local"
  String get _localLabel =>
      settings.localCity.isNotEmpty ? settings.localCity : 'Local';

  Widget _row(String label, DateTime t) {
    final theme = settings.theme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tapPart(
          onPartTap,
          ClockPart.label,
          Text(
            label,
            style: TextStyle(
              color:
                  settings.labelInk, // pick it under Clock colors > City names
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TimeParts(
          time: t,
          settings: settings,
          onPartTap: onPartTap,
          stacked: stacked,
          showSeconds: false,
          suffixScale: 0.29,
          stackGap: -4,
          style: TextStyle(
            color: theme.clockColor,
            fontSize: 104,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
