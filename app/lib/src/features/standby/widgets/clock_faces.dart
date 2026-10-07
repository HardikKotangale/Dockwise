import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../../domain/standby_models.dart';

/// City name for an IANA zone id, e.g. "America/New_York" -> "New York".
String zoneLabel(String zoneId) => zoneId.split('/').last.replaceAll('_', ' ');

const _regions = {
  'Africa',
  'America',
  'Antarctica',
  'Arctic',
  'Asia',
  'Atlantic',
  'Australia',
  'Europe',
  'Indian',
  'Pacific',
};

/// Search every city in the time-zone database (offline). Best matches first.
List<String> searchZones(String query, {int limit = 8}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  _initZones();
  final hits = <String>[];
  for (final id in tz.timeZoneDatabase.locations.keys) {
    if (!_regions.contains(id.split('/').first)) continue;
    if (zoneLabel(id).toLowerCase().contains(q)) hits.add(id);
  }
  hits.sort((a, b) {
    final sa = zoneLabel(a).toLowerCase().startsWith(q) ? 0 : 1;
    final sb = zoneLabel(b).toLowerCase().startsWith(q) ? 0 : 1;
    return sa != sb ? sa - sb : zoneLabel(a).compareTo(zoneLabel(b));
  });
  return hits.take(limit).toList();
}

/// Called when a part of the clock (hours, minutes...) is tapped.
typedef PartTap = void Function(ClockPart part);

Widget _tap(PartTap? onTap, ClockPart part, Widget child) => onTap == null
    ? child
    : GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(part),
        child: child,
      );

class ClockFace extends StatelessWidget {
  const ClockFace({
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
    final face = switch (settings.clockStyle) {
      ClockStyle.digital => DigitalClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
      ),
      ClockStyle.analog => AnalogClockFace(time: time, settings: settings),
      ClockStyle.float => FloatClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
      ),
      ClockStyle.frame => FrameClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
      ),
      ClockStyle.mono => MonoClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
      ),
      ClockStyle.flip => FlipClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
      ),
      ClockStyle.text => TextClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
      ),
      ClockStyle.world => WorldClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
      ),
    };
    // Every style fills its panel (portrait or landscape); the Size slider
    // shrinks it to a share of that, so it works for all styles alike.
    final share = settings.fontScale.clamp(0.4, 1.0);
    return FractionallySizedBox(
      widthFactor: share,
      heightFactor: share,
      child: FittedBox(fit: BoxFit.contain, child: face),
    );
  }
}

