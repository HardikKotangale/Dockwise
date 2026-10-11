import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Confetti and fireworks over the whole card from the moment [active] turns
/// on (the timer reached zero: touchdown) until it turns off again (Stop).
/// Nothing runs before or after, and nothing at all when animations are off.
class Celebration extends StatefulWidget {
  const Celebration({super.key, required this.active});

  final bool active;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _Confetti {
  _Confetti(math.Random r)
    : x = r.nextDouble(),
      delay = r.nextDouble() * 0.35,
      speed = 0.55 + r.nextDouble() * 0.5,
      size = 5 + r.nextDouble() * 6,
      sway = 10 + r.nextDouble() * 30,
      phase = r.nextDouble() * math.pi * 2,
      spin = (r.nextDouble() - 0.5) * 14,
      color = _palette[r.nextInt(_palette.length)];

  final double x, delay, speed, size, sway, phase, spin;
  final Color color;
}

class _Burst {
  _Burst(math.Random r, this.cx, this.cy, this.start)
    : angles = [
        for (var i = 0; i < 30; i++)
          i / 30 * math.pi * 2 + r.nextDouble() * 0.2,
      ],
      speeds = [for (var i = 0; i < 30; i++) 0.65 + r.nextDouble() * 0.35],
      color = _palette[r.nextInt(_palette.length)];

  final double cx, cy, start;
  final List<double> angles, speeds;
  final Color color;
}

const _palette = [
  Color(0xFFFFD60A),
  Color(0xFFFF453A),
  Color(0xFF0A84FF),
  Color(0xFF30D158),
  Color(0xFFFF9F0A),
  Colors.white,
];

class _CelebrationState extends State<Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );
  final _r = math.Random(11);
  late List<_Confetti> _confetti;
  late List<_Burst> _bursts;

  // a fresh scatter of confetti and fireworks for each round
  void _shuffle() {
    _confetti = [for (var i = 0; i < 80; i++) _Confetti(_r)];
    _bursts = [
      for (final s in const [0.04, 0.2, 0.38, 0.55])
        _Burst(
          _r,
          0.15 + _r.nextDouble() * 0.7,
          0.22 + _r.nextDouble() * 0.3,
          s,
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _shuffle();
    // it keeps going, round after round, until the timer is stopped
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.active && mounted) {
        setState(_shuffle);
        _c.forward(from: 0);
      }
    });
  }

  @override
  void didUpdateWidget(Celebration old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      if (!MediaQuery.disableAnimationsOf(context)) _c.forward(from: 0);
    } else if (!widget.active && old.active) {
      _c.reset();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          if (!_c.isAnimating) return const SizedBox.shrink();
          return CustomPaint(
            size: Size.infinite,
            painter: _CelebrationPainter(_c.value, _confetti, _bursts),
          );
        },
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter(this.t, this.confetti, this.bursts);

  final double t;
  final List<_Confetti> confetti;
  final List<_Burst> bursts;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final reach = math.min(w, h) * 0.34;
    // fireworks: sparks fly out, slow down, drop and fade
    for (final b in bursts) {
      final tt = ((t - b.start) / 0.32).clamp(0.0, 1.0);
      if (tt <= 0 || tt >= 1) continue;
      final out = Curves.easeOutCubic.transform(tt);
      final paint = Paint()
        ..color = b.color.withValues(alpha: (1 - tt) * 0.95)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3;
      for (var i = 0; i < b.angles.length; i++) {
        final d = b.speeds[i] * reach;
        final dx = math.cos(b.angles[i]);
        final dy = math.sin(b.angles[i]);
        final fall = reach * 0.35 * tt * tt;
        final head = Offset(
          b.cx * w + dx * d * out,
          b.cy * h + dy * d * out + fall,
        );
        final tail = Offset(
          b.cx * w + dx * d * out * 0.86,
          b.cy * h + dy * d * out * 0.86 + fall * 0.8,
        );
        canvas.drawLine(tail, head, paint);
      }
    }
    // confetti: tumbling pieces drifting down
    for (final p in confetti) {
      final prog = ((t - p.delay) / (1 - p.delay) * p.speed).clamp(0.0, 1.0);
      if (prog <= 0 || prog >= 1) continue;
      final y = -12 + math.pow(prog, 1.15) * (h + 24);
      final x = p.x * w + math.sin(prog * 7 + p.phase) * p.sway;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(prog * p.spin);
      // the piece turns edge-on as it tumbles
      final flip = math.cos(prog * p.spin * 1.7).abs().clamp(0.15, 1.0);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6 * flip,
        ),
        Paint()..color = p.color.withValues(alpha: 1 - prog * prog),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CelebrationPainter old) => old.t != t;
}
