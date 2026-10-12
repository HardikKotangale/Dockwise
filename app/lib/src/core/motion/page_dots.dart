import 'dart:async';

import 'package:flutter/material.dart';

import 'glass.dart';
import 'motion.dart';

/// A page indicator (small dots, or the pages' own icons when [icons] is
/// given), and a way to move between the pages.
///
/// It is hidden until needed: they appear when the page changes (a swipe),
/// or when you tap where they are. Once showing, put a finger on them: a glass
/// strip lists every page and lights the one under your finger with its name.
/// Slide to the next dot and the next page is lit (Weather, then Calendar, then
/// Music, then Summary); lift your finger and you go to the lit page. A tap is
/// the same thing, just without sliding. A moment after the last touch they
/// fade away again, so nothing stays lit on an OLED.
class PageDots extends StatefulWidget {
  const PageDots({
    super.key,
    required this.labels,
    this.icons,
    required this.index,
    required this.bright,
    required this.onSelect,
  });

  final List<String> labels;

  /// one icon per page, shown in the glass strip next to its name
  final List<IconData>? icons;
  final int index;

  /// goes true when the page has just changed: show the dots for a moment
  final bool bright;
  final ValueChanged<int> onSelect;

  @override
  State<PageDots> createState() => _PageDotsState();
}

class _PageDotsState extends State<PageDots> {
  double get _slot => 30.0; // finger-friendly: the least HIG allows is 28
  final _link = LayerLink();
  OverlayEntry? _strip; // the glass strip, drawn above everything else
  int? _lit; // the page under the finger, or just chosen
  bool _down = false;
  bool _revealOnly = false; // this touch only brought the dots back
  bool _shown = false;
  Timer? _hide;
  Timer? _unlit;

  int _at(double dx, int count) => (dx / _slot).floor().clamp(0, count - 1);

  @override
  void initState() {
    super.initState();
    if (widget.bright) _reveal();
  }

  @override
  void didUpdateWidget(PageDots old) {
    super.didUpdateWidget(old);
    if (widget.bright && !old.bright) _reveal();
  }

  void _reveal([int ms = 2200]) {
    _hide?.cancel();
    if (!_shown) setState(() => _shown = true);
    _hide = Timer(Duration(milliseconds: ms), () {
      if (mounted && !_down) setState(() => _shown = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _unlit?.cancel();
    _strip?.remove();
    _strip = null;
    super.dispose();
  }

  // Lights page [i] (or none). The glass strip lives in the Overlay, so it is
  // drawn over whatever card is on screen, not behind it.
  void _light(int? i) {
    setState(() => _lit = i);
    if (i == null) {
      _strip?.remove();
      _strip = null;
    } else if (_strip == null) {
      _strip = OverlayEntry(
        builder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 8),
            showWhenUnlinked: false,
            child: IgnorePointer(
              child: _PageStrip(
                labels: widget.labels,
                lit: _lit ?? widget.index,
                current: widget.index,
              ),
            ),
          ),
        ),
      );
      Overlay.of(context).insert(_strip!);
    } else {
      _strip!.markNeedsBuild();
    }
  }

  void _down_(PointerDownEvent e, int n) {
    // hidden: the first touch only brings the dots back
    if (!_shown) {
      tick();
      _reveal();
      _revealOnly = true;
      return;
    }
    _revealOnly = false;
    _down = true;
    _unlit?.cancel();
    _reveal(60000);
    tick();
    _light(_at(e.localPosition.dx, n));
  }

  void _move(PointerMoveEvent e, int n) {
    if (!_down) return;
    final i = _at(e.localPosition.dx, n);
    if (i != _lit) {
      tick();
      _light(i);
    }
  }

  void _up(int n) {
    if (_revealOnly) {
      _revealOnly = false;
      return;
    }
    if (!_down) return;
    _down = false;
    final i = _lit;
    _reveal(); // the strip lingers a moment on where you went
    _unlit = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) _light(null);
    });
    if (i != null) {
      tick();
      if (i != widget.index) widget.onSelect(i);
    }
  }

  void _cancel() {
    _revealOnly = false;
    if (!_down) return;
    _down = false;
    _light(null);
    _reveal();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final n = widget.labels.length;
    final active = _lit ?? widget.index;
    Duration d(int ms) => still ? Duration.zero : Duration(milliseconds: ms);
    final icons = widget.icons;
    return Center(
      child: CompositedTransformTarget(
        link: _link,
        child: SizedBox(
          width: n * _slot,
          height: 30, // tall enough to hit (28 pt is the minimum)
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _down_(e, n),
            onPointerMove: (e) => _move(e, n),
            onPointerUp: (_) => _up(n),
            onPointerCancel: (_) => _cancel(),
            child: AnimatedOpacity(
              opacity: _shown ? 1 : 0,
              duration: d(_shown ? 160 : 400),
              curve: easeOutStrong,
              child: Row(
                children: [
                  for (var i = 0; i < n; i++)
                    // a labelled button for screen readers (the touch itself is
                    // handled by the Listener above)
                    Semantics(
                      button: true,
                      selected: i == active,
                      label: widget.labels[i],
                      onTap: () => widget.onSelect(i),
                      excludeSemantics: true,
                      child: SizedBox(
                        width: _slot,
                        height: 30, // tall enough to hit (28 pt is the minimum)
                        child: Center(
                          child: icons == null
                              ? AnimatedContainer(
                                  duration: d(200),
                                  curve: easeOutStrong,
                                  width: i == active ? 8 : 6,
                                  height: i == active ? 8 : 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(
                                      alpha: i == active ? 0.95 : 0.4,
                                    ),
                                  ),
                                )
                              : AnimatedScale(
                                  scale: i == active ? 1.15 : 0.9,
                                  duration: d(200),
                                  curve: easeOutStrong,
                                  child: Icon(
                                    icons[i],
                                    size: 16,
                                    color: Colors.white.withValues(
                                      alpha: i == active ? 0.95 : 0.4,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every page's name in one glass strip, the one you are heading to lit up: so you see where a tap, a hold or a slide will take you.
class _PageStrip extends StatelessWidget {
  const _PageStrip({
    required this.labels,
    required this.lit,
    required this.current,
  });

  final List<String> labels;
  final int lit;
  final int current;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final strip = Glass(
      radius: 99,
      blur: 18,
      opacity: 0.62,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++)
              AnimatedContainer(
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: easeOutStrong,
                padding: EdgeInsets.symmetric(
                  horizontal: i == lit ? 12 : 9,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: Colors.white.withValues(alpha: i == lit ? 0.24 : 0),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: i == lit ? 1 : (i == current ? 0.8 : 0.5),
                    ),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (still) return strip;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: easeOutStrong,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      ),
      child: strip,
    );
  }
}
