import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/apple.dart';
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
    // the accent color eases to a new one, instead of jumping
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: settings.appAccentInk),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Motion.fast,
      builder: (context, tinted, _) =>
          _content(context, tinted ?? settings.appAccentInk),
    );
  }

  Widget _content(BuildContext context, Color accent) {
    final theme = settings.theme;
    final month = settings.calendarStyle == CalendarStyle.month;
    final label = month
        ? DateFormat('MMMM yyyy').format(now)
        : DateFormat('EEEE d MMMM yyyy').format(now);
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      // one sentence for a screen reader, not the digits one by one
      label: month ? 'Calendar, $label' : 'Today is $label',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, c) {
          // lay out by the space there is: a wide panel puts the words beside
          // the number or grid, a tall one above it
          final wide = c.maxWidth > c.maxHeight * 1.25;
          final pad = (math.min(c.maxWidth, c.maxHeight) / 14).clamp(
            14.0,
            34.0,
          );
          return Padding(
            padding: EdgeInsets.all(pad),
            child: LayoutBuilder(
              builder: (context, box) {
                final rects = month
                    ? _monthRects(box.maxWidth, box.maxHeight, wide)
                    : _dayRects(box.maxWidth, box.maxHeight, wide);
                final parts = month
                    ? _monthParts(theme, accent)
                    : _dayParts(accent);
                // Every part has its own place for each arrangement, and when
                // the phone turns they glide from one to the other, instead of
                // one layout being swapped for the other.
                return Stack(
                  // parts on the move stay inside the card
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (final e in parts.entries)
                      AnimatedPositioned(
                        key: ValueKey('${month ? 'm' : 'd'}-${e.key}'),
                        duration: still ? Duration.zero : Motion.verySlow,
                        curve: easeOutStrong,
                        left: rects[e.key]!.left,
                        top: rects[e.key]!.top,
                        width: rects[e.key]!.width,
                        height: rects[e.key]!.height,
                        child: e.value,
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  // text that fills the box it is given (left aligned): the box's height sets
  // the size, so the arrangement decides how big each line is
  Widget _fit(Widget text, {Alignment at = Alignment.centerLeft}) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: at, child: text);

  // ---- day ----------------------------------------------------------------

  Map<String, Rect> _dayRects(double w, double h, bool wide) {
    if (wide) {
      final left = w * 0.47;
      final x = left + h * 0.08;
      final rw = w - x;
      // three lines of words, centred on the height
      final a = (h * 0.2).clamp(22.0, 80.0) * 1.25;
      final b = (h * 0.17).clamp(20.0, 72.0) * 1.25;
      final c = (h * 0.14).clamp(18.0, 60.0) * 1.25;
      final top = (h - a - b - c - h * 0.04) / 2;
      return {
        'number': Rect.fromLTWH(0, 0, left, h),
        'weekday': Rect.fromLTWH(x, top, rw, a),
        'month': Rect.fromLTWH(x, top + a + h * 0.02, rw, b),
        'year': Rect.fromLTWH(x, top + a + b + h * 0.04, rw, c),
      };
    }
    final u = math.min(w, h * 0.7);
    final a = (u * 0.15).clamp(22.0, 84.0) * 1.25;
    final b = (u * 0.13).clamp(20.0, 72.0) * 1.25;
    final c = (u * 0.1).clamp(18.0, 56.0) * 1.25;
    return {
      'weekday': Rect.fromLTWH(0, 0, w, a),
      'number': Rect.fromLTWH(0, a, w, math.max(0, h - a - b - c)),
      'month': Rect.fromLTWH(0, h - b - c, w, b),
      'year': Rect.fromLTWH(0, h - c, w, c),
    };
  }

  Map<String, Widget> _dayParts(Color accent) => {
    'number': _Enter(
      delay: 60,
      scale: 0.8,
      child: SizedBox.expand(
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
    ),
    'weekday': _Enter(
      delay: 0,
      child: SizedBox.expand(
        child: _fit(
          Text(
            DateFormat('EEEE').format(now).toUpperCase(),
            maxLines: 1,
            style: TextStyle(
              color: accent,
              fontSize: 100,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    ),
    'month': _Enter(
      delay: 130,
      child: SizedBox.expand(
        child: _fit(
          Text(
            DateFormat('MMMM').format(now),
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 100,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
        ),
      ),
    ),
    'year': _Enter(
      delay: 200,
      child: SizedBox.expand(
        child: _fit(
          Text(
            '${now.year}',
            maxLines: 1,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 100,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ),
  };

  // ---- month --------------------------------------------------------------

  Map<String, Rect> _monthRects(double w, double h, bool wide) {
    if (wide) {
      final gridW = w * 0.68;
      final x = w - gridW;
      final wd = (h * 0.075).clamp(13.0, 24.0) * 1.6;
      return {
        'head': Rect.fromLTWH(0, 0, x - h * 0.08, h),
        'weekdays': Rect.fromLTWH(x, 0, gridW, wd),
        'grid': Rect.fromLTWH(x, wd + 4, gridW, math.max(0, h - wd - 4)),
      };
    }
    final col = w / 7;
    final head = (w * 0.115).clamp(22.0, 60.0);
    final headH = head * 1.25 + head * 0.8 * 1.25;
    final wd = (col * 0.3).clamp(13.0, 26.0) * 1.6;
    final top = headH + head * 0.35;
    return {
      'head': Rect.fromLTWH(0, 0, w, headH),
      'weekdays': Rect.fromLTWH(0, top, w, wd),
      'grid': Rect.fromLTWH(0, top + wd + 6, w, math.max(0, h - top - wd - 6)),
    };
  }

  Map<String, Widget> _monthParts(ThemePreset theme, Color accent) => {
    'head': _Enter(
      delay: 0,
      child: SizedBox.expand(
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('MMMM').format(now).toUpperCase(),
                  maxLines: 1,
                  style: TextStyle(
                    color: accent,
                    fontSize: 100,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    height: 1.1,
                  ),
                ),
                Text(
                  '${now.year}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 78,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    'weekdays': _Enter(
      delay: 60,
      child: LayoutBuilder(
        builder: (context, c) {
          final col = c.maxWidth / 7;
          return _weekdays(col, (c.maxHeight / 1.6).clamp(11.0, 26.0));
        },
      ),
    ),
    'grid': _grid(theme, accent),
  };

  // Weekday names over the grid: three letters when a column is wide enough
  // for them, one letter when it is not.
  Widget _weekdays(double colWidth, double size) {
    final long = colWidth >= size * 2.6;
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Row(
      children: [
        for (final d in names)
          Expanded(
            child: Center(
              child: Text(
                long ? d : d[0],
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: size,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _grid(ThemePreset theme, Color accent) {
    final cells = monthCells(now);
    final weeks = cells.length ~/ 7;
    return Column(
      children: [
        for (var w = 0; w < weeks; w++)
          Expanded(
            child: Row(
              children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: _cell(cells[w * 7 + d], theme, accent, w * 7 + d),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(int? day, ThemePreset theme, Color accent, int index) {
    if (day == null) return const SizedBox.shrink();
    final today = day == now.day;
    return LayoutBuilder(
      builder: (context, c) {
        final size = math.min(c.maxWidth, c.maxHeight);
        return _Enter(
          // the days land one after another, left to right, top to bottom
          delay: 120 + index * 14,
          scale: 0.6,
          child: Center(
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: today
                  ? BoxDecoration(color: accent, shape: BoxShape.circle)
                  : null,
              child: Text(
                '$day',
                style: TextStyle(
                  color: today
                      ? (ThemeData.estimateBrightnessForColor(accent) ==
                                Brightness.light
                            ? Colors.black
                            : Colors.white)
                      : Colors.white,
                  // as big as the cell allows, never under 14
                  fontSize: (size * 0.52).clamp(14.0, 60.0),
                  fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Arrives a beat after the card appears: fades in, rises a little and grows
/// from [scale] to full size, with an ease-out that starts fast (under 0.5 s in
/// all). The wait is part of the animation, so nothing needs a timer. With
/// Animations off it is simply there.
class _Enter extends StatefulWidget {
  const _Enter({required this.delay, required this.child, this.scale = 0.92});

  final int delay; // ms
  final double scale;
  final Widget child;

  @override
  State<_Enter> createState() => _EnterState();
}

class _EnterState extends State<_Enter> with SingleTickerProviderStateMixin {
  static const _run = 380;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.delay + _run),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(
      parent: _c,
      curve: Interval(
        widget.delay / (widget.delay + _run),
        1,
        curve: easeOutStrong,
      ),
    );
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) {
        final v = t.value;
        if (v >= 1) return child!;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 14),
            child: Transform.scale(
              scale: widget.scale + (1 - widget.scale) * v,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
