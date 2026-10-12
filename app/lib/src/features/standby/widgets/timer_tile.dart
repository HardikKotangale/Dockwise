import 'package:flutter/material.dart';

import '../../../core/apple.dart';
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

  Widget _flipCards(StandbySettings look) {
    final parts = _parts;
    final out = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        out.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              ':',
              style: TextStyle(
                color: look.colonInk,
                fontSize: 60,
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        );
      }
      final role = i == parts.length - 1 ? ClockPart.minutes : ClockPart.hours;
      for (var d = 0; d < parts[i].length; d++) {
        if (d > 0) out.add(const SizedBox(width: 4));
        out.add(
          FlipCard(
            key: ValueKey('tile$i$d'),
            value: parts[i][d],
            settings: look,
            role: role,
            width: 70,
            height: 120,
            fontSize: 74,
            radius: 14,
          ),
        );
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: out);
  }

  @override
  Widget build(BuildContext context) {
    final look = settings.timerLook;
    final flip = settings.timerStyle == TimerStyle.flip;
    final time = look.hoursInk;
    final figure = settings.timerFigureColor != 0
        ? Color(settings.timerFigureColor)
        : time;
    final progress = totalMs <= 0 ? 0.0 : (leftMs / totalMs).clamp(0.0, 1.0);
    final go = done
        ? ('Stop', const Color(0xFFFF453A), onReset)
        : running
        ? ('Pause', const Color(0xFFFF9F0A), onPause)
        : (started ? 'Resume' : 'Start', const Color(0xFF30D158), onStart);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, c) {
            final roomy = c.maxHeight > 150;
            return Column(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Timer, $_text left',
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onOpen,
                      // up or down: the other style, like the weather tile
                      onVerticalDragEnd: (d) {
                        if ((d.primaryVelocity ?? 0).abs() > 300) {
                          onSwipe?.call();
                        }
                      },
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: KeyedSubtree(
                              key: ValueKey(settings.timerStyle),
                              child: flip
                                  ? _flipCards(look)
                                  : Text(
                                      _text,
                                      style: TextStyle(
                                        fontSize: 90,
                                        height: 1,
                                        fontWeight: FontWeight.w300,
                                        letterSpacing: -2,
                                        color: done
                                            ? const Color(0xFFFF453A)
                                            : time,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (roomy)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: ExcludeSemantics(
                      child: TimerTrack(
                        height: 24,
                        kind: settings.timerStyle == TimerStyle.flip
                            ? TrackKind.field
                            : TrackKind.horse,
                        progress: progress,
                        color: figure,
                        done: done,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: _Mini(
                        label: 'Reset',
                        spoken: 'Reset timer',
                        dim: !started,
                        onTap: onReset,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _Mini(
                        label: '+1',
                        spoken: 'Add one minute',
                        onTap: onAddMinute,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _Mini(
                        label: go.$1,
                        spoken: '${go.$1} timer',
                        tint: go.$2,
                        onTap: go.$3,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
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
  });

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
            height: 34,
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
                  fontSize: 13,
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
