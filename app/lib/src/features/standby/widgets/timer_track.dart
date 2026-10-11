import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What runs along the timer's track.
enum TrackKind { horse, field }

/// A thin track under the countdown with a small figure running along it as
/// the time goes: a horse towards a finish flag, or a player towards the end
/// zone. Both are drawn as a few strokes (no images), the legs follow how far
/// it has run, and nothing animates by itself: it only moves with the clock,
/// so it costs nothing while paused and next to nothing while running.
class TimerTrack extends StatelessWidget {
  const TimerTrack({
    super.key,
    required this.kind,
    required this.progress,
    required this.color,
    this.done = false,
    this.height = 44,
  });

  final TrackKind kind;

  /// 1 = just started (all the time left), 0 = finished
  final double progress;
  final Color color;
  final bool done;
  final double height;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress),
        // steady speed, so it glides between the one-second updates
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 1000),
        curve: Curves.linear,
        builder: (context, v, _) => CustomPaint(
          size: Size(double.infinity, height),
          painter: kind == TrackKind.horse
              ? _HorsePainter(v, color, done)
              : _FieldPainter(
                  v,
                  color,
                  done,
                  DefaultTextStyle.of(context).style,
                ),
        ),
      ),
    );
  }
}

Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeWidth = w;

// One leg with a knee that bends [bend] (+1 forward, -1 back). The foot goes
// round a loop: back along the ground, then up and forward to take the next
// step; [phase] is where it is in the stride.
void _step(
  Canvas canvas,
  Paint p,
  Offset hip,
  double phase, {
  required double reach,
  required double lift,
  required double bend,
  required double len,
  double upper = 3.4,
}) {
  final foot = Offset(
    hip.dx + reach * math.cos(phase),
    -lift * math.max(0, -math.sin(phase)),
  );
  final v = foot - hip;
  final d = math.min(v.distance, len * 2 - 0.01);
  final dir = v / v.distance;
  final mid = hip + dir * (d / 2);
  final h = math.sqrt(len * len - (d / 2) * (d / 2));
  final knee = mid - Offset(-dir.dy, dir.dx) * (h * bend);
  // thicker above the knee, thinner below, with a small hoof / shoe
  canvas.drawLine(hip, knee, p..strokeWidth = upper);
  canvas.drawLine(knee, foot, p..strokeWidth = upper * 0.68);
  canvas.drawCircle(foot, upper * 0.5, Paint()..color = p.color);
}

class _HorsePainter extends CustomPainter {
  _HorsePainter(this.progress, this.color, this.done);

  final double progress;
  final Color color;
  final bool done;

  static const _pad = 14.0;

  @override
  void paint(Canvas canvas, Size outer) {
    // drawn for a 44-high track; a shorter one just scales it
    final k = outer.height / 44;
    canvas.save();
    canvas.scale(k);
    final size = Size(outer.width / k, 44);
    _paint(canvas, size);
    canvas.restore();
  }

