import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../../core/apple.dart';
import '../../../../domain/standby_models.dart';
import 'clock_text.dart';

/// Apple "Float": big bubbly numerals, one pastel per digit. Hours over
/// minutes in a tall panel, side by side (with a colon) in a wide one, gliding
/// between the two when the shape changes.
///
/// It floats: every digit sits at its own small random angle (a new one when
/// it changes), and the hours and the minutes sway with the phone as two
/// bodies joined by a spring, so each one feels the other: the minutes answer
/// first, the hours are pulled along, the colon rides between them.
///
/// Nothing moves around when a digit changes: every digit has the same fixed
/// slot, a new digit rises in while the old one fades, and the only width that
/// ever changes (a second hour digit) grows smoothly.
class FloatClockFace extends StatefulWidget {
  const FloatClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.onPartTap,
    this.stacked = true,
    this.tilt,
    this.random,
  });

  final DateTime time;
  final StandbySettings settings;
  final PartTap? onPartTap;

  /// hours over minutes (a tall panel) instead of side by side
  final bool stacked;

  /// how the phone is held, as accelerometer (x, y, z); the phone's own sensor
  /// unless a test gives one
  final Stream<(double, double, double)>? tilt;

  /// where the random angles come from (a test gives a fixed one)
  final math.Random? random;

  @override
  State<FloatClockFace> createState() => _FloatClockFaceState();
}

