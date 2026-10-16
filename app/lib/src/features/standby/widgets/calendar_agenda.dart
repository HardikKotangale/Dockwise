import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/calendar_service.dart';

/// The Calendar card's Meetings tab: what is coming up, from the system
/// calendar. It shows as many rows as fit; with no access it says how to allow
/// it, and where there is no calendar at all (Android, Windows) it says so.
class CalendarAgenda extends StatelessWidget {
  const CalendarAgenda({
    super.key,
    required this.now,
    required this.accent,
    required this.access,
    required this.meetings,
    required this.showTitles,
    this.onConnect,
    this.onEdge,
    this.compact = false,
  });

  final DateTime now;
  final Color accent;
  final CalendarAccess access;
  final List<Meeting> meetings;
  final bool showTitles;
  final VoidCallback? onConnect;

  /// the list was pulled past its first or last meeting: the next tab
  final VoidCallback? onEdge;

  /// a small tile: only the next few meetings, no heading
  final bool compact;

  static String _day(DateTime d, DateTime now) {
    final a = DateTime(d.year, d.month, d.day);
    final b = DateTime(now.year, now.month, now.day);
    final diff = a.difference(b).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return DateFormat('EEE d MMM').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final unit = (math.min(c.maxWidth, c.maxHeight) / 300).clamp(0.6, 2.0);
        final pad = (compact ? 12.0 : 26.0) * unit.clamp(0.8, 1.4);
        return Padding(
          padding: EdgeInsets.all(pad),
          child: switch (access) {
            CalendarAccess.granted => _list(c, unit, pad),
            _ => _notice(unit),
          },
        );
      },
    );
  }

  Widget _notice(double unit) {
    final (icon, text, button) = switch (access) {
      CalendarAccess.unsupported => (
        Icons.event_busy_rounded,
        'Meetings show on a Mac or an iPhone, from the Calendar app.',
        null,
      ),
      CalendarAccess.denied => (
        Icons.lock_outline_rounded,
        'Calendar access is off. Allow it in System Settings > Privacy & '
            'Security > Calendars.',
        null,
      ),
      _ => (
        Icons.event_available_rounded,
        'Show your meetings here. Hushdock only reads them, and keeps nothing.',
        'Allow calendar',
      ),
    };
    final size = (compact ? 13.0 : 17.0) * unit.clamp(0.8, 1.5);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 300 * unit.clamp(0.8, 1.5)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accent, size: size * 2),
              SizedBox(height: size * 0.6),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: size,
                  height: 1.3,
                ),
              ),
              if (button != null && onConnect != null) ...[
                SizedBox(height: size),
                GestureDetector(
                  onTap: onConnect,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: size * 1.3,
                      vertical: size * 0.6,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      button,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(BoxConstraints c, double unit, double pad) {
    final u = unit.clamp(0.8, 1.5);
    final upcoming = [
      for (final m in meetings)
        if (m.end.isAfter(now)) m,
    ];
    if (upcoming.isEmpty) return _empty(unit);

    // by day: the day's heading, its all-day banners, then the timed meetings
    final days = <String, List<Meeting>>{};
    for (final m in upcoming) {
      final d = m.start.isBefore(now) ? now : m.start;
      days.putIfAbsent(_day(d, now), () => []).add(m);
    }
    final headH = 38.0 * u;
    final bannerH = (compact ? 30.0 : 36.0) * u;
    final rowH = (compact ? 50.0 : 66.0) * u;
    final shown = <Widget>[];
    var first = true;
    for (final e in days.entries) {
      final allDay = [
        for (final m in e.value)
          if (m.allDay) m,
      ];
      final timed = [
        for (final m in e.value)
          if (!m.allDay) m,
      ];
      if (!first) shown.add(SizedBox(height: 12 * u));
      first = false;
      shown.add(
        SizedBox(height: headH, child: _heading(e.key, e.value.first.start, u)),
      );
      for (final m in allDay) {
        shown.add(
          SizedBox(height: bannerH + 6 * u, child: _banner(m, bannerH, u)),
        );
      }
      for (final m in timed) {
        shown.add(SizedBox(height: rowH, child: _row(m, rowH, u)));
      }
    }
    // As many days as there are room for show at once; a month's worth is
    // there to scroll. While it all fits the list takes no drags, so a swipe
    // still changes the tab; when it scrolls, a swipe past either end does.
    return _EdgeSwipe(
      onEdge: onEdge,
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: shown,
      ),
    );
  }

  // "Today" and the date, like the heading of a day in the Calendar app
  Widget _heading(String day, DateTime date, double u) => Align(
    alignment: Alignment.centerLeft,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          day,
          style: TextStyle(
            color: accent,
            fontSize: (compact ? 18.0 : 24.0) * u,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(width: 10 * u),
        Flexible(
          child: Text(
            DateFormat('EEE d MMM').format(date.isBefore(now) ? now : date),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white54,
              fontSize: (compact ? 13.0 : 16.0) * u,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Color _tint(Meeting m) => m.color == 0 ? accent : Color(m.color);

  String _title(Meeting m) =>
      showTitles && m.title.isNotEmpty ? m.title : 'Busy';

  // an all-day event: a tinted banner in its calendar's colour
  Widget _banner(Meeting m, double h, double u) {
    final tint = _tint(m);
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * u),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(10 * u),
        ),
        child: Row(
          children: [
            Container(
              width: 4 * u,
              margin: EdgeInsets.symmetric(vertical: 6 * u, horizontal: 8 * u),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Text(
                _title(m),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: (compact ? 13.0 : 16.0) * u,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10 * u),
              child: Text(
                'All day',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: (compact ? 11.0 : 13.0) * u,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // a meeting: its time, a bar in its calendar's colour, its title
  Widget _row(Meeting m, double h, double u) {
    final fmt = DateFormat.jm();
    final on = !m.start.isAfter(now) && m.end.isAfter(now);
    final tint = _tint(m);
    final big = (compact ? 14.0 : 18.0) * u;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3 * u),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: on ? tint.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(12 * u),
        ),
        child: Row(
          children: [
            SizedBox(width: 6 * u),
            SizedBox(
              width: big * 4.6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fmt.format(m.start),
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: big * 0.9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    on ? 'Now' : fmt.format(m.end),
                    maxLines: 1,
                    style: TextStyle(
                      color: on ? tint : Colors.white54,
                      fontSize: big * 0.72,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 4 * u,
              margin: EdgeInsets.symmetric(vertical: 8 * u),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 10 * u),
            Expanded(
              child: Text(
                _title(m),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: big,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: 6 * u),
          ],
        ),
      ),
    );
  }

  Widget _empty(double unit) {
    final size = (compact ? 13.0 : 18.0) * unit.clamp(0.8, 1.5);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: accent,
            size: size * 2,
          ),
          SizedBox(height: size * 0.5),
          Text(
            'No meetings coming up',
            style: TextStyle(color: Colors.white70, fontSize: size),
          ),
        ],
      ),
    );
  }
}

/// Calls [onEdge] when a scrolling list is pulled past either end (once per
/// flick), so a swipe can still change the tab after the list has run out.
class _EdgeSwipe extends StatefulWidget {
  const _EdgeSwipe({required this.child, this.onEdge});

  final Widget child;
  final VoidCallback? onEdge;

  @override
  State<_EdgeSwipe> createState() => _EdgeSwipeState();
}

class _EdgeSwipeState extends State<_EdgeSwipe> {
  DateTime _last = DateTime(0);

  @override
  Widget build(BuildContext context) =>
      NotificationListener<OverscrollNotification>(
        onNotification: (n) {
          final now = DateTime.now();
          if (n.overscroll.abs() > 4 &&
              now.difference(_last) > const Duration(milliseconds: 900)) {
            _last = now;
            widget.onEdge?.call();
          }
          return false;
        },
        child: widget.child,
      );
}
