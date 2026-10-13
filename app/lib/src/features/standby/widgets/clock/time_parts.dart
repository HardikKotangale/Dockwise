import 'package:flutter/material.dart';

import '../../../../core/apple.dart';
import '../../../../domain/standby_models.dart';
import 'clock_text.dart';

/// The time as separate, individually coloured and tappable parts, ready for
/// a [MorphLayout]: hours, the colon, minutes, and a trailing part (seconds and
/// AM/PM). Each number sits in a box as wide as "88", so the clock never
/// shifts as the digits change.
class TimeParts extends StatelessWidget {
  const TimeParts({
    super.key,
    required this.time,
    required this.settings,
    required this.style,
    required this.stacked,
    this.onPartTap,
    this.suffixScale = 0.26,
    this.showSeconds,
    this.rowGap = 0,
    this.stackGap = 0,
  });

  final DateTime time;
  final StandbySettings settings;

  /// the numerals' style; the colours come from the settings
  final TextStyle style;

  /// hours over minutes (a tall panel) instead of on one line
  final bool stacked;
  final PartTap? onPartTap;

  /// AM/PM size relative to the numerals
  final double suffixScale;

  /// null: follow the setting
  final bool? showSeconds;
  final double rowGap;
  final double stackGap;

  @override
  Widget build(BuildContext context) {
    final t = clockText(
      time,
      settings,
      seconds: showSeconds ?? settings.secondsVisible,
    );
    final parts = t.text.split(':');
    final base = style.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // a number in a box as wide as two digits
    Widget number(String value, Color ink, ClockPart part) {
      final ruler = TextPainter(
        text: TextSpan(text: '88', style: base),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = ruler.width;
      ruler.dispose();
      return tapPart(
        onPartTap,
        part,
        SizedBox(
          width: width,
          child: Center(
            child: Text(
              value,
              maxLines: 1,
              style: base.copyWith(
                color: ink,
                shadows: glowShadows(ink, settings.glowIntensity),
              ),
            ),
          ),
        ),
      );
    }

    final hours = number(parts[0], settings.hoursInk, ClockPart.hours);
    final minutes = number(parts[1], settings.minutesInk, ClockPart.minutes);
    final separator = tapPart(
      onPartTap,
      ClockPart.colon,
      Text(
        ':',
        style: base.copyWith(
          color: settings.colonInk,
          shadows: glowShadows(settings.colonInk, settings.glowIntensity),
        ),
      ),
    );

    // seconds: the same size on one line, small under the minutes when stacked
    Widget? trailing;
    final hasSeconds = parts.length > 2;
    if (hasSeconds || t.suffix != null) {
      trailing = TweenAnimationBuilder<double>(
        tween: Tween(end: stacked ? 0.34 : 1.0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : Motion.slow,
        curve: easeOutStrong,
        builder: (context, k, _) {
          final size = (base.fontSize ?? 100) * k;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (hasSeconds)
                tapPart(
                  onPartTap,
                  ClockPart.detail,
                  Text(
                    ':${parts[2]}',
                    style: base.copyWith(
                      fontSize: size,
                      color: settings.detailInk,
                      shadows: glowShadows(
                        settings.detailInk,
                        settings.glowIntensity,
                      ),
                    ),
                  ),
                ),
              if (t.suffix != null)
                tapPart(
                  onPartTap,
                  ClockPart.detail,
                  Padding(
                    // on a line it sits at the baseline after the digits; under
                    // them it is centred, with no shift to either side
                    padding: EdgeInsets.only(
                      left: stacked ? 0 : 10,
                      bottom: stacked ? 0 : (base.fontSize ?? 100) * 0.06,
                    ),
                    child: Text(
                      t.suffix!,
                      style: TextStyle(
                        color: settings.detailInk,
                        shadows: glowShadows(
                          settings.detailInk,
                          settings.glowIntensity,
                        ),
                        fontSize: (base.fontSize ?? 100) * suffixScale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

    return MorphLayout(
      stacked: stacked,
      hours: hours,
      separator: separator,
      minutes: minutes,
      trailing: trailing,
      rowGap: rowGap,
      stackGap: stackGap,
    );
  }
}
