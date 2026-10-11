import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/apple.dart';
import '../../../state/standby_controller.dart';
import 'mini_keyboard.dart';

/// Type a timer length on our own number pad. Digits slide in from the right,
/// like a microwave: 1 5 0 0 is 15:00. The timer behind it follows as you type.
class TimerEntry extends StatefulWidget {
  const TimerEntry({super.key, required this.controller, required this.onDone});

  final StandbyController controller;
  final VoidCallback onDone;

  @override
  State<TimerEntry> createState() => _TimerEntryState();
}

class _TimerEntryState extends State<TimerEntry> {
  // It opens on the timer's length, so you see what you are changing. The first
  // key you press starts a new number; backspace edits the one shown.
  late String _digits = _fromSeconds(widget.controller.settings.timerSeconds);
  bool _fresh = true;

  static String _fromSeconds(int seconds) {
    final v =
        seconds ~/ 3600 * 10000 + seconds % 3600 ~/ 60 * 100 + seconds % 60;
    return v == 0 ? '' : v.toString();
  }

  // HHMMSS, padded on the left
  String get _padded => _digits.padLeft(6, '0');

  int get _seconds {
    final p = _padded;
    return int.parse(p.substring(0, 2)) * 3600 +
        int.parse(p.substring(2, 4)) * 60 +
        int.parse(p.substring(4, 6));
  }

  void _type(String d) {
    if (_fresh) {
      _fresh = false;
      _digits = '';
    }
    final next = (_digits + d).replaceFirst(RegExp('^0+'), '');
    if (next.length > 6) return;
    _apply(next);
  }

  void _back() {
    _fresh = false;
    if (_digits.isEmpty) return;
    _apply(_digits.substring(0, _digits.length - 1));
  }

  void _apply(String digits) {
    setState(() => _digits = digits);
    if (_seconds > 0) widget.controller.timerSet(_seconds);
  }

  Widget _unit(String value, String unit, {required bool lit}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 160),
        // on top of the surrounding text style, so the app's font carries over
        style: DefaultTextStyle.of(context).style.copyWith(
          fontSize: 56,
          height: 1,
          fontWeight: FontWeight.w300,
          decoration: TextDecoration.none,
          color: Colors.white.withValues(alpha: lit ? 1 : 0.3),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          // the new digit rises into place as the old one lifts away
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.22), end: Offset.zero)
                  .animate(
                    CurvedAnimation(parent: animation, curve: easeOutStrong),
                  ),
              child: child,
            ),
          ),
          child: Text(value, key: ValueKey(value)),
        ),
      ),
      Text(unit, style: const TextStyle(color: Colors.white54, fontSize: 13)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final p = _padded;
    final live = _digits.length;
    final handle = SpringDockScope.maybeOf(context);
    // Swipe up or down anywhere on the time to go back (the X works too).
    final display = GestureDetector(
      behavior: HitTestBehavior.opaque,
      // the whole dock follows your finger down, like a sheet; a quick flick
      // up closes it too
      onVerticalDragUpdate: (d) => handle?.dragUpdate(d.delta.dy),
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (handle == null) {
          if (v.abs() > 250) widget.onDone();
        } else if (v < -250) {
          handle.dismiss();
        } else {
          handle.dragEnd(v);
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Semantics(
            label:
                '${int.parse(p.substring(0, 2))} hours '
                '${int.parse(p.substring(2, 4))} minutes '
                '${int.parse(p.substring(4, 6))} seconds',
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _unit(p.substring(0, 2), 'hour', lit: live > 4),
                  const SizedBox(width: 18),
                  _unit(p.substring(2, 4), 'min', lit: live > 2),
                  const SizedBox(width: 18),
                  _unit(p.substring(4, 6), 'second', lit: live > 0),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Swipe up or down to go back',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
    Widget pad(double? keyHeight) => _Rise(
      delay: 140,
      child: MiniNumberPad(
        keyHeight: keyHeight,
        onDigits: (d) => d.split('').forEach(_type),
        onBackspace: _back,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: LayoutBuilder(
        builder: (context, c) {
          // a wide window (landscape): the time on the left, the pad on the
          // right, using the whole screen
          if (c.maxWidth > c.maxHeight * 1.3) {
            return Row(
              children: [
                Expanded(child: _Rise(delay: 40, child: display)),
                const SizedBox(width: 24),
                Expanded(
                  child: Center(child: pad(min(60, (c.maxHeight - 16) / 4))),
                ),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: _Rise(delay: 40, child: display)),
              const SizedBox(height: 8),
              pad(null),
            ],
          );
        },
      ),
    );
  }
}

/// Arrives a beat after the dock does: fades in and rises a little, so the
/// parts of the screen settle one after another (30-80 ms apart) instead of
/// all at once.
class _Rise extends StatefulWidget {
  const _Rise({required this.delay, required this.child});

  final int delay;
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  // the wait is part of the animation (its first stretch does nothing), so no
  // timer is needed
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.delay + 320),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(
      parent: _c,
      curve: Interval(
        widget.delay / (widget.delay + 320),
        1,
        curve: easeOutStrong,
      ),
    );
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(t),
        child: widget.child,
      ),
    );
  }
}