class DigitalClockFace extends StatelessWidget {
  const DigitalClockFace({
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
    final theme = settings.theme;
    final t = _clockText(time, settings, seconds: settings.secondsVisible);
    final size = 152.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _TimeText(
          text: t.text,
          settings: settings,
          onPartTap: onPartTap,
          style: TextStyle(
            color: theme.clockColor,
            fontSize: size,
            height: 0.88,
            fontWeight: FontWeight.lerp(
              FontWeight.w500,
              FontWeight.w900,
              settings.fontWeight / 900,
            ),
            letterSpacing: 0,
            shadows: _glow(theme.clockAccent, settings.glowIntensity),
          ),
        ),
        if (t.suffix != null)
          _tap(
            onPartTap,
            ClockPart.detail,
            Padding(
              padding: EdgeInsets.only(left: 10, bottom: size * 0.06),
              child: Text(
                t.suffix!,
                style: TextStyle(
                  color: settings.detailInk,
                  fontSize: size * 0.26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The iOS StandBy "digital with seconds" look: a big, heavy, condensed time
/// in a square, with 60 short ticks around the border. The tick for the current
/// second is the brightest; the ones behind it fade away like a comet's tail.
class FrameClockFace extends StatelessWidget {
  const FrameClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.onPartTap,
  });

  final DateTime time;
  final StandbySettings settings;
  final PartTap? onPartTap;

  static const _side = 300.0;

  @override
  Widget build(BuildContext context) {
    final t = _clockText(time, settings);
    // Apple shows 8:13, not 08:13
    final text = t.text.replaceFirst(RegExp(r'^0(?=\d)'), '');
    return SizedBox.square(
      dimension: _side,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // only the tick border reacts to taps (see _FramePainter.hitTest),
          // not the empty middle of the frame
          GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onTap: onPartTap == null ? null : () => onPartTap!(ClockPart.label),
            child: CustomPaint(
              size: const Size.square(_side),
              painter: _FramePainter(
                second: time.second,
                ink: settings.ticksInk,
                scale: settings.tickScale,
              ),
            ),
          ),
          // always inside the ticks, however wide the time is (e.g. 10:09 PM)
          SizedBox(
            width: _side - 58,
            height: _side - 70,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TimeText(
                    text: text,
                    settings: settings,
                    onPartTap: onPartTap,
                    solidColon: true,
                    style: const TextStyle(
                      fontFamily: 'BebasNeue',
                      fontSize: 225,
                      height: 0.95,
                    ),
                  ),
                  if (t.suffix != null)
                    _tap(
                      onPartTap,
                      ClockPart.detail,
                      Text(
                        t.suffix!,
                        style: TextStyle(
                          fontFamily: 'BebasNeue',
                          color: settings.detailInk,
                          fontSize: 50,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Length and thickness of a Frame tick at [scale] (1 = default). The default
/// is deliberately small: fine lines like Apple's, not chunky bars.
({double length, double width}) frameTickSize(double scale) {
  final k = scale.clamp(0.5, 1.6);
  return (length: 14 * k, width: 3.2 * k);
}

/// Brightness (0..1) of border tick [i] when it is [second] o'clock-seconds:
/// full at the current second, fading the further behind it a tick is, and
/// darkest just ahead of it (the comet tail of the Frame clock).
double frameTickBrightness(int i, int second) {
  final age = (second - i) % 60; // 0 = now, 59 = about to light up
  final left = (60 - age) / 60;
  return 0.1 + 0.9 * left * left;
}

class _FramePainter extends CustomPainter {
  const _FramePainter({
    required this.second,
    required this.ink,
    required this.scale,
  });

  final int second; // 0..59: the brightest tick
  final Color ink;
  final double scale; // tick size multiplier

  // Rounded square, drawn clockwise from the top centre.
  static Path _border(Rect r, double radius) {
    final c = r.center.dx;
    return Path()
      ..moveTo(c, r.top)
      ..lineTo(r.right - radius, r.top)
      ..arcToPoint(
        Offset(r.right, r.top + radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(r.right, r.bottom - radius)
      ..arcToPoint(
        Offset(r.right - radius, r.bottom),
        radius: Radius.circular(radius),
      )
      ..lineTo(r.left + radius, r.bottom)
      ..arcToPoint(
        Offset(r.left, r.bottom - radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(r.left, r.top + radius)
      ..arcToPoint(
        Offset(r.left + radius, r.top),
        radius: Radius.circular(radius),
      )
      ..lineTo(c, r.top);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(6);
    final metric = _border(rect, size.width * 0.16).computeMetrics().first;
    final tick = frameTickSize(scale);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = tick.width;
    for (var i = 0; i < 60; i++) {
      final t = metric.getTangentForOffset(metric.length * i / 60)!;
      final inward = Offset(-t.vector.dy, t.vector.dx); // clockwise path
      paint.color = ink.withValues(alpha: frameTickBrightness(i, second));
      canvas.drawLine(t.position, t.position + inward * tick.length, paint);
    }
  }

  // Tappable only on the tick strip, not the interior.
  @override
  bool? hitTest(Offset position) {
    const side = FrameClockFace._side;
    const outer = Rect.fromLTWH(0, 0, side, side);
    return outer.contains(position) && !outer.deflate(32).contains(position);
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.second != second || old.ink != ink || old.scale != scale;
}

/// Apple "Float": big bubbly numerals, hours over minutes, one pastel per digit.
class FloatClockFace extends StatelessWidget {
  const FloatClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.onPartTap,
  });

  final DateTime time;
  final StandbySettings settings;
  final PartTap? onPartTap;

  static const _pastels = [
    Color(0xFFFFB3C7),
    Color(0xFFFF9EBB),
    Color(0xFFFFE680),
    Color(0xFFC9B8F5),
  ];

  @override
  Widget build(BuildContext context) {
    final t = _clockText(time, settings);
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tap(onPartTap, ClockPart.hours, row(digits.sublist(0, h), 0)),
        _tap(onPartTap, ClockPart.minutes, row(digits.sublist(h), h)),
        if (t.suffix != null)
          _tap(
            onPartTap,
            ClockPart.detail,
            Text(
              t.suffix!,
              style: TextStyle(
                color: settings.detailInk,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

/// Apple "Minimal Mono": thin monospaced numerals, quiet and low-contrast.
class MonoClockFace extends StatelessWidget {
  const MonoClockFace({
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
    final t = _clockText(time, settings, seconds: settings.secondsVisible);
    return _TimeText(
      text: '${t.text}${t.suffix == null ? '' : ' ${t.suffix}'}',
      settings: settings,
      onPartTap: onPartTap,
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

class FlipClockFace extends StatelessWidget {
  const FlipClockFace({
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
    // a third tile for seconds when "Show seconds" is on
    final t = _clockText(time, settings, seconds: settings.secondsVisible);
    final parts = t.text.split(':');
    final colon = TextStyle(
      color: settings.colonInk,
      fontSize: 86,
      fontWeight: FontWeight.w900,
    );
    // one card per digit: the ones flip every tick, the tens only when they change
    Widget digits(String v, ClockPart role) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < v.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _FlipTile(
            key: ValueKey('${role.name}$i'),
            value: v[i],
            settings: settings,
            role: role,
          ),
        ],
      ],
    );
    Widget colonDots() => _tap(
      onPartTap,
      ClockPart.colon,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(':', style: colon),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _tap(onPartTap, ClockPart.hours, digits(parts[0], ClockPart.hours)),
            colonDots(),
            _tap(
              onPartTap,
              ClockPart.minutes,
              digits(parts[1], ClockPart.minutes),
            ),
            if (parts.length > 2) ...[
              colonDots(),
              _tap(
                onPartTap,
                ClockPart.detail,
                digits(parts[2], ClockPart.detail),
              ),
            ],
            if (t.suffix != null)
              _tap(
                onPartTap,
                ClockPart.detail,
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 8),
                  child: Text(
                    t.suffix!,
                    style: TextStyle(
                      color: settings.detailInk,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One flip-clock tile. When its value changes it flips like a real one: the
/// old top half folds down, then the new bottom half unfolds into place.
class _FlipTile extends StatefulWidget {
  const _FlipTile({
    super.key,
    required this.value,
    required this.settings,
    required this.role, // hours, minutes or detail (= seconds)
  });

  final String value;
  final StandbySettings settings;
  final ClockPart role;

  static const width = 88.0;
  static const height = 174.0;

  @override
  State<_FlipTile> createState() => _FlipTileState();
}

class _FlipTileState extends State<_FlipTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 460),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _previous = null);
        }
      });
  String? _previous; // the value being flipped away from

  @override
  void didUpdateWidget(_FlipTile old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value) return;
    if (MediaQuery.disableAnimationsOf(context)) return; // respect the setting
    _previous = old.value;
    _flip.forward(from: 0);
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  // The full tile showing [value]: the card, the digits, the centre seam.
  Widget _card(String value) {
    final theme = widget.settings.theme;
    // Color-block themes invert: ink tile, panel-colored digits.
    final onPanel = theme.panelColor != null;
    final tile = onPanel ? theme.clockColor : const Color(0xFF111116);
    final digits = onPanel
        ? theme.panelColor!
        : switch (widget.role) {
            ClockPart.minutes => widget.settings.minutesInk,
            ClockPart.detail => widget.settings.detailInk,
            _ => widget.settings.hoursInk,
          };
    return Container(
      width: _FlipTile.width,
      height: _FlipTile.height,
      decoration: BoxDecoration(
        color: tile,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              color: digits,
              fontSize: 92,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Container(height: 1.5, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // Top or bottom half of the tile for [value].
  Widget _half(String value, {required bool top}) => SizedBox(
    width: _FlipTile.width,
    height: _FlipTile.height / 2,
    child: ClipRect(
      child: Align(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        heightFactor: 0.5,
        child: _card(value),
      ),
    ),
  );

  Matrix4 _tilt(double angle) => Matrix4.identity()
    ..setEntry(3, 2, 0.004) // a little perspective
    ..rotateX(angle);

  @override
  Widget build(BuildContext context) {
    final old = _previous;
    if (old == null) return _card(widget.value);
    const half = _FlipTile.height / 2;
    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final t = _flip.value;
        final first = t < 0.5; // 1st half: old top folds; 2nd: new bottom opens
        return SizedBox(
          width: _FlipTile.width,
          height: _FlipTile.height,
          child: Stack(
            children: [
              // behind: the new top half and the old bottom half
              Positioned(
                top: 0,
                left: 0,
                child: _half(widget.value, top: true),
              ),
              Positioned(bottom: 0, left: 0, child: _half(old, top: false)),
              if (first)
                Positioned(
                  top: 0,
                  left: 0,
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: _tilt(-math.pi / 2 * (t / 0.5)),
                    child: _half(old, top: true),
                  ),
                )
              else
                Positioned(
                  top: half,
                  left: 0,
                  child: Transform(
                    alignment: Alignment.topCenter,
                    transform: _tilt(math.pi / 2 * (1 - (t - 0.5) / 0.5)),
                    child: _half(widget.value, top: false),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

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
        _tap(
          onPartTap,
          ClockPart.hours,
          Text(_numberWord(hour), style: _textStyle(settings, 72)),
        ),
        _tap(
          onPartTap,
          ClockPart.minutes,
          Text(
            _numberWord(time.minute),
            style: _textStyle(settings, 56).copyWith(
              color: settings.minutesColor == 0
                  ? settings.theme.clockSecondary
                  : settings.minutesInk,
            ),
          ),
        ),
        if (!settings.use24HourTime)
          _tap(
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

/// Two times only: this device's local time and one chosen city.
class WorldClockFace extends StatelessWidget {
  const WorldClockFace({
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
    final other = _zoneTime(time, settings.worldZone);
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
    final c = _clockText(t, settings);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tap(
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
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _TimeText(
              text: c.text,
              settings: settings,
              onPartTap: onPartTap,
              style: TextStyle(
                color: theme.clockColor,
                fontSize: 104,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (c.suffix != null)
              _tap(
                onPartTap,
                ClockPart.detail,
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    c.suffix!,
                    style: TextStyle(
                      color: settings.detailInk,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

bool _tzReady = false;

void _initZones() {
  if (_tzReady) return;
  tzdata.initializeTimeZones(); // lazy: only when the world clock is used
  _tzReady = true;
}

DateTime _zoneTime(DateTime now, String zoneId) {
  try {
    _initZones();
    return tz.TZDateTime.from(now.toUtc(), tz.getLocation(zoneId));
  } catch (_) {
    return now.toUtc(); // unknown zone id: show UTC rather than crash
  }
}

class AnalogClockFace extends StatelessWidget {
  const AnalogClockFace({
    super.key,
    required this.time,
    required this.settings,
  });

  final DateTime time;
  final StandbySettings settings;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AnalogClockPainter(time, settings),
        child: const SizedBox.square(dimension: 310),
      ),
    );
  }
}

class _AnalogClockPainter extends CustomPainter {
  _AnalogClockPainter(this.time, this.settings);

  final DateTime time;
  final StandbySettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final theme = settings.theme;
    // each part: a picked color, else the theme default
    final marks = settings.colonColor == 0
        ? theme.clockColor.withValues(alpha: 0.62)
        : Color(settings.colonColor);
    final hourInk = settings.hoursColor == 0
        ? theme.clockAccent
        : Color(settings.hoursColor);
    final minuteInk = settings.minutesColor == 0
        ? theme.clockColor
        : Color(settings.minutesColor);
    final secondInk = settings.detailColor == 0
        ? const Color(0xFFFF9F0A)
        : Color(settings.detailColor);
    final tickPaint = Paint()
      ..color = marks
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 60; i++) {
      final angle = (i / 60) * math.pi * 2;
      final inner = radius - (i % 5 == 0 ? 26 : 14);
      final outer = radius - 4;
      canvas.drawLine(
        center + Offset(math.sin(angle) * inner, -math.cos(angle) * inner),
        center + Offset(math.sin(angle) * outer, -math.cos(angle) * outer),
        tickPaint..strokeWidth = i % 5 == 0 ? 4 : 1.4,
      );
    }

    final hour = (time.hour % 12 + time.minute / 60) / 12;
    final minute = (time.minute + time.second / 60) / 60;
    _hand(
      canvas,
      center,
      radius * 0.42,
      hour,
      Paint()
        ..color = hourInk
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    _hand(
      canvas,
      center,
      radius * 0.68,
      minute,
      Paint()
        ..color = minuteInk
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    if (settings.secondsVisible) {
      _hand(
        canvas,
        center,
        radius * 0.8,
        time.second / 60,
        Paint()
          ..color = secondInk
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
      center,
      settings.secondsVisible ? 5 : 7,
      Paint()..color = settings.secondsVisible ? secondInk : hourInk,
    );
  }

  void _hand(
    Canvas canvas,
    Offset center,
    double length,
    double turn,
    Paint p,
  ) {
    final angle = turn * math.pi * 2;
    canvas.drawLine(
      center,
      center + Offset(math.sin(angle) * length, -math.cos(angle) * length),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _AnalogClockPainter oldDelegate) {
    return oldDelegate.time.minute != time.minute ||
        (settings.secondsVisible && oldDelegate.time.second != time.second) ||
        oldDelegate.settings != settings;
  }
}

/// 'H:MM[:SS]' as spans, each part in its own picked color: hours, the
/// colon, minutes, and (if shown) seconds. [taps] makes each part tappable.
TextSpan _timeSpans(
  String text,
  StandbySettings settings, {
  TextStyle? style,
  Map<ClockPart, GestureRecognizer>? taps,
  bool solidColon = false, // full-strength colon unless a color was picked
}) {
  final colon = solidColon && settings.colonColor == 0
      ? settings.hoursInk
      : settings.colonInk;
  final parts = text.split(':');
  if (parts.length < 2) return TextSpan(text: text, style: style);
  TextSpan span(String t, Color c, ClockPart part) => TextSpan(
    text: t,
    style: TextStyle(color: c),
    recognizer: taps?[part],
  );
  return TextSpan(
    style: style,
    children: [
      span(parts[0], settings.hoursInk, ClockPart.hours),
      span(':', colon, ClockPart.colon),
      span(parts[1], settings.minutesInk, ClockPart.minutes),
      if (parts.length > 2) ...[
        span(':', colon, ClockPart.colon),
        span(parts[2], settings.detailInk, ClockPart.detail),
      ],
    ],
  );
}

/// Time text whose hours / colon / minutes / seconds can each be tapped.
class _TimeText extends StatefulWidget {
  const _TimeText({
    required this.text,
    required this.settings,
    required this.style,
    this.onPartTap,
    this.solidColon = false,
  });

  final String text;
  final StandbySettings settings;
  final TextStyle style;
  final PartTap? onPartTap;
  final bool solidColon;

  @override
  State<_TimeText> createState() => _TimeTextState();
}

class _TimeTextState extends State<_TimeText> {
  final _taps = {for (final p in ClockPart.values) p: TapGestureRecognizer()};

  @override
  void dispose() {
    for (final r in _taps.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cb = widget.onPartTap;
    _taps.forEach((part, r) => r.onTap = cb == null ? null : () => cb(part));
    // Equal-width digits, and a box as wide as the widest possible reading
    // ("88:88:88"), so the clock never changes size as the seconds tick.
    final style = widget.style.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final ruler = TextPainter(
      text: TextSpan(
        text: widget.text.replaceAll(RegExp(r'\d'), '8'),
        style: style,
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = ruler.width;
    ruler.dispose();
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.center,
        child: Text.rich(
          _timeSpans(
            widget.text,
            widget.settings,
            style: style,
            taps: cb == null ? null : _taps,
            solidColon: widget.solidColon,
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}

({String text, String? suffix}) _clockText(
  DateTime time,
  StandbySettings settings, {
  bool seconds = false,
}) {
  final sec = seconds ? ':${_twoDigits(time.second)}' : '';
  if (settings.use24HourTime) {
    return (
      text: '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}$sec',
      suffix: null,
    );
  }
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return (
    text: '$hour:${_twoDigits(time.minute)}$sec',
    suffix: time.hour < 12 ? 'AM' : 'PM',
  );
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

TextStyle _textStyle(StandbySettings settings, double size) {
  return TextStyle(
    color: settings.hoursInk,
    fontSize: size,
    fontWeight: FontWeight.w900,
    height: 0.95,
    letterSpacing: 0,
  );
}

List<Shadow> _glow(Color color, double amount) {
  if (amount <= 0.01) return const [];
  return [
    Shadow(
      color: color.withValues(alpha: amount),
      blurRadius: 28 * amount,
    ),
  ];
}

String _numberWord(int value) {
  const words = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  if (value < 20) return words[value];
  const tens = {20: 'twenty', 30: 'thirty', 40: 'forty', 50: 'fifty'};
  final ten = value ~/ 10 * 10;
  final rest = value % 10;
  return rest == 0 ? tens[ten]! : '${tens[ten]} ${words[rest]}';
}
