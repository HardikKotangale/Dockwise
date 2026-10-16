import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

/// What the animated backdrop shows for a WMO weather code.
enum Precip { none, rain, snow }

class SceneSpec {
  const SceneSpec({
    this.sun = false,
    this.moon = false,
    this.stars = false,
    this.clouds = 0,
    this.darkness = 0,
    this.precip = Precip.none,
    this.heavy = false,
    this.lightning = false,
    this.fog = false,
  });

  final bool sun;
  final bool moon;
  final bool stars;
  final int clouds; // 0..3 parallax layers
  final double darkness; // 0 white fluffy .. 1 storm grey
  final Precip precip;
  final bool heavy;
  final bool lightning;
  final bool fog;
}

/// Maps an Open-Meteo / WMO weather code (and day/night) to a scene.
SceneSpec sceneFor(int? code, bool isDay) {
  if (code == null || code == 0) {
    return isDay
        ? const SceneSpec(sun: true)
        : const SceneSpec(moon: true, stars: true);
  }
  if (code <= 2) {
    return isDay
        ? const SceneSpec(sun: true, clouds: 1)
        : const SceneSpec(moon: true, stars: true, clouds: 1);
  }
  if (code == 3) return const SceneSpec(clouds: 3, darkness: 0.3);
  if (code == 45 || code == 48) {
    return const SceneSpec(clouds: 1, darkness: 0.2, fog: true);
  }
  if (code >= 51 && code <= 57) {
    return const SceneSpec(clouds: 2, darkness: 0.45, precip: Precip.rain);
  }
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) {
    return const SceneSpec(
      clouds: 3,
      darkness: 0.6,
      precip: Precip.rain,
      heavy: true,
    );
  }
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
    return const SceneSpec(clouds: 2, darkness: 0.15, precip: Precip.snow);
  }
  return const SceneSpec(
    clouds: 3,
    darkness: 0.9,
    precip: Precip.rain,
    heavy: true,
    lightning: true,
  );
}

/// Animated weather backdrop. Like Apple's: when it appears (the card swiped
/// in, new weather, back to the app) the rain, snow and clouds move for
/// [playFor], slow down and come to rest, then it is a still picture that
/// costs nothing. A card that is sliding in waits for [settleFirst] before it
/// moves, so the slide and the scene never compete for the same frames. One painter; 20 fps on a phone, every frame the screen shows on a
/// computer; never moving when animations are disabled.
class WeatherScene extends StatefulWidget {
  const WeatherScene({super.key, required this.spec});

  final SceneSpec spec;

  static const playFor = Duration(seconds: 2);

  /// About how long a card takes to slide in (Motion.slow and a little).
  static const settleFirst = Duration(milliseconds: 450);

  @override
  State<WeatherScene> createState() => WeatherSceneState();
}

