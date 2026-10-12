import 'package:flutter/material.dart';

import '../../../core/apple.dart';
import '../../../domain/standby_models.dart';
import 'celebration.dart';
import 'clock/clock_text.dart';
import 'clock/flip_clock.dart';
import 'timer_track.dart';

/// The timer: no card behind it, like the clock. The countdown is as big as
/// the room allows (hours over minutes over seconds in a tall panel), with a
/// small figure running along a track under it: a horse for the digital style,
/// a player heading for the end zone for the flip style. Small quiet buttons
/// (reset, start / pause, +1 / +5 / +10 min) sit at the right in landscape and
/// at the bottom in portrait; quick lengths and a "Type" button (our own
/// number pad) fold away once it is running.
class TimerCard extends StatefulWidget {
  const TimerCard({
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
    required this.onAdd,
    required this.onPreset,
    required this.onType,
    this.roomy = false,
    this.horizontal = false,
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
  final ValueChanged<int> onAdd; // minutes
  final ValueChanged<int> onPreset; // seconds
  final VoidCallback onType;

  /// One panel: bigger, boxy buttons (there is room). Two panels: small ones.
  final bool roomy;

  /// Two panels: the time stays on one line in either orientation.
  final bool horizontal;

  static const presets = [60, 300, 600, 900, 1800, 3600, 7200];

  static String presetLabel(int seconds) =>
      seconds >= 3600 ? '${seconds ~/ 3600} hr' : '${seconds ~/ 60} min';

  @override
  State<TimerCard> createState() => _TimerCardState();
}

const _green = Color(0xFF30D158);
const _orange = Color(0xFFFF9F0A);
const _red = Color(0xFFFF453A);

class _TimerCardState extends State<TimerCard>
    with SingleTickerProviderStateMixin {
  // a slow pulse while it rings
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(TimerCard old) {
    super.didUpdateWidget(old);
    if (widget.done && !_pulse.isAnimating) {
      if (!MediaQuery.disableAnimationsOf(context)) {
        _pulse.repeat(reverse: true);
      }
    } else if (!widget.done && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  // 5:00 -> ["05", "00"]; an hour or more adds the hour in front
  List<String> _parts() {
    final secs = (widget.leftMs / 1000).ceil();
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return [if (h > 0) '$h', two(m), two(s)];
  }

  // what a screen reader says for the time left
  String _spoken() {
    final secs = (widget.leftMs / 1000).ceil();
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    return [
      if (h > 0) '$h ${h == 1 ? 'hour' : 'hours'}',
      if (m > 0) '$m ${m == 1 ? 'minute' : 'minutes'}',
      if (s > 0 || secs == 0) '$s ${s == 1 ? 'second' : 'seconds'}',
    ].join(' ');
  }

  // Digits, big. Stacked (a tall panel): hours over minutes over seconds, each
  // as large as the width allows. Otherwise on one line with colons.
  // The timer's own colors when picked; otherwise the clock's.
  StandbySettings get _st => widget.settings.timerLook;

  // the horse, the player and the track
  Color get _figureColor {
    final s = widget.settings;
    if (s.timerFigureColor != 0) return Color(s.timerFigureColor);
    return _st.minutesInk;
  }

  Widget _digital(List<String> parts, bool stacked) {
    final st = _st;
    const base = TextStyle(
      fontSize: 220,
      height: 0.92,
      fontWeight: FontWeight.w300,
      letterSpacing: -4,
      fontFeatures: [FontFeature.tabularFigures()],
      decoration: TextDecoration.none,
    );
    Color ink(int i) => i == parts.length - 1 ? st.minutesInk : st.hoursInk;
    Text part(int i) => Text(
      parts[i],
      style: base.copyWith(
        color: ink(i),
        shadows: glowShadows(ink(i), st.glowIntensity),
      ),
    );
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < parts.length; i++) part(i)],
      );
    }
    final colon = base.copyWith(color: st.colonInk);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) Text(':', style: colon),
          part(i),
        ],
      ],
    );
  }

  Widget _flip(List<String> parts, bool stacked) {
    final st = _st;
    Widget group(int i) {
      final role = i == parts.length - 1 ? ClockPart.minutes : ClockPart.hours;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var d = 0; d < parts[i].length; d++) ...[
            if (d > 0) const SizedBox(width: 6),
            FlipCard(
              key: ValueKey('timer$i$d'),
              value: parts[i][d],
              settings: st,
              role: role,
              width: 88,
              height: 150,
              fontSize: 92,
              radius: 16,
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
            if (i > 0) const SizedBox(height: 12),
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              ':',
              style: TextStyle(
                color: st.colonInk,
                fontSize: 90,
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

  // The countdown, as big as the room allows, with the running figure under
  // it. Tap the time to type a length (before it starts).
  Widget _face(bool stacked, {Widget? above}) {
    final st = widget.settings;
    final parts = _parts();
    final flip = st.timerStyle == TimerStyle.flip;
    final progress = widget.totalMs <= 0
        ? 0.0
        : (widget.leftMs / widget.totalMs).clamp(0.0, 1.0);
    // the horse and the player keep the same colors to the end
    final color = _figureColor;
    final digits = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: KeyedSubtree(
        key: ValueKey('${st.timerStyle.name}$stacked'),
        child: flip ? _flip(parts, stacked) : _digital(parts, stacked),
      ),
    );
    return Column(
      children: [
        Expanded(
          child: Semantics(
            label: 'Timer, ${_spoken()} left',
            button: !widget.started,
            hint: widget.started ? null : 'Double tap to type a length',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.started ? null : widget.onType,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) => Opacity(
                  opacity: widget.done ? 1 - 0.55 * _pulse.value : 1,
                  child: child,
                ),
                child: SizedBox.expand(
                  child: FittedBox(fit: BoxFit.contain, child: digits),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // e.g. the +minute buttons, right above the track
        if (above != null) ...[above, const SizedBox(height: 10)],
        ExcludeSemantics(
          child: TimerTrack(
            height: _short ? 28 : 44,
            kind: flip ? TrackKind.field : TrackKind.horse,
            progress: progress,
            color: color,
            done: widget.done,
          ),
        ),
      ],
    );
  }

  // Evenly spaced boxes in [columns] columns: it fills the room instead of
  // stacking one to a line.
  Widget _grid(List<Widget> kids, int columns) {
    final rows = <Widget>[];
    for (var i = 0; i < kids.length; i += columns) {
      final row = kids.skip(i).take(columns).toList();
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
          child: Row(
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: 10),
                Expanded(child: j < row.length ? row[j] : const SizedBox()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _chips(int columns) {
    // two panels: no room for the quick lengths here; they are on the number
    // pad (tap the time, or Type)
    if (widget.horizontal) return const SizedBox.shrink();
    final st = widget.settings;
    final kids = [
      for (final s in TimerCard.presets)
        _Chip(
          box: widget.roomy,
          label: TimerCard.presetLabel(s),
          selected: st.timerSeconds == s,
          onTap: () => widget.onPreset(s),
        ),
      _Chip(
        box: widget.roomy,
        label: 'Type',
        icon: Icons.keyboard_rounded,
        selected: false,
        onTap: widget.onType,
      ),
    ];
    if (widget.roomy) return _grid(kids, columns);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: kids,
    );
  }

  // Small and quiet: they sit on the screen, not on a card.
  Widget _add(int m) => _Chip(
    box: widget.roomy || widget.horizontal,
    dense: widget.horizontal,
    label: '+$m min',
    spoken: 'Add $m ${m == 1 ? 'minute' : 'minutes'}',
    selected: false,
    onTap: () => widget.onAdd(m),
  );

  // +1 / +5 / +10 minutes in a row (landscape puts them above the track)
  Widget _addRow() {
    // once it runs, everything is in this one row above the track, so the
    // time gets all the width
    final all = widget.started;
    if (!widget.roomy) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          _add(1),
          _add(5),
          _add(10),
          if (all) ...[_reset(), _go()],
        ],
      );
    }
    final kids = [
      for (final m in const [1, 5, 10]) _add(m),
      if (all) ...[_reset(), _go()],
    ];
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: all ? 720 : 460),
        child: Row(
          children: [
            for (var i = 0; i < kids.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: kids[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reset() {
    return _Chip(
      box: widget.roomy || widget.horizontal,
      dense: widget.horizontal,
      label: 'Reset',
      spoken: 'Reset timer',
      selected: false,
      dim: !widget.started,
      onTap: widget.onReset,
    );
  }

  Widget _go() {
    final primaryLabel = widget.done
        ? 'Stop'
        : widget.running
        ? 'Pause'
        : widget.started
        ? 'Resume'
        : 'Start';
    final primary = widget.done
        ? _red
        : widget.running
        ? _orange
        : _green;
    return _Chip(
      box: widget.roomy || widget.horizontal,
      dense: widget.horizontal,
      label: primaryLabel,
      spoken: '$primaryLabel timer',
      selected: true,
      tint: primary,
      onTap: widget.done
          ? widget.onReset
          : widget.running
          ? widget.onPause
          : widget.onStart,
    );
  }

  Widget _controls({bool withAdd = true}) {
    Widget add(int m) => _add(m);
    final reset = _reset();
    final go = _go();
    if (widget.roomy) {
      // big boxes that share the width, so they are easy to hit
      Widget row(List<Widget> kids) => Row(
        children: [
          for (var i = 0; i < kids.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: kids[i]),
          ],
        ],
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (withAdd) ...[
            row([add(1), add(5), add(10)]),
            const SizedBox(height: 10),
          ],
          row([reset, go]),
        ],
      );
    }
    if (widget.horizontal) {
      // two panels: the same boxes, in two rows, so the time gets the room
      Widget row(List<Widget> kids) => Row(
        children: [
          for (var i = 0; i < kids.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: kids[i]),
          ],
        ],
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row([add(1), add(5), add(10)]),
          const SizedBox(height: 6),
          row([
            _Chip(
              box: true,
              dense: true,
              label: 'Type',
              icon: Icons.keyboard_rounded,
              selected: false,
              onTap: widget.onType,
            ),
            reset,
            go,
          ]),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (withAdd) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              add(1),
              add(5),
              add(10),
              if (widget.horizontal)
                _Chip(
                  label: 'Type',
                  icon: Icons.keyboard_rounded,
                  selected: false,
                  onTap: widget.onType,
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [reset, go],
        ),
      ],
    );
  }

  // quick lengths, folded away once the timer has started
  Widget _folding(Widget child) => AnimatedSize(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    curve: easeOutStrong,
    alignment: Alignment.topCenter,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: widget.started ? 0 : 1,
      child: widget.started ? const SizedBox(width: double.infinity) : child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _layout(),
        // confetti and fireworks for the touchdown
        Positioned.fill(child: Celebration(active: widget.done)),
      ],
    );
  }

  // a short panel (two panels, settings open): everything gets smaller so the
  // time keeps its room
  bool _short = false;

  Widget _layout() {
    return LayoutBuilder(
      builder: (context, c) {
        _short = c.maxHeight < 300;
        // two panels never use the side-by-side layout: a short panel (the
        // settings dock is open) would squeeze it
        final wide = !widget.horizontal && c.maxWidth > c.maxHeight * 1.25;
        if (wide) {
          final side = widget.roomy ? 360.0 : 190.0;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
            child: Row(
              children: [
                Expanded(child: _face(false, above: _addRow())),
                // the side column slides away once it runs, and the time takes
                // the whole width
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: easeOutStrong,
                  width: widget.started ? 0 : side + 14,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerRight,
                      minWidth: side,
                      maxWidth: side,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14),
                        // a short panel shrinks the column instead of overflowing
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: side - 14,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _chips(3),
                                ),
                                _controls(withAdd: false),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        // tall: the time on top, everything else under it, never taking more
        // than half the height so the time always has room
        final inner = c.maxWidth - 32;
        return Padding(
          padding: _short
              ? const EdgeInsets.fromLTRB(10, 4, 10, 8)
              : const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            children: [
              Expanded(child: _face(!widget.horizontal)),
              SizedBox(height: _short ? 6 : 10),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: c.maxHeight * (_short ? 0.4 : 0.5),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _Compact(
                    on: _short,
                    child: SizedBox(
                      width: _short ? c.maxWidth - 20 : inner,
                      child: Column(
                        children: [
                          _folding(
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _chips(4),
                            ),
                          ),
                          _controls(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Tells the buttons below it to be small (a short panel).
class _Compact extends InheritedWidget {
  const _Compact({required this.on, required super.child});

  final bool on;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Compact>()?.on ?? false;

  @override
  bool updateShouldNotify(_Compact old) => old.on != on;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.spoken,
    this.tint,
    this.dim = false,
    this.box = false,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? spoken;

  /// a color for the text (Start is green, Pause orange)
  final Color? tint;
  final bool dim;

  /// a roomy rounded box instead of a small pill
  final bool box;

  /// a box with less height (two panels)
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tiny = _Compact.of(context);
    final ink =
        tint ??
        Colors.white.withValues(alpha: dim ? 0.3 : (selected ? 1 : 0.72));
    return Semantics(
      button: true,
      selected: selected,
      label: spoken ?? (icon == null ? 'Set $label' : 'Type a length'),
      excludeSemantics: true,
      child: Pressable(
        scale: 0.95,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            tick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: box ? 12 : 14,
              vertical: tiny ? 5 : (dense ? 10 : (box ? 15 : 8)),
            ),
            alignment: box ? Alignment.center : null,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tiny ? 10 : (box ? 14 : 18)),
              color: tint != null
                  ? tint!.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: selected ? 0.22 : 0.08),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: ink),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: ink,
                      fontSize: tiny ? 12 : (dense ? 14 : (box ? 16 : 14)),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
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
