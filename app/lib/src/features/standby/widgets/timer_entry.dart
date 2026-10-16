import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        LogicalKeyboardKey;

import '../../../core/apple.dart';
import '../../../core/key_capture.dart';
import '../../../state/standby_controller.dart';
import 'key_caps.dart';
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
  bool _help = false; // computer: ? or F1 shows the keys

  // A keyboard types here too: the number keys (top row or keypad) enter
  // digits, Backspace or Delete takes one back, Enter is done. Esc still
  // closes the dock, through the screen.
  @override
  void initState() {
    super.initState();
    KeyCapture.take();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    KeyCapture.release();
    super.dispose();
  }

  static final _digitKeys = {
    for (var i = 0; i <= 9; i++) ...{
      LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i): '$i',
      LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + i): '$i',
    },
  };

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;
    final digit = _digitKeys[key];
    if (digit != null) {
      _type(digit);
      return true;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _back();
      return true;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.question ||
            key == LogicalKeyboardKey.slash ||
            key == LogicalKeyboardKey.f1)) {
      setState(() => _help = !_help);
      return true;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      widget.onDone();
      return true;
    }
    return false;
  }

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

  Widget _unit(
    String value,
    String unit, {
    required bool lit,
    double size = 56,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedDefaultTextStyle(
        duration: Motion.quick,
        // on top of the surrounding text style, so the app's font carries over
        style: DefaultTextStyle.of(context).style.copyWith(
          fontSize: size,
          height: 1,
          fontWeight: FontWeight.w300,
          decoration: TextDecoration.none,
          color: Colors.white.withValues(alpha: lit ? 1 : 0.3),
        ),
        child: AnimatedSwitcher(
          duration: Motion.fast,
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
      Text(
        unit,
        style: TextStyle(color: Colors.white54, fontSize: size > 56 ? 16 : 13),
      ),
    ],
  );

  // ---- a computer: no pad, just the time, a few presets and the keys ----

  static const _presets = [
    (60, '1 min'),
    (300, '5 min'),
    (600, '10 min'),
    (900, '15 min'),
    (1800, '30 min'),
    (3600, '1 hr'),
  ];

  void _preset(int seconds) {
    tick();
    _fresh = true; // the next key starts a new number
    setState(() => _digits = _fromSeconds(seconds));
    widget.controller.timerSet(seconds);
  }

  // 00h 00m 00s: big light figures with the unit as a small suffix, the way
  // Apple's own timer reads. Figures already typed are bright, the rest dim.
  Widget _figure(String value, String suffix, {required bool lit}) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      AnimatedDefaultTextStyle(
        duration: Motion.quick,
        style: DefaultTextStyle.of(context).style.copyWith(
          fontSize: 128,
          height: 1,
          fontWeight: FontWeight.w200,
          letterSpacing: -2,
          fontFeatures: const [FontFeature.tabularFigures()],
          decoration: TextDecoration.none,
          color: Colors.white.withValues(alpha: lit ? 1 : 0.22),
        ),
        child: AnimatedSwitcher(
          duration: Motion.fast,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.16), end: Offset.zero)
                  .animate(
                    CurvedAnimation(parent: animation, curve: easeOutStrong),
                  ),
              child: child,
            ),
          ),
          child: Text(value, key: ValueKey(value)),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        suffix,
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: Colors.white.withValues(alpha: lit ? 0.6 : 0.2),
          decoration: TextDecoration.none,
        ),
      ),
    ],
  );

  Widget _desktop() {
    final p = _padded;
    final live = _digits.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Center(
        child: SingleChildScrollView(
          child: _Rise(
            delay: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        _figure(p.substring(0, 2), 'h', lit: live > 4),
                        const SizedBox(width: 36),
                        _figure(p.substring(2, 4), 'm', lit: live > 2),
                        const SizedBox(width: 36),
                        _figure(p.substring(4, 6), 's', lit: live > 0),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (sec, label) in _presets)
                      _PresetChip(
                        label: label,
                        selected: _seconds == sec,
                        onTap: () => _preset(sec),
                      ),
                  ],
                ),
                const SizedBox(height: 36),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(180, 52),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: widget.onDone,
                  child: const Text('Done'),
                ),
                // the keys stay out of sight until ? or F1 asks for them
                AnimatedSize(
                  duration: Motion.medium,
                  curve: easeOutStrong,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: Motion.fast,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.12),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _help
                        ? const Padding(
                            key: ValueKey('help'),
                            padding: EdgeInsets.only(top: 22),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 22,
                              runSpacing: 10,
                              children: [
                                KeyHint(
                                  keys: ['0', '9'],
                                  label: 'type',
                                  range: true,
                                ),
                                KeyHint(keys: ['⌫'], label: 'delete'),
                                KeyHint(keys: ['↵'], label: 'done'),
                                KeyHint(keys: ['esc'], label: 'close'),
                              ],
                            ),
                          )
                        : const SizedBox(key: ValueKey('none'), width: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
            'Swipe up or down to go back · or type it, Enter when done',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13),
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
    if (onComputer) return _desktop();
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

/// A preset as a quiet pill; the one that matches the time is filled.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    scale: 0.95,
    child: Material(
      color: Colors.white.withValues(alpha: selected ? 0.22 : 0.08),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        splashFactory: NoSplash.splashFactory,
        hoverColor: Colors.white.withValues(alpha: 0.06),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: selected ? 1 : 0.75),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    ),
  );
}
