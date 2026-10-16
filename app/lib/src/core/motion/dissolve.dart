import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'motion.dart';

/// Shows [child]. When [present] turns from true to false (and [enabled]), the
/// old picture of the child breaks into small particles that drift up and away,
/// from left to right, while the new content is already in place, like the
/// "dissolve" of a slide or the Snap effect. When it turns from false to true,
/// the particles fly back in and put the new content together. Used when a
/// second city is removed or added. With reduce motion on, the change is
/// instant.
///
/// The old child is pictured once (toImageSync) and every particle is drawn by
/// one drawRawAtlas call per frame, so a few thousand of them cost very little.
class DissolveSwitcher extends StatefulWidget {
  const DissolveSwitcher({
    super.key,
    required this.present,
    required this.child,
    this.enabled = true,
    this.fadeIn = true,
    this.duration = const Duration(milliseconds: 1100),
  });

  /// whether there is something to show (a city is set)
  final bool present;
  final Widget child;

  /// false: no dissolve now, even if [present] just turned false
  final bool enabled;

  /// fade the content in when it comes back
  final bool fadeIn;
  final Duration duration;

  @override
  State<DissolveSwitcher> createState() => _DissolveSwitcherState();
}

class _DissolveSwitcherState extends State<DissolveSwitcher>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  _Particles? _particles;

  // coming in: the new content is hidden while its particles gather
  bool _assembling = false;
  bool _captured = false;

  @override
  void didUpdateWidget(DissolveSwitcher old) {
    super.didUpdateWidget(old);
    if (MediaQuery.disableAnimationsOf(context) || !widget.enabled) return;
    if (!old.present && widget.present) {
      // the new content is hidden (but drawn, faintly) for a frame so it can be
      // pictured; then its particles gather into it
      _assembling = true;
      _captured = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _gather());
      return;
    }
    if (!(old.present && !widget.present)) return;
    final box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary || !box.hasSize) return;
    final size = box.size;
    if (size.isEmpty) return;
    try {
      // the old picture, before this rebuild replaces what it shows
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final image = box.toImageSync(pixelRatio: dpr);
      _particles?.image.dispose();
      _particles = _Particles(image, size, dpr);
      _c.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _particles?.image.dispose();
          _particles = null;
        });
      });
    } catch (_) {
      _particles = null; // nothing to picture: just change
    }
  }

  void _gather() {
    if (!mounted || !_assembling) return;
    final box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary || !box.hasSize || box.size.isEmpty) {
      setState(() => _assembling = false);
      return;
    }
    try {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final image = box.toImageSync(pixelRatio: dpr);
      _particles?.image.dispose();
      setState(() {
        _particles = _Particles(image, box.size, dpr);
        _captured = true;
      });
      _c.value = 1; // every particle far away, then home
      _c.reverse().whenComplete(() {
        if (!mounted) return;
        setState(() {
          _assembling = false;
          _captured = false;
          _particles?.image.dispose();
          _particles = null;
        });
      });
    } catch (_) {
      setState(() => _assembling = false);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _particles?.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget inner = widget.child;
    if (widget.fadeIn) {
      inner = AnimatedSwitcher(
        duration: _assembling ? Duration.zero : calm(context, Motion.medium),
        switchInCurve: easeOutStrong,
        child: KeyedSubtree(key: ValueKey(widget.present), child: inner),
      );
    }
    // the picture is taken of the whole thing, outside the fade (one key only)
    final content = Opacity(
      // hidden while the particles gather (0.004 still draws, so it can be
      // pictured; a picture is taken inside, at full strength)
      opacity: !_assembling ? 1 : (_captured ? 0 : 0.004),
      child: RepaintBoundary(key: _boundary, child: inner),
    );
    final p = _particles;
    if (p == null) return content;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        content,
        // the old content, as particles, over the same place
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: IgnorePointer(
              child: SizedBox(
                width: p.size.width,
                height: p.size.height,
                child: CustomPaint(painter: _DissolvePainter(p, _c)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The cells of the old picture and a random number for each.
class _Particles {
  _Particles(this.image, this.size, this.dpr) {
    // about 2,500 cells at most, never smaller than 3 points
    cell = math.max(3.0, math.sqrt(size.width * size.height / 2500));
    cols = (size.width / cell).ceil();
    rows = (size.height / cell).ceil();
    final rnd = math.Random(7);
    count = cols * rows;
    seeds = Float32List(count * 3);
    for (var i = 0; i < count; i++) {
      seeds[i * 3] = rnd.nextDouble();
      seeds[i * 3 + 1] = rnd.nextDouble();
      seeds[i * 3 + 2] = rnd.nextDouble();
    }
    rects = Float32List(count * 4);
    final px = cell * dpr;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final i = r * cols + c;
        rects[i * 4] = c * px;
        rects[i * 4 + 1] = r * px;
        rects[i * 4 + 2] = math.min((c + 1) * px, image.width.toDouble());
        rects[i * 4 + 3] = math.min((r + 1) * px, image.height.toDouble());
      }
    }
    transforms = Float32List(count * 4);
    colors = Int32List(count);
  }

  final ui.Image image;
  final Size size;
  final double dpr;
  late final double cell;
  late final int cols, rows, count;
  late final Float32List seeds, rects, transforms;
  late final Int32List colors;
}

class _DissolvePainter extends CustomPainter {
  _DissolvePainter(this.p, this.t) : super(repaint: t);

  final _Particles p;
  final Animation<double> t;
  final _paint = Paint()..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    final time = t.value;
    final w = p.size.width;
    final cell = p.cell;
    final inv = 1 / p.dpr;
    for (var r = 0; r < p.rows; r++) {
      for (var c = 0; c < p.cols; c++) {
        final i = r * p.cols + c;
        final sx = p.seeds[i * 3],
            sy = p.seeds[i * 3 + 1],
            sr = p.seeds[i * 3 + 2];
        // a wave from the left, a little ragged; each cell then lives 55%
        final delay = (c * cell / w) * 0.4 + sx * 0.12;
        final local = ((time - delay) / 0.55).clamp(0.0, 1.0);
        final e = Curves.easeIn.transform(local);
        final x =
            c * cell +
            cell / 2 +
            e * (26 + sx * 46) +
            math.sin(e * 5 + sr * 6) * 6 * e;
        final y = r * cell + cell / 2 - e * (20 + sy * 58);
        final rot = (sr - 0.5) * 6 * e;
        final scale = (1 - 0.7 * e) * inv;
        final scos = math.cos(rot) * scale;
        final ssin = math.sin(rot) * scale;
        // RSTransform: the cell's own centre is the anchor
        final half = cell * p.dpr / 2;
        p.transforms[i * 4] = scos;
        p.transforms[i * 4 + 1] = ssin;
        p.transforms[i * 4 + 2] = x - (scos * half - ssin * half);
        p.transforms[i * 4 + 3] = y - (ssin * half + scos * half);
        final alpha = ((1 - e) * 255).round().clamp(0, 255);
        p.colors[i] = (alpha << 24) | 0x00FFFFFF;
      }
    }
    canvas.drawRawAtlas(
      p.image,
      p.transforms,
      p.rects,
      p.colors,
      BlendMode.modulate,
      null,
      _paint,
    );
  }

  @override
  bool shouldRepaint(_DissolvePainter old) => old.p != p || old.t != t;
}
