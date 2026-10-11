import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/standby_models.dart';

/// Calendar cells for [month], Sunday first: leading/trailing nulls pad the
/// first and last week so the list length is a multiple of 7.
List<int?> monthCells(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final days = DateTime(month.year, month.month + 1, 0).day;
  final leading = first.weekday % 7; // Sunday = 0
  final cells = <int?>[
    for (var i = 0; i < leading; i++) null,
    for (var d = 1; d <= days; d++) d,
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}

/// Calendar card: today's date (day) or the whole month grid (month).
class CalendarCard extends StatelessWidget {
  const CalendarCard({super.key, required this.settings, required this.now});

  final StandbySettings settings;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = settings.theme;
    return LayoutBuilder(
      builder: (context, c) {
        final unit = math.min(c.maxWidth, c.maxHeight);
        final pad = (unit / 10).clamp(14.0, 32.0);
        return Padding(
          padding: EdgeInsets.all(pad),
          child: settings.calendarStyle == CalendarStyle.month
              ? _month(theme, unit)
              : _day(theme, unit),
        );
      },
    );
  }

  Widget _day(ThemePreset theme, double unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEEE').format(now).toUpperCase(),
          maxLines: 1,
          style: TextStyle(
            color: settings.appAccentInk,
            fontSize: (unit / 10).clamp(16.0, 30.0),
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${now.day}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 400,
                height: 1,
                fontWeight: FontWeight.w600,
                letterSpacing: -12,
              ),
            ),
          ),
        ),
        Text(
          DateFormat('MMMM yyyy').format(now),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white70,
            fontSize: (unit / 11).clamp(16.0, 28.0),
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _month(ThemePreset theme, double unit) {
    final cells = monthCells(now);
    final weeks = cells.length ~/ 7;
    final headerSize = (unit / 11).clamp(15.0, 26.0);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('MMMM').format(now).toUpperCase(),
                maxLines: 1,
                style: TextStyle(
                  color: settings.appAccentInk,
                  fontSize: headerSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Text(
              '${now.year}',
              style: TextStyle(
                color: Colors.white54,
                fontSize: headerSize * 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: (headerSize * 0.7).clamp(11.0, 18.0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Column(
            children: [
              for (var w = 0; w < weeks; w++)
                Expanded(
                  child: Row(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Expanded(child: _cell(cells[w * 7 + d], theme)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(int? day, ThemePreset theme) {
    if (day == null) return const SizedBox.shrink();
    final today = day == now.day;
    return LayoutBuilder(
      builder: (context, c) {
        final size = math.min(c.maxWidth, c.maxHeight);
        return Center(
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: today
                ? BoxDecoration(
                    color: settings.appAccentInk,
                    shape: BoxShape.circle,
                  )
                : null,
            child: Text(
              '$day',
              style: TextStyle(
                color: today
                    ? (ThemeData.estimateBrightnessForColor(
                                settings.appAccentInk,
                              ) ==
                              Brightness.light
                          ? Colors.black
                          : Colors.white)
                    : Colors.white,
                fontSize: (size * 0.46).clamp(10.0, 24.0),
                fontWeight: today ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      },
    );
  }
}
