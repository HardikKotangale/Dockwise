import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../domain/standby_models.dart';

/// Called when a part of the clock (hours, minutes...) is tapped.
typedef PartTap = void Function(ClockPart part);

Widget tapPart(PartTap? onTap, ClockPart part, Widget child) => onTap == null
    ? child
    : GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(part),
        child: child,
      );

/// The time of day as text ("10:09" and "AM", or 24-hour with no suffix), for
/// small uses such as the Summary panel.
({String text, String? suffix}) timeOfDayText(
  DateTime time,
  StandbySettings settings,
) => clockText(time, settings);

/// 'H:MM[:SS]' as spans, each part in its own picked color: hours, the
/// colon, minutes, and (if shown) seconds. [taps] makes each part tappable.
TextSpan timeSpans(
  String text,
  StandbySettings settings, {
  TextStyle? style,
  Map<ClockPart, GestureRecognizer>? taps,
  bool solidColon = false, // full-strength colon unless a color was picked
}) {
  final colon = solidColon && settings.colonColor == 0
      ? settings.hoursInk
      : settings.colonInk;
  final parts = text.split(':');
  if (parts.length < 2) return TextSpan(text: text, style: style);
  TextSpan span(String t, Color c, ClockPart part) => TextSpan(
    text: t,
    style: TextStyle(color: c, shadows: glowShadows(c, settings.glowIntensity)),
    recognizer: taps?[part],
  );
  return TextSpan(
    style: style,
    children: [
      span(parts[0], settings.hoursInk, ClockPart.hours),
      span(':', colon, ClockPart.colon),
      span(parts[1], settings.minutesInk, ClockPart.minutes),
      if (parts.length > 2) ...[
        span(':', colon, ClockPart.colon),
        span(parts[2], settings.detailInk, ClockPart.detail),
      ],
    ],
  );
}

/// Time text whose hours / colon / minutes / seconds can each be tapped.
class TimeText extends StatefulWidget {
  const TimeText({
    super.key,
    required this.text,
    required this.settings,
    required this.style,
    this.onPartTap,
    this.solidColon = false,
  });

  final String text;
  final StandbySettings settings;
  final TextStyle style;
  final PartTap? onPartTap;
  final bool solidColon;

  @override
  State<TimeText> createState() => _TimeTextState();
}

class _TimeTextState extends State<TimeText> {
  final _taps = {for (final p in ClockPart.values) p: TapGestureRecognizer()};

  @override
  void dispose() {
    for (final r in _taps.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cb = widget.onPartTap;
    _taps.forEach((part, r) => r.onTap = cb == null ? null : () => cb(part));
    // Equal-width digits, and a box as wide as the widest possible reading
    // ("88:88:88"), so the clock never changes size as the seconds tick.
    final style = widget.style.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final ruler = TextPainter(
      text: TextSpan(
        text: widget.text.replaceAll(RegExp(r'\d'), '8'),
        style: style,
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = ruler.width;
    ruler.dispose();
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.center,
        child: Text.rich(
          timeSpans(
            widget.text,
            widget.settings,
            style: style,
            taps: cb == null ? null : _taps,
            solidColon: widget.solidColon,
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}

({String text, String? suffix}) clockText(
  DateTime time,
  StandbySettings settings, {
  bool seconds = false,
}) {
  final sec = seconds ? ':${twoDigits(time.second)}' : '';
  if (settings.use24HourTime) {
    return (
      text: '${twoDigits(time.hour)}:${twoDigits(time.minute)}$sec',
      suffix: null,
    );
  }
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return (
    text: '$hour:${twoDigits(time.minute)}$sec',
    suffix: time.hour < 12 ? 'AM' : 'PM',
  );
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

List<Shadow> glowShadows(Color color, double amount) {
  if (amount <= 0.01) return const [];
  return [
    Shadow(
      color: color.withValues(alpha: amount),
      blurRadius: 28 * amount,
    ),
  ];
}

String numberWord(int value) {
  const words = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  if (value < 20) return words[value];
  const tens = {20: 'twenty', 30: 'thirty', 40: 'forty', 50: 'fifty'};
  final ten = value ~/ 10 * 10;
  final rest = value % 10;
  return rest == 0 ? tens[ten]! : '${tens[ten]} ${words[rest]}';
}