class WeatherSceneState extends State<WeatherScene>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // Phones: 20 fps (battery). A computer: every frame the screen shows, with
  // no limit (60, 120, 270 Hz...). The scene moves on the screen's own clock
  // (a Ticker), not on a timer. The heavy sky is a picture drawn once, so a
  // frame costs only the rain, snow and lightning.
  static const _phone = Duration(milliseconds: 50);

  static bool get _onComputer => const {
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  }.contains(defaultTargetPlatform);
  // the end of the play slows down to rest instead of freezing
  static const _easeOut = 700;
  Duration _frame = _phone;
  bool _still = false; // animations disabled
  final _time = ValueNotifier<double>(0);
  // the slow layers (sky, clouds, fog) are drawn at this time: it only moves
  // when a play ends, so during the play they stay one cached picture
  final _restTime = ValueNotifier<double>(0);
  final _cache = SnapshotController(allowSnapshotting: true);
  Ticker? _ticker;
  int _playedMs = 0;
  bool _quiet = true; // at rest (set false while it plays)

  Timer? _wait;

  /// Plays the scene from where it rests, for [WeatherScene.playFor], after
  /// [after] (the card arriving).
  void _play({Duration after = Duration.zero}) {
    _stop();
    if (_still) return;
    if (after > Duration.zero) {
      _wait = Timer(after, _play);
      return;
    }
    _playedMs = 0;
    if (_quiet) setState(() => _quiet = false);
    final total = WeatherScene.playFor.inMilliseconds;
    var last = Duration.zero;
    _ticker = createTicker((elapsed) {
      // a phone keeps to its slow rate; a computer takes every frame
      if (_frame > Duration.zero && elapsed - last < _frame) return;
      final dt = (elapsed - last).inMicroseconds / 1000; // ms since the last
      last = elapsed;
      _playedMs = elapsed.inMilliseconds;
      final left = total - _playedMs;
      if (left <= 0) {
        _restTime.value = _time.value; // the sky catches up, once
        if (mounted) setState(() => _quiet = true);
        return _stop();
      }
      // the scene moves at the same speed whatever the frame rate
      final speed = left < _easeOut ? left / _easeOut : 1.0;
      _time.value += dt / 1000 * speed;
    })..start();
  }

  void _stop() {
    _wait?.cancel();
    _wait = null;
    _ticker?.dispose();
    _ticker = null;
  }

  /// Moving right now (false once it has come to rest).
  bool get playing => _ticker != null || _wait != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final frame = _onComputer ? Duration.zero : _phone;
    final still = MediaQuery.disableAnimationsOf(context);
    final changed = frame != _frame || still != _still;
    _frame = frame;
    _still = still;
    if (!_started) {
      _started = true;
      _play(after: WeatherScene.settleFirst); // the card just appeared
    } else if (changed && _ticker != null) {
      _play(); // mid-play: carry on at the new rate (or stop if still)
    }
  }

  @override
  void didUpdateWidget(WeatherScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec) _play(); // the weather changed
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    state == AppLifecycleState.resumed ? _play() : _stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _time.dispose();
    _restTime.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Three layers. In a second of play the sky hardly moves, but its soft
    // shapes (the sun's glow, clouds, fog: big gradients over the whole card)
    // are most of the drawing. So they are drawn once into a picture that is
    // reused every frame, at half resolution: soft gradients look the same,
    // for a quarter of the work. The sharp sky (stars, the moon's edge) is
    // drawn at full resolution under it, and only rain, snow and lightning
    // are drawn again on each frame.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, box) {
          // The soft sky is a picture of about 0.35 megapixels at most (half the
          // screen's density on a small card, less on a big one): its shapes are
          // blurry anyway, and drawing it again at every new size (a dock opening
          // beside the card) is the heaviest thing the weather does.
          final area = box.maxWidth * box.maxHeight;
          final soft = area <= 0
              ? dpr / 2
              : math.min(dpr / 2, math.max(0.2, math.sqrt(350000 / area)));
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_Layer.sharp.has(widget.spec))
                CustomPaint(
                  painter: _ScenePainter(widget.spec, _time, _Layer.sharp),
                  size: Size.infinite,
                ),
              MediaQuery(
                data: MediaQuery.of(context).copyWith(devicePixelRatio: soft),
                child: SnapshotWidget(
                  controller: _cache,
                  mode: SnapshotMode.permissive,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _ScenePainter(
                        widget.spec,
                        _restTime,
                        _Layer.soft,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
              if (_Layer.weather.has(widget.spec))
                CustomPaint(
                  painter: _ScenePainter(
                    widget.spec,
                    _time,
                    _Layer.weather,
                    quiet: _quiet,
                  ),
                  size: Size.infinite,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The layers of a scene, back to front: the sharp sky (stars, moon), the
/// soft sky (sun glow, clouds, fog) and the quick weather (rain, snow,
/// lightning).
enum _Layer {
  sharp,
  soft,
  weather;

  bool has(SceneSpec spec) => switch (this) {
    sharp => spec.stars || spec.moon,
    soft => true,
    weather => spec.precip != Precip.none || spec.lightning,
  };
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.spec, this.time, this.layer, {this.quiet = false})
    : super(repaint: time);

  final SceneSpec spec;
  final ValueNotifier<double> time;
  final _Layer layer;

  /// the scene has come to rest: no bolt may be caught mid-flash
  final bool quiet;

  // Fixed pseudo-random seeds so particles are stable between frames.
  static final _rnd = math.Random(11);
  static final _seeds = List.generate(
    120,
    (_) => (_rnd.nextDouble(), _rnd.nextDouble(), _rnd.nextDouble()),
  );

  // One unit-radius soft disc per tone, reused everywhere by scaling the
  // canvas (no per-frame shader allocation).
  static final Map<int, ui.Shader> _discs = {};
  static ui.Shader _disc(Color c) => _discs.putIfAbsent(
    c.toARGB32(),
    () => ui.Gradient.radial(
      Offset.zero,
      1,
      [c, c.withValues(alpha: 0)],
      const [0.0, 1.0],
    ),
  );

  final _paint = Paint();

  /// Soft round blob centred at [p]; [alpha] modulates the shared shader.
  void _blob(
    Canvas canvas,
    Offset p,
    double rx,
    double ry,
    Color c,
    double alpha,
  ) {
    _paint
      ..shader = _disc(c)
      ..color = Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0));
    canvas
      ..save()
      ..translate(p.dx, p.dy)
      ..scale(rx, ry)
      ..drawCircle(Offset.zero, 1, _paint)
      ..restore();
    _paint.shader = null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    if (layer == _Layer.sharp) {
      if (spec.stars) _stars(canvas, size, t);
      if (spec.moon) _moon(canvas, size);
      return;
    }
    if (layer == _Layer.weather) {
      switch (spec.precip) {
        case Precip.rain:
          _rain(canvas, size, t);
        case Precip.snow:
          _snow(canvas, size, t);
        case Precip.none:
      }
      if (spec.lightning && !quiet) _lightning(canvas, size, t);
      return;
    }
    if (spec.sun) _sun(canvas, size, t);
    for (var layer = 0; layer < spec.clouds; layer++) {
      _clouds(canvas, size, t, layer);
    }
    if (spec.fog) _fog(canvas, size, t);
  }

  // ---- sky bodies -------------------------------------------------------

  // Apple-style sun: a luminous orb in a wide warm bloom, with a few broad,
  // very faint light shafts that fade out and breathe. No hard lines.
  void _sun(Canvas canvas, Size size, double t) {
    final c = Offset(size.width * 0.8, size.height * 0.2);
    final r = size.shortestSide * 0.1;
    final breathe = 0.5 + 0.5 * math.sin(t * 0.55);
    // sunlight washing across the whole card from the corner
    _blob(
      canvas,
      c,
      size.width * 1.25,
      size.width * 1.25,
      const Color(0xFFFFC76B),
      0.2 + 0.05 * breathe,
    );
    // soft shafts: each is a wedge that fades with distance (unit shader,
    // scaled), drawn 3x with narrowing width so the edges are feathered
    _paint.shader = _disc(const Color(0xFFFFF3D0));
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(size.shortestSide * 1.1, size.shortestSide * 1.1);
    for (var i = 0; i < 7; i++) {
      final base = t * 0.025 + i * (math.pi * 2 / 7) + 0.4;
      final life = 0.55 + 0.45 * math.sin(t * 0.4 + i * 1.7);
      for (var layer = 0; layer < 3; layer++) {
        final half = (0.11 - layer * 0.034) * (0.85 + 0.3 * math.sin(i * 2.3));
        final path = Path()
          ..moveTo(0, 0)
          ..lineTo(math.cos(base - half), math.sin(base - half))
          ..lineTo(math.cos(base + half), math.sin(base + half))
          ..close();
        _paint.color = Colors.white.withValues(alpha: 0.055 * life);
        canvas.drawPath(path, _paint);
      }
    }
    canvas.restore();
    _paint.shader = null;
    // warm halo, bright core, white-hot centre
    _blob(canvas, c, r * 5, r * 5, const Color(0xFFFFD98A), 0.5);
    _blob(canvas, c, r * 2.6, r * 2.6, const Color(0xFFFFF0C0), 0.7);
    _blob(canvas, c, r * 1.25, r * 1.25, const Color(0xFFFFF6D8), 1);
    _blob(canvas, c, r * 0.85, r * 0.85, Colors.white, 1);
  }

  // A moon the way Apple draws it: a wide cool glow, the dark side faintly
  // there (earthshine), and a soft-lit crescent with a gentle edge.
  void _moon(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.8, size.height * 0.2);
    final r = size.shortestSide * 0.085;
    _blob(canvas, c, r * 7, r * 7, const Color(0xFF8FA8FF), 0.14);
    _blob(canvas, c, r * 3.6, r * 3.6, const Color(0xFFBFD0FF), 0.3);
    _paint
      ..shader = null
      ..color = const Color(0xFFBFD0FF).withValues(alpha: 0.1);
    canvas.drawCircle(c, r, _paint);
    final crescent = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      Path()..addOval(
        Rect.fromCircle(
          center: c + Offset(r * 0.55, -r * 0.2),
          radius: r * 0.9,
        ),
      ),
    );
    _paint
      ..color = const Color(0xFFFFF4D6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8);
    canvas.drawPath(crescent, _paint);
    _paint.maskFilter = null;
  }

  void _stars(Canvas canvas, Size size, double t) {
    _paint.shader = null;
    for (var i = 0; i < 36; i++) {
      final s = _seeds[i];
      final tw =
          0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 3 * (0.5 + s.$3) + s.$3 * 20));
      _paint.color = Colors.white.withValues(alpha: 0.75 * tw);
      canvas.drawCircle(
        Offset(s.$1 * size.width, s.$2 * size.height * 0.7),
        0.7 + s.$3 * 1.4,
        _paint,
      );
    }
  }

  // ---- clouds -------------------------------------------------------------

  // Volumetric billows: a shaded underside, then a lit top, per puff. Three
  // parallax layers: far = smaller/slower/fainter, near = bigger/faster.
  void _clouds(Canvas canvas, Size size, double t, int layer) {
    final scale = 0.8 + layer * 0.35;
    final speed = 0.004 + layer * 0.004;
    for (var i = 0; i < 3; i++) {
      final s = _seeds[60 + layer * 5 + i];
      final x = ((s.$1 + t * speed + i * 0.4) % 1.6 - 0.3) * size.width;
      final y =
          size.height * (0.1 + layer * 0.15 + s.$2 * 0.1) +
          math.sin(t * 0.1 + s.$3 * 6) * size.height * 0.008;
      _cloud(
        canvas,
        Offset(x, y),
        size.shortestSide * 0.12 * scale,
        spec.darkness,
        0.7 + layer * 0.15,
      );
    }
  }

  static const _puffs = [
    (-1.8, 0.25, 0.8),
    (-1.0, -0.1, 1.0),
    (-0.1, -0.45, 1.2),
    (0.9, -0.15, 1.05),
    (1.7, 0.2, 0.85),
    (0.0, 0.35, 1.1),
  ];

  void _cloud(Canvas canvas, Offset c, double r, double dark, double vis) {
    final shade = Color.lerp(
      const Color(0xFF8FA3BD),
      const Color(0xFF1F2430),
      dark,
    )!;
    final light = Color.lerp(Colors.white, const Color(0xFFB7BFCC), dark)!;
    // underside first
    for (final p in _puffs) {
      _blob(
        canvas,
        c + Offset(p.$1 * r, (p.$2 + 0.28) * r),
        r * p.$3 * 1.5,
        r * p.$3 * 1.0,
        shade,
        (0.3 + dark * 0.3) * vis,
      );
    }
    // sunlit top
    for (final p in _puffs) {
      _blob(
        canvas,
        c + Offset(p.$1 * r, (p.$2 - 0.05) * r),
        r * p.$3 * 1.35,
        r * p.$3 * 0.95,
        light,
        (0.36 - dark * 0.18) * vis,
      );
    }
  }

  void _fog(Canvas canvas, Size size, double t) {
    for (var i = 0; i < 4; i++) {
      final y = size.height * (0.25 + i * 0.17);
      final dx = math.sin(t * 0.07 + i * 2) * size.width * 0.14;
      _blob(
        canvas,
        Offset(size.width * 0.5 + dx, y),
        size.width * 0.9,
        size.height * 0.09,
        Colors.white,
        0.2,
      );
    }
  }

  // ---- precipitation ------------------------------------------------------

  // Two depths of streaks, plus ripples where the rain lands.
  void _rain(Canvas canvas, Size size, double t) {
    final n = spec.heavy ? 70 : 38;
    _paint.shader = null;
    for (var i = 0; i < n; i++) {
      final s = _seeds[i];
      final near = s.$3 > 0.55;
      final fall = near ? 1.0 : 0.65;
      final y =
          ((s.$2 + t * fall * (0.5 + s.$3 * 0.3)) % 1.1 - 0.05) * size.height;
      final x = s.$1 * size.width - y * 0.16;
      final len = size.height * (near ? 0.06 : 0.035);
      _paint
        ..color = Colors.white.withValues(alpha: near ? 0.5 : 0.25)
        ..strokeWidth = near ? 1.5 : 1.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, y), Offset(x - len * 0.18, y + len), _paint);
    }
    // ripples near the bottom edge
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 9; i++) {
      final s = _seeds[80 + i];
      final p = (t * 1.1 + s.$3 * 3) % 1;
      final rr = 3 + 15 * p;
      _paint.color = Colors.white.withValues(alpha: 0.32 * (1 - p));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(s.$1 * size.width, size.height * (0.93 + s.$2 * 0.05)),
          width: rr * 2,
          height: rr * 0.55,
        ),
        _paint,
      );
    }
    _paint.style = PaintingStyle.fill;
  }

  // Far flakes are tiny and crisp; near flakes are big, soft and blurry (depth
  // of field), and they drift slowly side to side.
  void _snow(Canvas canvas, Size size, double t) {
    for (var i = 0; i < 80; i++) {
      final s = _seeds[i % _seeds.length];
      final near = s.$3 > 0.62;
      final speed = near ? 0.07 + s.$3 * 0.04 : 0.03 + s.$3 * 0.04;
      final y = ((s.$2 + t * speed + i * 0.013) % 1.08 - 0.04) * size.height;
      final sway = math.sin(t * (0.4 + s.$3) + s.$2 * 9) * (near ? 20 : 9);
      final x = ((s.$1 * 7.31 + i * 0.137) % 1) * size.width + sway;
      if (near) {
        _blob(
          canvas,
          Offset(x, y),
          4 + s.$3 * 4,
          4 + s.$3 * 4,
          Colors.white,
          0.75,
        );
      } else {
        _paint
          ..shader = null
          ..color = Colors.white.withValues(alpha: 0.6);
        canvas.drawCircle(Offset(x, y), 0.9 + s.$3 * 1.3, _paint);
      }
    }
  }

  // Sky flash plus a jagged bolt with a glow, every ~7 seconds.
  void _lightning(Canvas canvas, Size size, double t) {
    final cycle = (t / 7).floor();
    final p = t % 7;
    final flash = p < 0.14
        ? 1 - p / 0.14
        : (p > 0.3 && p < 0.42 ? 0.7 * (1 - (p - 0.3) / 0.12) : 0.0);
    if (flash <= 0) return;
    _paint
      ..shader = null
      ..color = Colors.white.withValues(alpha: 0.14 * flash);
    canvas.drawRect(Offset.zero & size, _paint);
    // bolt: deterministic zigzag per cycle
    final r = math.Random(cycle * 31 + 5);
    var x = size.width * (0.25 + r.nextDouble() * 0.5);
    var y = size.height * 0.08;
    final path = Path()..moveTo(x, y);
    while (y < size.height * 0.62) {
      x += (r.nextDouble() - 0.5) * size.width * 0.12;
      y += size.height * (0.06 + r.nextDouble() * 0.05);
      path.lineTo(x, y);
    }
    _paint
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8
      ..color = const Color(0xFFBFD0FF).withValues(alpha: 0.22 * flash);
    canvas.drawPath(path, _paint);
    _paint
      ..strokeWidth = 2.2
      ..color = Colors.white.withValues(alpha: 0.95 * flash);
    canvas.drawPath(path, _paint);
    _paint.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.spec != spec ||
      old.layer != layer ||
      old.time != time ||
      old.quiet != quiet;
}
