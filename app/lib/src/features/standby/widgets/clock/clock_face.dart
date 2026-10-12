import 'package:flutter/material.dart';

import '../../../../domain/standby_models.dart';
import 'analog_clock.dart';
import 'clock_text.dart';
import 'digital_clock.dart';
import 'flip_clock.dart';
import 'float_clock.dart';
import 'frame_clock.dart';
import 'mono_clock.dart';
import 'text_clock.dart';
import 'world_clock.dart';

class ClockFace extends StatelessWidget {
  const ClockFace({
    super.key,
    required this.time,
    required this.settings,
    this.onPartTap,
  });

  final DateTime time;
  final StandbySettings settings;
  final PartTap? onPartTap;

  @override
  Widget build(BuildContext context) {
    // the panel's own shape (before the face is scaled to fit) decides how
    // Float is arranged
    final spoken = timeOfDayText(time, settings);
    return Semantics(
      // one sentence for a screen reader, not the digits one by one
      label:
          'Time ${spoken.text}${spoken.suffix == null ? '' : ' ${spoken.suffix}'}',
      excludeSemantics: true,
      child: LayoutBuilder(
        // A tall (or squarish) panel stacks the hours over the minutes; a wide
        // one keeps them on a line. The faces glide between the two.
        builder: (context, c) =>
            _scaled(context, stacked: c.maxHeight > c.maxWidth * 0.85),
      ),
    );
  }

  // what the clock looks like apart from the time itself and the sliders
  String _look() => [
    settings.activeThemeId,
    settings.use24HourTime,
    settings.secondsVisible,
    settings.hoursColor,
    settings.minutesColor,
    settings.colonColor,
    settings.detailColor,
    settings.labelColor,
  ].join('|');

  static Duration _gentle(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 320);

  static Duration _fast(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 160);

  Widget _scaled(BuildContext context, {required bool stacked}) {
    // With two panels, World and Flip stay on one line whichever way the phone
    // is held: side by side the text reads better at that size than stacked.
    final twoPanels = settings.layoutMode == StandbyLayoutMode.duo;
    final lineStyle = stacked && !twoPanels;
    final face = switch (settings.clockStyle) {
      ClockStyle.digital => DigitalClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
        stacked: stacked,
      ),
      ClockStyle.analog => AnalogClockFace(time: time, settings: settings),
      // Float follows the panel's shape: wide (one panel) = hours and minutes
      // side by side; narrow or tall (two panels) = hours over minutes
      ClockStyle.float => FloatClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
        stacked: stacked,
      ),
      ClockStyle.frame => FrameClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
      ),
      ClockStyle.mono => MonoClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
        stacked: stacked,
      ),
      ClockStyle.flip => FlipClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
        stacked: lineStyle,
      ),
      ClockStyle.text => TextClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
      ),
      ClockStyle.world => WorldClockFace(
        time: time,
        settings: settings,
        onPartTap: onPartTap,
        stacked: lineStyle,
      ),
    };
    // Every style fills its panel (portrait or landscape); the Size slider
    // shrinks it to a share of that, so it works for all styles alike. The
    // share eases to its new value, so dragging the slider is smooth.
    final share = settings.fontScale.clamp(0.4, 1.0);
    Widget sized(double k) => settings.clockStyle == ClockStyle.frame
        // the frame is a rectangle that fills the whole panel (the whole screen
        // in one-panel mode), so it is not scaled from a fixed size
        ? FractionallySizedBox(widthFactor: k, heightFactor: k, child: face)
        : FractionallySizedBox(
            widthFactor: k,
            heightFactor: k,
            child: FittedBox(fit: BoxFit.contain, child: face),
          );
    final scaled = TweenAnimationBuilder<double>(
      tween: Tween(end: share),
      duration: _fast(context),
      builder: (context, k, _) => sized(k),
    );
    // A change to how the clock looks (a color, 12/24-hour, seconds, the theme)
    // cross-fades from the old look to the new one instead of jumping.
    return AnimatedSwitcher(
      duration: _gentle(context),
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey(_look()), child: scaled),
    );
  }
}