  void _paint(Canvas canvas, Size size) {
    final ground = size.height - 5;
    final w = size.width - _pad * 2;
    final ran = (1 - progress).clamp(0.0, 1.0);

    // the ground, and a finish flag at the end
    canvas.drawLine(
      Offset(_pad, ground),
      Offset(size.width - _pad, ground),
      _stroke(Colors.white.withValues(alpha: 0.14), 2),
    );
    final end = size.width - _pad;
    canvas.drawLine(
      Offset(end, ground),
      Offset(end, ground - 24),
      _stroke(Colors.white.withValues(alpha: 0.5), 2),
    );
    const cell = 4.0;
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        canvas.drawRect(
          Rect.fromLTWH(end + 1 + c * cell, ground - 24 + r * cell, cell, cell),
          Paint()
            ..color = (r + c).isEven
                ? Colors.white.withValues(alpha: done ? 1 : 0.7)
                : Colors.black,
        );
      }
    }

    final x = _pad + ran * (w - 18);
    final phase = x / 20 * math.pi; // the stride follows the distance run
    final sprinting = ran > 0 && ran < 1;
    final hop = sprinting ? math.sin(phase * 2).abs() : 0.0;
    final far = Color.lerp(color, Colors.black, 0.45)!;

    // a shadow that shrinks as it leaves the ground, and dust kicked up behind
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, ground + 1),
        width: 34 - 8 * hop,
        height: 4,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    if (sprinting) {
      for (var k = 0; k < 4; k++) {
        final t = (phase / math.pi + k * 0.25) % 1; // each puff lives one cycle
        canvas.drawCircle(
          Offset(x - 16 - t * 22, ground - 2 - t * 7),
          1.6 + t * 3.6,
          Paint()..color = Colors.white.withValues(alpha: 0.22 * (1 - t)),
        );
      }
    }

    canvas.save();
    canvas.translate(x, ground - hop * 2.4);
    final reach = sprinting ? 10.0 : 1.0;
    final lift = sprinting ? 6.5 : 0.0;
    void leg(double hx, double ph, double bend, Color c) => _step(
      canvas,
      _stroke(c, 1),
      Offset(hx, -13),
      phase + ph,
      reach: reach,
      lift: lift,
      bend: bend,
      len: 7.4,
    );
    // the legs on the far side, a little darker, then the body over them
    leg(-6, math.pi + 0.7, -1, far);
    leg(8, 0.7, 1, far);
    final sway = sprinting ? math.sin(phase * 2) * 3 : 0.0;
    final fill = Paint()..color = color;
    // tail and mane stream back in the wind
    final tail = Path()
      ..moveTo(-12, -20)
      ..quadraticBezierTo(-20, -22 + sway, -26, -13 + sway * 1.5);
    canvas.drawPath(tail, _stroke(far, 3.2));
    // barrel, chest and rump
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-1, -18), width: 27, height: 12),
      fill,
    );
    canvas.drawCircle(const Offset(9, -19), 6.4, fill);
    canvas.drawCircle(const Offset(-10, -18), 6, fill);
    // neck, head, ear, eye
    canvas.drawLine(
      const Offset(9, -21),
      const Offset(16, -31),
      _stroke(color, 7),
    );
    canvas.drawLine(
      const Offset(16, -31),
      const Offset(24, -26),
      _stroke(color, 5.4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(14, -33)
        ..lineTo(14.6, -37.5)
        ..lineTo(17.6, -33.4)
        ..close(),
      fill,
    );
    canvas.drawCircle(
      const Offset(20, -29),
      0.9,
      Paint()..color = Colors.black,
    );
    final mane = Path()
      ..moveTo(15, -35)
      ..quadraticBezierTo(8, -33 + sway * 0.5, 6, -24);
    canvas.drawPath(mane, _stroke(far, 2.4));
    // the legs on the near side
    leg(-8, math.pi, -1, color);
    leg(6, 0, 1, color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HorsePainter old) =>
      old.progress != progress || old.color != color || old.done != done;
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.progress, this.color, this.done, this.base);

  // the surrounding text style, so the label uses the app's font
  final TextStyle base;

  final double progress;
  final Color color;
  final bool done;

  static const _pad = 12.0;

  @override
  void paint(Canvas canvas, Size outer) {
    final k = outer.height / 44;
    canvas.save();
    canvas.scale(k);
    final size = Size(outer.width / k, 44);
    _paint(canvas, size);
    canvas.restore();
  }

  void _paint(Canvas canvas, Size size) {
    final w = size.width;
    final ground = size.height - 5;
    final field = RRect.fromRectAndRadius(
      Rect.fromLTRB(0, size.height - 17, w, size.height),
      const Radius.circular(6),
    );
    canvas.drawRRect(field, Paint()..color = const Color(0xFF14532D));
    // the end zone, and yard lines every ten percent
    final zone = w * 0.9;
    canvas.save();
    canvas.clipRRect(field);
    canvas.drawRect(
      Rect.fromLTRB(zone, size.height - 17, w, size.height),
      Paint()..color = color.withValues(alpha: 0.5),
    );
    for (var i = 1; i < 9; i++) {
      final lx = w * 0.1 * i;
      canvas.drawLine(
        Offset(lx, size.height - 17),
        Offset(lx, size.height),
        _stroke(Colors.white.withValues(alpha: i == 5 ? 0.5 : 0.22), 1.4),
      );
    }
    canvas.drawLine(
      Offset(zone, size.height - 17),
      Offset(zone, size.height),
      _stroke(Colors.white.withValues(alpha: 0.85), 2),
    );
    canvas.restore();

    final ran = (1 - progress).clamp(0.0, 1.0);
    final x = _pad + ran * (zone + 8 - _pad * 2);
    final phase = x / 15 * math.pi;
    final sprinting = ran > 0 && ran < 1;
    final swing = sprinting ? 1.0 : 0.12;
    final hop = sprinting ? math.sin(phase * 2).abs() : 0.0;
    final jersey = color;
    const pants = Colors.white;
    final far = Color.lerp(pants, Colors.black, 0.4)!;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, ground + 1),
        width: 18 - 4 * hop,
        height: 3.4,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    if (sprinting) {
      for (var k = 0; k < 3; k++) {
        final t = (phase / math.pi + k / 3) % 1;
        canvas.drawCircle(
          Offset(x - 9 - t * 16, ground - 1.5 - t * 5),
          1.3 + t * 2.6,
          Paint()..color = Colors.white.withValues(alpha: 0.25 * (1 - t)),
        );
      }
    }

    canvas.save();
    canvas.translate(x, ground - hop * 1.8);
    void leg(double ph, Color c) => _step(
      canvas,
      _stroke(c, 1),
      const Offset(-2, -13),
      phase + ph,
      reach: 7.5 * swing,
      lift: 7.5 * swing,
      bend: 1,
      len: 7.2,
      upper: 3.4,
    );
    const lean = 0.0;
    // far leg and far arm first, then the torso, then the near ones
    leg(math.pi, far);
    canvas.drawLine(
      Offset(2 + lean, -23),
      Offset(-3 + 6 * math.sin(phase + math.pi), -18),
      _stroke(far, 2.6),
    );
    // jersey and shoulders, leaning into the run
    canvas.drawLine(
      const Offset(-3, -14),
      const Offset(3, -25),
      _stroke(jersey, 6),
    );
    canvas.drawLine(
      const Offset(-2, -25),
      const Offset(6, -25),
      _stroke(jersey, 3.4),
    ); // shoulder pads
    // helmet with a face mask
    canvas.drawCircle(const Offset(5, -30), 4.3, Paint()..color = jersey);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(5.6, -29.4), radius: 3.4),
      -0.5,
      1.9,
      false,
      _stroke(Colors.white.withValues(alpha: 0.85), 0.9),
    );
    leg(0, pants);
    // the arm that carries the ball, tucked in
    canvas.drawLine(
      const Offset(3, -23),
      const Offset(8, -19),
      _stroke(jersey, 3),
    );
    canvas.save();
    canvas.translate(9.5, -19.5);
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 8.6, height: 5),
      Paint()..color = const Color(0xFFB45F2A),
    );
    canvas.drawLine(
      const Offset(-1.6, 0),
      const Offset(1.6, 0),
      _stroke(Colors.white, 0.8),
    ); // the laces
    canvas.restore();
    canvas.restore();

    if (done) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'TOUCHDOWN',
          style: base.copyWith(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            decoration: TextDecoration.none,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((zone - tp.width) / 2, 0));
    }
  }

  @override
  bool shouldRepaint(_FieldPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.done != done ||
      old.base != base;
}
