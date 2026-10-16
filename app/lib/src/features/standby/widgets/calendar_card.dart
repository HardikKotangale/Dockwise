import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/apple.dart';
import '../../../domain/standby_models.dart';
import '../../../services/calendar_service.dart';
import 'calendar_agenda.dart';

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
  const CalendarCard({
    super.key,
    required this.settings,
    required this.now,
    this.entrance = true,
    this.compact = false,
    this.access = CalendarAccess.unknown,
    this.meetings = const [],
    this.onConnect,
  });

  /// the Meetings tab: whether the calendar may be read, what is coming up,
  /// and the button that asks for access
  final CalendarAccess access;
  final List<Meeting> meetings;
  final VoidCallback? onConnect;

  /// A small tile (Summary): always the stacked arrangement. Today: weekday,
  /// number, month and year, the week's letters. Month: the month and year on
  /// top, the grid across the whole width under it.
  final bool compact;

  /// The parts arrive one after another when the card appears. Off where the
  /// card sits inside something that has its own entrance (a Summary tile).
  final bool entrance;

  final StandbySettings settings;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final style = settings.calendarStyle;
    final still = MediaQuery.disableAnimationsOf(context);
    final key = ValueKey(style);
    final card = _card(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Today and Month trade places like the weather's pages: the month
        // rises into place from below, Today settles from above
        AnimatedSwitcher(
          duration: still ? Duration.zero : Motion.medium,
          switchInCurve: easeOutStrong,
          switchOutCurve: easeOutStrong,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          transitionBuilder: (child, anim) {
            final incoming = child.key == key;
            final dir = style == CalendarStyle.day ? -1.0 : 1.0;
            return AnimatedBuilder(
              animation: anim,
              builder: (context, c) => anim.value == 1
                  ? c!
                  : FractionalTranslation(
                      translation: Offset(
                        0,
                        (incoming ? dir : -dir) * 0.12 * (1 - anim.value),
                      ),
                      child: Opacity(
                        opacity: anim.value.clamp(0.0, 1.0),
                        child: c,
                      ),
                    ),
              child: child,
            );
          },
          child: KeyedSubtree(
            key: key,
            child: entrance ? card : _NoEntrance(child: card),
          ),
        ),
        // the pill and dots naming the view, for a moment after each swipe
        SwipeRail(
          index: style.index,
          labels: const ['Today', 'Month', 'Meetings'],
        ),
      ],
    );
  }

  // the calendar's own color when one is picked, else the theme's accent
  Color get _accent => settings.calendarColor == 0
      ? settings.appAccentInk
      : Color(settings.calendarColor);

  Widget _card(BuildContext context) {
    // the accent color eases to a new one, instead of jumping
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _accent),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Motion.fast,
      builder: (context, tinted, _) =>
          settings.calendarStyle == CalendarStyle.agenda
          ? CalendarAgenda(
              now: now,
              accent: tinted ?? _accent,
              access: access,
              meetings: meetings,
              showTitles: settings.calendarTitles,
              onConnect: onConnect,
              compact: compact,
            )
          : _content(context, tinted ?? _accent),
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
          // the number or grid, a tall one above it. A panel only a little
          // wider than tall (one of two on a 16:9 screen) is wide already:
          // stacked, it left half the card empty
          final wide = c.maxWidth > c.maxHeight * 1.1;
          final pad = (math.min(c.maxWidth, c.maxHeight) / 14).clamp(
            14.0,
            34.0,
          );
          return Padding(
            padding: EdgeInsets.all(pad),
            child: LayoutBuilder(
              builder: (context, box) {
                // A full card that is wide gets a side column. A small tile
                // stacks, unless it is low and wide (Summary beside an open
                // dock): then the date sits beside its words, or there would
                // be no height left for it.
                final side = wide && !compact;
                final low = compact && box.maxWidth > box.maxHeight * 1.6;
                final rects = month
                    ? _monthRects(box.maxWidth, box.maxHeight, side, low: low)
                    : _dayRects(box.maxWidth, box.maxHeight, side, low: low);
                final parts = month
                    ? _monthParts(theme, accent, thisWeekOnly: low)
                    : _dayParts(accent, withYear: !side);
                // Every part has its own place for each arrangement, and when
                // the phone turns they glide from one to the other, instead of
                // one layout being swapped for the other.
                return Stack(
                  // parts on the move stay inside the card
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (final e in parts.entries)
                      if (rects[e.key]!.height > 0)
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

  Map<String, Rect> _dayRects(
    double w,
    double h,
    bool wide, {
    bool low = false,
  }) {
    if (low) {
      // the number at full height on the left, the weekday and "October
      // 2026" beside it; no room for the week's letters
      final em = h * 1.22;
      final numW = math.min(w * 0.45, em * 0.58 * '${now.day}'.length);
      final x = numW + h * 0.12;
      final rw = math.max(0.0, w - x);
      return {
        'number': Rect.fromLTWH(0, -h * 0.11, numW, em),
        'weekday': Rect.fromLTWH(x, h * 0.1, rw, h * 0.34),
        'month': Rect.fromLTWH(x, h * 0.52, rw, h * 0.3),
        'year': Rect.fromLTWH(x, h, rw, 0),
        'week': Rect.fromLTWH(x, h, rw, 0),
      };
    }
    if (wide) {
      // One number on the card: the date, filling the height (its line box is
      // taller than the card so the digits themselves, about 0.72 of it, reach
      // nearly top to bottom) in a column as wide as its digits need. The
      // words start right after it; the week's letters sit at the foot.
      final em = h * 1.22;
      final digits = '${now.day}'.length;
      final numW = math.min(w * 0.5, em * 0.58 * digits);
      final x = numW + h * 0.07;
      final rw = math.max(0.0, w - x);
      return {
        'number': Rect.fromLTWH(0, -h * 0.11, numW, em),
        'weekday': Rect.fromLTWH(x, 0, rw, h * 0.2),
        'month': Rect.fromLTWH(x, h * 0.24, rw, h * 0.17),
        'year': Rect.fromLTWH(x, h * 0.43, rw, h * 0.12),
        'week': Rect.fromLTWH(x, h * 0.84, rw, h * 0.16),
      };
    }
    // Tall: the weekday, the number as big as the rest leaves room for, the
    // month and year on one line, and the week's letters across the foot.
    final u = math.min(w, h * 0.7);
    final a = (u * 0.15).clamp(22.0, 84.0) * 1.25;
    final b = (u * 0.12).clamp(20.0, 64.0) * 1.25;
    // the week's letters only where they can be read
    var weekH = math.min(h * 0.1, w * 0.13);
    if (weekH < 18) weekH = 0;
    final gap = h * 0.03;
    final numH = math.max(0.0, h - a - b - weekH - gap * 2);
    return {
      'weekday': Rect.fromLTWH(0, 0, w, a),
      // the line box is a little taller than its room, so the digits (about
      // 0.72 of it) fill the room itself
      'number': Rect.fromLTWH(0, a - numH * 0.06, w, numH * 1.12),
      'month': Rect.fromLTWH(0, a + numH, w, b),
      'week': Rect.fromLTWH(0, h - weekH, w, weekH),
      // the year is part of the month line here
      'year': Rect.fromLTWH(0, h, w, 0),
    };
  }

  Map<String, Widget> _dayParts(Color accent, {required bool withYear}) => {
    'week': _Enter(delay: 260, child: _weekStrip(accent)),
    'number': _Enter(
      delay: 60,
      scale: 0.8,
      child: SizedBox.expand(
        child: FittedBox(
          // grows to its box (a big screen) as well as shrinking
          fit: BoxFit.contain,
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
          // the year, when it shares the line, is quieter than the month
          Text.rich(
            TextSpan(
              text: DateFormat('MMMM').format(now),
              children: [
                if (withYear)
                  TextSpan(
                    text: ' ${now.year}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
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
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 100,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ),
  };

  // Where today falls in the week, in letters only (S M T W T F S, Sunday
  // first like the month grid): today's letter in the accent circle, days
  // gone faded. No dates, so the big number stays the only number.
  Widget _weekStrip(Color accent) {
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.light
        ? Colors.black
        : Colors.white;
    const letters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final todayAt = now.weekday % 7; // Sunday 0 .. Saturday 6
    return LayoutBuilder(
      builder: (context, c) {
        final circle = math.min(c.maxWidth / 7 * 0.8, c.maxHeight);
        return Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                // shrinks with its box while the card glides between
                // arrangements, rather than overflowing it
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    width: circle,
                    height: circle,
                    alignment: Alignment.center,
                    decoration: i == todayAt
                        ? BoxDecoration(color: accent, shape: BoxShape.circle)
                        : null,
                    child: Text(
                      letters[i],
                      style: TextStyle(
                        color: i == todayAt
                            ? onAccent
                            : Colors.white.withValues(
                                alpha: i < todayAt ? 0.3 : 0.65,
                              ),
                        fontSize: circle * 0.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---- month --------------------------------------------------------------

  Map<String, Rect> _monthRects(
    double w,
    double h,
    bool wide, {
    bool low = false,
  }) {
    if (low) {
      // A whole month cannot be read in a tile this low: the title, then
      // this week's row of the grid (today circled, days gone faded).
      return {
        'head': Rect.fromLTWH(0, 0, w, h * 0.27),
        'today': Rect.fromLTWH(0, h, w, 0),
        'weekdays': Rect.fromLTWH(0, h * 0.36, w, h * 0.2),
        'grid': Rect.fromLTWH(0, h * 0.58, w, h * 0.42),
      };
    }
    if (wide) {
      // The grid is the one place with numbers. The side column has the
      // month and year big at its top and today's weekday, in words, at its
      // foot (the grid's circle already says which date it is).
      final gridW = w * 0.64;
      final x = w - gridW;
      final side = x - h * 0.07;
      final wd = (h * 0.075).clamp(13.0, 24.0) * 1.6;
      return {
        'head': Rect.fromLTWH(0, 0, side, h * 0.38),
        'today': Rect.fromLTWH(0, h * 0.74, side, h * 0.26),
        'weekdays': Rect.fromLTWH(x, 0, gridW, wd),
        'grid': Rect.fromLTWH(x, wd + 4, gridW, math.max(0, h - wd - 4)),
      };
    }
    final col = w / 7;
    final head = compact
        ? (h * 0.13).clamp(12.0, 44.0)
        : (w * 0.115).clamp(22.0, 60.0);
    // a tile has the month and year on one line, a card on two
    final headH = compact ? head * 1.25 : head * 1.25 + head * 0.8 * 1.25;
    final wd = compact
        ? (h * 0.075).clamp(9.0, 22.0) * 1.5
        : (col * 0.3).clamp(13.0, 26.0) * 1.6;
    final top = headH + head * (compact ? 0.2 : 0.35);
    return {
      'head': Rect.fromLTWH(0, 0, w, headH),
      'today': Rect.fromLTWH(0, 0, w, 0), // no room for it in a tall panel
      'weekdays': Rect.fromLTWH(0, top, w, wd),
      'grid': Rect.fromLTWH(0, top + wd + 6, w, math.max(0, h - top - wd - 6)),
    };
  }

  Map<String, Widget> _monthParts(
    ThemePreset theme,
    Color accent, {
    bool thisWeekOnly = false,
  }) => {
    'head': _Enter(
      delay: 0,
      child: SizedBox.expand(
        child: Align(
          alignment: Alignment.topLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: compact
                // one line in a tile: OCTOBER 2026, the year quieter
                ? Text.rich(
                    TextSpan(
                      text: DateFormat('MMMM').format(now).toUpperCase(),
                      children: [
                        TextSpan(
                          text: '  ${now.year}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    style: TextStyle(
                      color: accent,
                      fontSize: 100,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      height: 1.1,
                    ),
                  )
                : Column(
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
    'today': _Enter(delay: 40, child: _today()),
    'weekdays': _Enter(
      delay: 60,
      child: LayoutBuilder(
        builder: (context, c) {
          final col = c.maxWidth / 7;
          return _weekdays(col, (c.maxHeight / 1.6).clamp(7.0, 26.0));
        },
      ),
    ),
    'grid': _grid(theme, accent, thisWeekOnly: thisWeekOnly),
  };

  // Today, at the foot of the side column, in words: which date it is, the
  // circle in the grid already says.
  Widget _today() {
    return SizedBox.expand(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TODAY',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                DateFormat('EEEE').format(now),
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Weekday names over the grid: three letters when a column is wide enough
  // for them, one letter when it is not.
  Widget _weekdays(double colWidth, double size) {
    final long = colWidth >= size * 2.6;
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Row(
      children: [
        for (final d in names)
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
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

  Widget _grid(ThemePreset theme, Color accent, {bool thisWeekOnly = false}) {
    final cells = monthCells(now);
    final weeks = cells.length ~/ 7;
    final todayWeek = cells.indexOf(now.day) ~/ 7;
    return Column(
      children: [
        for (var w = 0; w < weeks; w++)
          if (!thisWeekOnly || w == todayWeek)
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
              // shrinks to the cell (a small tile), never overlaps the next
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$day',
                  style: TextStyle(
                    color: today
                        ? (ThemeData.estimateBrightnessForColor(accent) ==
                                  Brightness.light
                              ? Colors.black
                              : Colors.white)
                        // days gone fade back, so the eye goes to today and
                        // what is still ahead
                        : Colors.white.withValues(
                            alpha: day < now.day ? 0.4 : 1,
                          ),
                    // as big as the cell allows (two digits still fit its
                    // width)
                    fontSize: (size * 0.6).clamp(6.0, 110.0),
                    fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                  ),
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
/// Inside it, the card's parts are simply there (see CalendarCard.entrance).
class _NoEntrance extends InheritedWidget {
  const _NoEntrance({required super.child});

  @override
  bool updateShouldNotify(_NoEntrance oldWidget) => false;
}

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
    final quiet =
        context.dependOnInheritedWidgetOfExactType<_NoEntrance>() != null;
    if (quiet || MediaQuery.disableAnimationsOf(context)) {
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