class _FloatClockFaceState extends State<FloatClockFace>
    with SingleTickerProviderStateMixin {
  // Apple's Float blues, one per digit in turn
  static const _blues = [Color(0xFF2E7CF6), Color(0xFF5CC8F7)];
  // digits overlap, and each is a little see-through, so where two meet you
  // see both (a lighter blend), as on Apple's
  static const _see = 0.88;
  static const _overlap = 0.68; // a digit's slot, as a share of its width

  static const _maxAngle = 0.07; // radians, about 4 degrees either way
  static const _swayPx = 40.0; // px a digit slides per radian it has turned

  // The two bodies: hours (0) and minutes (1). Each is pulled to where the
  // phone leans (spring k, damping c) and to the other one (coupling).
  static const _k = [220.0, 300.0]; // stiff: it answers within a blink
  static const _c = 15.0; // a little life left in it: one soft overshoot
  static const _coupling = 60.0;

  late final math.Random _random = widget.random ?? math.Random();
  final _angles = <double>[];
  final _chars = <String>[];

  final _pos = [0.0, 0.0];
  final _vel = [0.0, 0.0];
  double _target = 0;
  final _moved = ValueNotifier<int>(0); // a new frame of the springs
  late final Ticker _ticker = createTicker(_step);
  Duration _last = Duration.zero;

  StreamSubscription<(double, double, double)>? _sensor;
  bool _sideways = false;
  bool _still = false;

  // the widest digit, so every digit gets the same slot
  double? _slot;
  double _slotHeight = 0;
  TextStyle? _slotFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sideways = MediaQuery.orientationOf(context) == Orientation.landscape;
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _still && (_sensor != null || still)) return;
    _still = still;
    _sensor?.cancel();
    _sensor = null;
    if (still) {
      _target = 0; // reduced motion: the tilted digits stay, nothing sways
      _pos.fillRange(0, 2, 0);
      _vel.fillRange(0, 2, 0);
      _ticker.stop();
      return;
    }
    // the real sensor only exists on a phone (a PC has none: no sway there)
    final stream =
        widget.tilt ??
        (Platform.isAndroid || Platform.isIOS
            ? accelerometerEventStream(
                samplingPeriod: SensorInterval.uiInterval,
              ).map((e) => (e.x, e.y, e.z))
            : null);
    _sensor = stream?.listen(_onTilt, onError: (_) {}); // no sensor: no sway
  }

  void _onTilt((double, double, double) g) {
    // how far the phone is turned from upright, in its own plane (like a
    // steering wheel): the screen's sideways and upward axes. Sideways, the
    // phone's x is up (which landscape decides the sign of y).
    final across = _sideways ? (g.$1 >= 0 ? -g.$2 : g.$2) : g.$1;
    final up = _sideways ? g.$1.abs() : g.$2;
    final turned = math.atan2(across, up);
    // flat on a table there is no "up": fade out so it does not jitter
    final grip = (math.sqrt(across * across + up * up) / 5).clamp(0.0, 1.0);
    // the digits hang like weights and stay upright: they turn back against it
    final goal = (turned * 0.9).clamp(-0.45, 0.45) * grip;
    _target += (goal - _target) * 0.6; // a little smoothing for the jitter
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _step(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    const sub = 4; // small steps keep the springs stable
    final h = dt / sub;
    for (var i = 0; i < sub; i++) {
      final a0 =
          -_k[0] * (_pos[0] - _target) -
          _c * _vel[0] +
          _coupling * (_pos[1] - _pos[0]);
      final a1 =
          -_k[1] * (_pos[1] - _target) -
          _c * _vel[1] +
          _coupling * (_pos[0] - _pos[1]);
      _vel[0] += a0 * h;
      _vel[1] += a1 * h;
      _pos[0] += _vel[0] * h;
      _pos[1] += _vel[1] * h;
    }
    _moved.value++;
    final settled =
        _vel.every((v) => v.abs() < 0.0005) &&
        _pos.every((p) => (p - _target).abs() < 0.0005);
    if (settled) _ticker.stop();
  }

  @override
  void dispose() {
    _sensor?.cancel();
    _ticker.dispose();
    _moved.dispose();
    super.dispose();
  }

  // a digit gets a new random angle when it changes
  double _angleOf(int i, String char) {
    while (_angles.length <= i) {
      _angles.add(0);
      _chars.add('');
    }
    if (_chars[i] != char) {
      _chars[i] = char;
      _angles[i] = (_random.nextDouble() * 2 - 1) * _maxAngle;
    }
    return _angles[i];
  }

  double _slotWidth(TextStyle style) {
    if (_slot != null && _slotFor == style) return _slot!;
    var widest = 0.0;
    for (var d = 0; d < 10; d++) {
      final p = TextPainter(
        text: TextSpan(text: '$d', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      widest = math.max(widest, p.width);
      _slotHeight = p.height;
      p.dispose();
    }
    _slotFor = style;
    return _slot = widest;
  }

  /// One floating glyph: its own small angle, swaying with [body] (0 hours,
  /// 1 minutes, 2 the colon between them) by [depth].
  Widget _floating(int i, int body, double depth, Widget glyph, String char) {
    final base = _angleOf(i, char);
    return TweenAnimationBuilder<double>(
      // a new random angle eases in instead of jumping
      tween: Tween(end: base),
      duration: calm(context, const Duration(milliseconds: 500)),
      curve: easeOutStrong,
      builder: (context, angle, child) => ListenableBuilder(
        listenable: _moved,
        child: child,
        builder: (context, child) {
          final lean = body == 2 ? (_pos[0] + _pos[1]) / 2 : _pos[body];
          return Transform.translate(
            // they slide toward the low side as they turn back
            offset: Offset(-lean * _swayPx * depth, 0),
            child: Transform.rotate(angle: angle + lean * depth, child: child),
          );
        },
      ),
      child: glyph,
    );
  }

  @override
  Widget build(BuildContext context) {
    final time = widget.time;
    final settings = widget.settings;
    final t = clockText(time, settings);
    final parts = t.text.split(':');
    // a picked row color is used for the row, its digits in two shades;
    // otherwise Apple's blues
    Color colorAt(int i, bool minutesRow) {
      final picked = minutesRow ? settings.minutesColor : settings.hoursColor;
      final Color c;
      if (picked != 0) {
        c = i.isEven
            ? Color(picked)
            : Color.lerp(Color(picked), Colors.white, 0.35)!;
      } else {
        c = _blues[i % _blues.length];
      }
      return c.withValues(alpha: _see);
    }

    const base = TextStyle(
      fontFamily: 'Fredoka',
      fontSize: 170,
      height: 0.86,
      fontWeight: FontWeight.w700,
      fontVariations: [FontVariation('wght', 700)],
    );
    final widest = _slotWidth(DefaultTextStyle.of(context).style.merge(base));
    final slot = widest * _overlap;
    const depth = [1.0, 0.85]; // the second digit of a row floats a bit less

    Widget digit(
      int i,
      int body,
      int inRow,
      String char,
      Color color,
    ) => SizedBox(
      width: slot,
      height: _slotHeight,
      // a digit wider than its slot spills over the neighbours' (they overlap)
      child: OverflowBox(
        minWidth: widest,
        maxWidth: widest,
        child: _floating(
          i,
          body,
          depth[inRow],
          // the old digit fades out as the new one rises in
          AnimatedSwitcher(
            duration: calm(context, const Duration(milliseconds: 280)),
            switchInCurve: easeOutStrong,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: Text(
              char,
              key: ValueKey('$i$char'),
              style: base.copyWith(color: color),
            ),
          ),
          char,
        ),
      ),
    );

    Widget row(String text, int body, int offset) => AnimatedSize(
      // a second hour digit appearing (or going) grows the row smoothly
      duration: calm(context, const Duration(milliseconds: 350)),
      curve: easeOutStrong,
      // the first and last digit spill past their slots: leave room for that,
      // so the clock is scaled to fit what is drawn
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: (widest - slot) / 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var j = 0; j < text.length; j++)
              digit(
                // slots counted from the row's end, so the minutes' digits keep
                // their identity when the hours gain or lose a digit
                body * 2 + (text.length - 1 - j),
                body,
                j == text.length - 1 ? 1 : 0,
                text[j],
                colorAt(offset + j, body == 1),
              ),
          ],
        ),
      ),
    );

    final colonColor = settings.colonColor != 0
        ? Color(settings.colonColor)
        : Colors.white; // two white dots over where the digits meet
    Widget dot() => DecoratedBox(
      decoration: BoxDecoration(color: colonColor, shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 30),
    );
    return MorphLayout(
      stacked: widget.stacked,
      rowGap: -14,
      hours: tapPart(widget.onPartTap, ClockPart.hours, row(parts[0], 0, 0)),
      minutes: tapPart(
        widget.onPartTap,
        ClockPart.minutes,
        row(parts[1], 1, 2),
      ),
      // on one line a colon floats between them (it folds away when stacked)
      separator: tapPart(
        widget.onPartTap,
        ClockPart.colon,
        _floating(
          8,
          2,
          0.7,
          SizedBox(
            width: 30,
            height: 150,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [dot(), dot()],
            ),
          ),
          ':',
        ),
      ),
      trailing: t.suffix == null
          ? null
          : tapPart(
              widget.onPartTap,
              ClockPart.detail,
              // AM/PM floats too, a new angle when it changes (twice a day)
              _floating(
                9,
                2,
                0.9,
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
                t.suffix!,
              ),
            ),
    );
  }
}
