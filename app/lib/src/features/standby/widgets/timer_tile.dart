import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/apple.dart';
import '../../../core/palette.dart';
import '../../../domain/standby_models.dart';
import 'clock/flip_clock.dart';
import 'timer_track.dart';

/// The timer as a Summary tile: the time left, a thin track with the runner
/// (when there is room), and three small buttons. Tap the time to open the
/// timer's settings.
class TimerTile extends StatelessWidget {
  const TimerTile({
    super.key,
    required this.settings,
    required this.leftMs,
    required this.totalMs,
    required this.running,
    required this.started,
    required this.done,
    required this.onStart,
    required this.onPause,
    required this.onReset,
    required this.onAddMinute,
    required this.onOpen,
    this.onSwipe,
  });

  final StandbySettings settings;
  final int leftMs;
  final int totalMs;
  final bool running;
  final bool started;
  final bool done;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;
  final VoidCallback onAddMinute;
  final VoidCallback onOpen;

  /// swiped up or down on the time: the other style (digital / flip)
  final VoidCallback? onSwipe;

  List<String> get _parts {
    final secs = (leftMs / 1000).ceil();
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return [if (h > 0) '$h', two(m), two(s)];
  }

  String get _text => _parts.join(':');

  // The time as flip cards: on one line, or (a tall tile) minutes over seconds
  // (and hours on top), each as large as the width allows.
  Widget _flipCards(StandbySettings look, bool stacked, {bool wide = false}) {
    final parts = _parts;
    Widget group(int i) {
      final role = i == parts.length - 1 ? ClockPart.minutes : ClockPart.hours;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var d = 0; d < parts[i].length; d++) ...[
            if (d > 0) const SizedBox(width: 5),
            FlipCard(
              key: ValueKey('tile$i$d'),
              value: parts[i][d],
              settings: look,
              role: role,
              // a wide tile has room to spare: broader cards, not just bigger
              width: wide ? 128 : 78,
              height: 130,
              fontSize: wide ? 92 : 84,
              radius: 14,
            ),
          ],
        ],
      );
    }

    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            group(i),
          ],
        ],
      );
    }
    final out = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        out.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              ':',
              style: TextStyle(
                color: look.colonInk,
                fontSize: 70,
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        );
      }
      out.add(group(i));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: out);
  }

  Widget _digital(StandbySettings look, bool stacked) {
    final base = TextStyle(
      fontSize: 200,
      height: 0.95,
      fontWeight: FontWeight.w300,
      letterSpacing: -4,
      color: done ? Palette.red : look.hoursInk,
      fontFeatures: const [FontFeature.tabularFigures()],
      decoration: TextDecoration.none,
    );
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final p in _parts) Text(p, style: base)],
      );
    }
    return Text(_text, style: base);
  }

  @override
  Widget build(BuildContext context) {
    final look = settings.timerLook;
    final flip = settings.timerStyle == TimerStyle.flip;
    final figure = settings.timerFigureColor != 0
        ? Color(settings.timerFigureColor)
        : look.hoursInk;
    final progress = totalMs <= 0 ? 0.0 : (leftMs / totalMs).clamp(0.0, 1.0);
    final go = done
        ? ('Stop', Palette.redText, onReset)
        : running
        ? ('Pause', Palette.orange, onPause)
        : (started ? 'Resume' : 'Start', Palette.green, onStart);

    Widget buttons({required bool column, double height = 34}) {
      final kids = [
        _Mini(
          height: height,
          label: 'Reset',
          spoken: 'Reset timer',
          dim: !started,
          onTap: onReset,
        ),
        _Mini(
          height: height,
          label: '+1 min',
          spoken: 'Add one minute',
          onTap: onAddMinute,
        ),
        _Mini(
          height: height,
          label: go.$1,
          spoken: '${go.$1} timer',
          tint: go.$2,
          onTap: go.$3,
        ),
      ];
      return column
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < kids.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  kids[i],
                ],
              ],
            )
          : Row(
              children: [
                for (var i = 0; i < kids.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: kids[i]),
                ],
              ],
            );
    }

    Widget face(bool stacked, {bool wide = false}) => Semantics(
      label: 'Timer, $_text left',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        // up or down: the other style, like the weather tile
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0).abs() > 300) onSwipe?.call();
        },
        child: SizedBox.expand(
          // as big as the tile allows, not just as big as it was drawn
          child: LayoutBuilder(
            builder: (context, box) {
              final shown = AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: KeyedSubtree(
                  key: ValueKey('${settings.timerStyle.name}$stacked$wide'),
                  child: flip
                      ? _flipCards(look, stacked, wide: wide)
                      : _digital(look, stacked),
                ),
              );
              // a wide tile: the digital time is stretched wider too, up to
              // three times as wide as it is tall
              if (wide && !flip) {
                return Center(
                  child: SizedBox(
                    width: math.min(box.maxWidth, box.maxHeight * 3.0),
                    height: box.maxHeight,
                    child: FittedBox(fit: BoxFit.fill, child: shown),
                  ),
                );
              }
              return FittedBox(fit: BoxFit.contain, child: shown);
            },
          ),
        ),
      ),
    );

    Widget track(double height) => ExcludeSemantics(
      child: TimerTrack(
        height: height,
        kind: flip ? TrackKind.field : TrackKind.horse,
        progress: progress,
        color: figure,
        done: done,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, outer) => Padding(
          // less padding when the tile is squeezed
          padding: EdgeInsets.all(outer.maxHeight < 140 ? 7 : 12),
          child: LayoutBuilder(
            builder: (context, c) {
              // a short tile (the settings window is open and the panel is
              // squeezed): the time on top, small buttons in one row, all there
              final short = c.maxHeight < 120;
              // a wide tile: the time stretched across, the buttons beside it
              if (c.maxWidth > c.maxHeight * 1.9 && !short) {
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: face(false, wide: true)),
                          if (c.maxHeight > 140) ...[
                            const SizedBox(height: 6),
                            track(24),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: math.min(170, c.maxWidth * 0.26),
                      child: Center(child: buttons(column: true)),
                    ),
                  ],
                );
              }
              // a tall tile: minutes over seconds, filling the height
              final tall = c.maxHeight > c.maxWidth * 1.1;
              return Column(
                children: [
                  Expanded(child: face(tall)),
                  if (c.maxHeight > 150)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 8),
                      child: track(24),
                    ),
                  buttons(column: false, height: short ? 28 : 34),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({
    required this.label,
    required this.spoken,
    required this.onTap,
    this.tint,
    this.dim = false,
    this.height = 34,
  });

  final double height;
  final String label;
  final String spoken;
  final VoidCallback onTap;
  final Color? tint;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final ink = tint ?? Colors.white.withValues(alpha: dim ? 0.3 : 0.9);
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      child: Pressable(
        scale: 0.94,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            tick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: tint != null
                  ? tint!.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.1),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: ink,
                  fontSize: height < 30 ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
