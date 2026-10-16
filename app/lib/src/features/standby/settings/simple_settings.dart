import 'dart:async';

import 'package:flutter/gestures.dart' show EagerGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/motion/motion.dart';
import '../../../core/palette.dart';
import '../../../domain/standby_models.dart';
import '../../../services/weather_service.dart';
import '../../../state/standby_controller.dart';
import '../widgets/calendar_card.dart';
import '../widgets/dock.dart';
import '../widgets/summary_card.dart' show SummaryCard, SummaryClockPreview;
import '../widgets/timer_track.dart';
import '../widgets/weather_card.dart' show WeatherNowView;
import 'city_page.dart' show CityRow;
import 'clock_settings.dart' show LookPicker, MiniClock;
import 'controls.dart';

/// Calendar settings: today's date or the whole month.
class CalendarSettings extends StatelessWidget {
  const CalendarSettings({
    super.key,
    required this.controller,
    required this.onAll,
  });

  final StandbyController controller;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: dockPadding,
      children: [
        CalendarBody(controller: controller),
        const Text(
          'Tip: swipe up or down on the calendar to switch.',
          style: TextStyle(color: Colors.white54),
        ),
        AllSettingsButton(onPressed: onAll),
      ],
    );
  }
}

/// Weather settings: unit, refresh, and a way to fix location permission.
class WeatherSettings extends StatelessWidget {
  const WeatherSettings({
    super.key,
    required this.controller,
    required this.onAll,
    this.onCity,
  });

  final StandbyController controller;
  final VoidCallback onAll;

  /// opens the city search (the weather's third page is the second city)
  final VoidCallback? onCity;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final problem = controller.weatherProblem;
    return ListView(
      padding: dockPadding,
      children: [
        const Text(
          'Weather uses this device\'s location.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: settings.fahrenheit,
          onChanged: (v) =>
              controller.updateSettings(settings.copyWith(fahrenheit: v)),
          title: const Text('Temperature in °F'),
        ),
        if (onCity != null)
          CityRow(
            settings: settings,
            onTap: onCity!,
            onChanged: controller.updateSettings,
          ),
        FilledButton(
          onPressed: controller.refreshWeather,
          child: const Text('Refresh weather'),
        ),
        if (problem == WeatherProblem.permission ||
            problem == WeatherProblem.locationOff) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: problem == WeatherProblem.permission
                ? Geolocator.openAppSettings
                : Geolocator.openLocationSettings,
            child: Text(
              problem == WeatherProblem.permission
                  ? 'Allow location in app settings'
                  : 'Turn on location',
            ),
          ),
        ],
        AllSettingsButton(onPressed: onAll),
      ],
    );
  }
}

/// One colour choice, as a dropdown row like the settings groups: a small
/// icon, the name, the colour now chosen as a dot, and a chevron. Opened, it
/// shows the swatches ("Auto" first) and the colour pad.
class ColorRow extends StatefulWidget {
  const ColorRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.autoLabel = 'Auto',
    this.icon,
    this.focus = false,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String autoLabel;

  /// the icon in front; found from the label when null
  final IconData? icon;

  /// true opens the row (a part of the clock was tapped: here it is)
  final bool focus;

  static const _icons = <String, IconData>{
    'Here tile': Icons.place_rounded,
    'Second city tile': Icons.public_rounded,
    'Time': Icons.schedule_rounded,
    'AM / PM and the day line': Icons.timelapse_rounded,
    'Accent color': Icons.palette_rounded,
    'Time color': Icons.schedule_rounded,
    'Horse and player color': Icons.directions_run_rounded,
  };

  @override
  State<ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<ColorRow> {
  late bool _open = SettingsSection.debugOpenAll || widget.focus;

  @override
  void didUpdateWidget(ColorRow old) {
    super.didUpdateWidget(old);
    if (widget.focus && !old.focus) setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final picked = value == 0 ? null : Color(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white.withValues(alpha: _open ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: _open,
              label: widget.label,
              child: InkWell(
                splashFactory: NoSplash.splashFactory,
                onTap: () {
                  tick();
                  setState(() => _open = !_open);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          widget.icon ??
                              ColorRow._icons[widget.label] ??
                              Icons.palette_rounded,
                          size: 17,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (picked == null)
                        Flexible(
                          child: Text(
                            widget.autoLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: picked,
                            border: Border.all(
                              color: Colors.white54,
                              width: 1.5,
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _open ? 0.25 : 0,
                        duration: reduce ? Duration.zero : Motion.fast,
                        curve: easeOutStrong,
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: reduce ? Duration.zero : Motion.medium,
              curve: easeOutStrong,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ChoiceChip(
                                label: Text(widget.autoLabel),
                                selected: value == 0,
                                onSelected: (_) => widget.onChanged(0),
                              ),
                              for (final c in clockPalette)
                                Semantics(
                                  button: true,
                                  selected: value == c.argb,
                                  label: '${widget.label} ${c.name}',
                                  child: GestureDetector(
                                    onTap: () => widget.onChanged(c.argb),
                                    child: AnimatedContainer(
                                      duration: calm(context, Motion.fast),
                                      curve: easeOutStrong,
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(c.argb),
                                        border: Border.all(
                                          color: value == c.argb
                                              ? (c.argb == 0xFFFFFFFF
                                                    ? Palette.blue
                                                    : Colors.white)
                                              : Colors.white24,
                                          width: value == c.argb ? 3 : 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _ColorPad(value: value, onChanged: widget.onChanged),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every colour there is, on one pad: hues from left to right, light at the
/// top and dark at the bottom, and a grey strip at the far left for white,
/// silver, slate and black. Drag anywhere. The thumb follows the finger at
/// once; the colour itself is handed on at most every 60 ms, because every
/// hand-over redraws the whole display behind the settings and saves them.
class _ColorPad extends StatefulWidget {
  const _ColorPad({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_ColorPad> createState() => _ColorPadState();
}

class _ColorPadState extends State<_ColorPad> {
  static const _gray = 0.07; // the grey strip: this fraction of the width
  static const _every = Duration(milliseconds: 60);

  Offset? _drag; // the thumb while a finger is down, in 0..1
  Timer? _timer;
  Color? _pending;
  DateTime _last = DateTime(0);

  static Color colorAt(double u, double v) {
    if (u < _gray) {
      return HSLColor.fromAHSL(1, 0, 0, (1 - v).clamp(0.03, 0.98)).toColor();
    }
    final hue = ((u - _gray) / (1 - _gray)).clamp(0.0, 1.0) * 359;
    // light tints at the top, the pure colour about 40% down, deep tones below
    return HSLColor.fromAHSL(1, hue, 0.9, (0.92 - 0.72 * v)).toColor();
  }

  static Offset where(Color c) {
    final hsl = HSLColor.fromColor(c);
    if (hsl.saturation < 0.12) return Offset(_gray / 2, 1 - hsl.lightness);
    return Offset(
      _gray + hsl.hue / 359 * (1 - _gray),
      ((0.92 - hsl.lightness) / 0.72).clamp(0.0, 1.0),
    );
  }

  void _at(Offset p, Size size, {bool end = false}) {
    final u = (p.dx / size.width).clamp(0.0, 1.0);
    final v = (p.dy / size.height).clamp(0.0, 1.0);
    setState(() => _drag = end ? null : Offset(u, v));
    _pending = colorAt(u, v);
    if (end || DateTime.now().difference(_last) > _every) {
      _flush();
    } else {
      _timer ??= Timer(_every, _flush);
    }
  }

  void _flush() {
    _timer?.cancel();
    _timer = null;
    final c = _pending;
    if (c == null) return;
    _pending = null;
    _last = DateTime.now();
    widget.onChanged(c.toARGB32());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = _drag ?? (widget.value == 0 ? null : where(Color(widget.value)));
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, 150);
        return Semantics(
          label: 'Any color. Drag to choose',
          slider: true,
          child: RawGestureDetector(
            // wins the touch at once, so dragging here never scrolls the page
            gestures: {
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
            },
            child: Listener(
              onPointerDown: (e) => _at(e.localPosition, size),
              onPointerMove: (e) => _at(e.localPosition, size),
              onPointerUp: (e) => _at(e.localPosition, size, end: true),
              onPointerCancel: (_) {
                setState(() => _drag = null);
                _flush();
              },
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // drawn once: the thumb moves over it, it never repaints
                    RepaintBoundary(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CustomPaint(
                          size: size,
                          painter: const _PadPainter(),
                        ),
                      ),
                    ),
                    if (at != null)
                      Positioned(
                        left: at.dx * size.width - 14,
                        top: at.dy * size.height - 14,
                        child: IgnorePointer(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _drag != null
                                  ? colorAt(_drag!.dx, _drag!.dy)
                                  : Color(widget.value),
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PadPainter extends CustomPainter {
  const _PadPainter();

  static const _cols = 96;
  static const _rows = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / _cols, h = size.height / _rows;
    final paint = Paint()..isAntiAlias = false;
    for (var x = 0; x < _cols; x++) {
      for (var y = 0; y < _rows; y++) {
        paint.color = _ColorPadState.colorAt(
          (x + 0.5) / _cols,
          (y + 0.5) / _rows,
        );
        // a hair wider than the cell, so no seams show between them
        canvas.drawRect(Rect.fromLTWH(x * w, y * h, w + 0.6, h + 0.6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => false;
}

/// Everything about the timer except where it lives: style, colors, and what
/// happens when it ends. Used by the timer's own settings and by All settings.
class TimerBody extends StatelessWidget {
  const TimerBody({super.key, required this.controller});

  final StandbyController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    void set(StandbySettings v) => controller.updateSettings(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Style',
          scope: 'Timer',
          nested: true,
          first: true,
          child: TimerLookPicker(settings: settings, onChanged: set),
        ),
        SettingsSection(
          title: 'Presets',
          scope: 'Timer',
          nested: true,
          subtitle: 'Ready-made colors, shown in the style you picked',
          child: LookPicker<(String, int, int)>(
            label: '',
            value: _timerPresets.firstWhere(
              (p) =>
                  p.$2 == settings.timerColor &&
                  p.$3 == settings.timerFigureColor,
              orElse: () => ('', -1, -1),
            ),
            values: _timerPresets,
            name: (p) => p.$1,
            preview: (p) => _TimerSketch(
              style: settings.timerStyle,
              color: p.$2,
              figure: p.$3,
            ),
            onChanged: (p) => set(
              settings.copyWith(timerColor: p.$2, timerFigureColor: p.$3),
            ),
          ),
        ),
        SettingsSection(
          title: 'Colors',
          scope: 'Timer',
          nested: true,
          child: Column(
            children: [
              ColorRow(
                label: 'Time color',
                autoLabel: 'Like the clock',
                value: settings.timerColor,
                onChanged: (c) => set(settings.copyWith(timerColor: c)),
              ),
              ColorRow(
                label: 'Horse and player color',
                autoLabel: 'Like the time',
                value: settings.timerFigureColor,
                onChanged: (c) => set(settings.copyWith(timerFigureColor: c)),
              ),
            ],
          ),
        ),
        SettingsSection(
          title: 'Options',
          scope: 'Timer',
          nested: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EnumPicker<String>(
                label: 'Sound when it ends',
                value: settings.timerSound,
                values: const ['alarm', 'chime', 'fanfare', 'none'],
                display: (v) => switch (v) {
                  'alarm' => 'Alarm',
                  'chime' => 'Chime',
                  'fanfare' => 'Fanfare',
                  _ => 'None',
                },
                onChanged: (v) {
                  set(settings.copyWith(timerSound: v));
                  // hear it as soon as you pick it
                  controller.testTimerAlert();
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vibrate'),
                subtitle: const Text(
                  'A phone on silent vibrates instead of playing the sound.',
                ),
                value: settings.timerVibrate,
                onChanged: (v) => set(settings.copyWith(timerVibrate: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Timer settings in the dock (tap the timer).
class TimerSettings extends StatelessWidget {
  const TimerSettings({
    super.key,
    required this.controller,
    required this.onAll,
  });

  final StandbyController controller;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: dockPadding,
      children: [
        TimerBody(controller: controller),
        const Text(
          'Tip: swipe up or down on the timer to switch the style.',
          style: TextStyle(color: Colors.white54),
        ),
        AllSettingsButton(onPressed: onAll),
      ],
    );
  }
}

/// Today / Whole month, each drawn by the real calendar card.
class CalendarLookPicker extends StatelessWidget {
  const CalendarLookPicker({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final StandbySettings settings;
  final ValueChanged<StandbySettings> onChanged;

  @override
  Widget build(BuildContext context) => LookPicker<CalendarStyle>(
    label: 'Style',
    value: settings.calendarStyle,
    values: CalendarStyle.values,
    name: (v) => v == CalendarStyle.day ? 'Today' : 'Month',
    preview: (v) => CalendarCard(
      settings: settings.copyWith(calendarStyle: v),
      now: DateTime(2026, 1, 17, 10, 9),
      entrance: false,
      compact: true,
    ),
    onChanged: (v) => onChanged(settings.copyWith(calendarStyle: v)),
  );
}

const _timerPresets = <(String, int, int)>[
  ('Plain', 0, 0),
  ('Green', 0xFF30D158, 0xFFFFD60A),
  ('Amber', 0xFFFF9F0A, 0xFFFFFFFF),
  ('Red', 0xFFFF453A, 0xFFFFD60A),
  ('Blue', 0xFF0A84FF, 0xFF64D2FF),
  ('Violet', 0xFFBF5AF2, 0xFFFF9FF3),
];

/// colors shared by the calendar's and the Summary tiles' presets
const _calendarPresets = <(String, int)>[
  ('Plain', 0),
  ('Red', 0xFFFF453A),
  ('Orange', 0xFFFF9F0A),
  ('Green', 0xFF30D158),
  ('Blue', 0xFF0A84FF),
  ('Violet', 0xFFBF5AF2),
];

/// The Summary's two time tiles, set up like the Clock's settings: style,
/// ready-made looks, colors and options, each in its own part.
class SummaryClocksBody extends StatelessWidget {
  const SummaryClocksBody({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onCity,
  });

  final StandbySettings settings;
  final ValueChanged<StandbySettings> onChanged;
  final VoidCallback onCity;

  static String _name(TileClockStyle v) => switch (v) {
    TileClockStyle.digital => 'Frame',
    TileClockStyle.flip => 'Flip',
    TileClockStyle.analog => 'Analog',
  };

  @override
  Widget build(BuildContext context) {
    final set = onChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Style',
          scope: 'Summary',
          nested: true,
          first: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LookPicker<TileClockStyle>(
                id: 'summary-here',
                label: 'Here',
                value: settings.summaryClockStyle,
                values: TileClockStyle.values,
                name: _name,
                preview: (v) =>
                    SummaryClockPreview(settings: settings, style: v),
                onChanged: (v) => set(settings.copyWith(summaryClockStyle: v)),
              ),
              LookPicker<int>(
                id: 'summary-there',
                label: 'Second city',
                value: settings.summaryThereStyle,
                values: const [-1, 0, 1, 2],
                name: (i) =>
                    i < 0 ? 'Same as Here' : _name(TileClockStyle.values[i]),
                preview: (i) => SummaryClockPreview(
                  settings: settings,
                  style: i < 0
                      ? settings.summaryClockStyle
                      : TileClockStyle.values[i],
                  second: true,
                ),
                onChanged: (i) => set(settings.copyWith(summaryThereStyle: i)),
              ),
            ],
          ),
        ),
        SettingsSection(
          title: 'Presets',
          scope: 'Summary',
          nested: true,
          subtitle: 'Ready-made tile colors, one set for each clock',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LookPicker<(String, int)>(
                id: 'summary-here-preset',
                label: 'Here',
                value: _calendarPresets.firstWhere(
                  (p) => p.$2 == settings.hereColor,
                  orElse: () => ('', -1),
                ),
                values: _calendarPresets,
                name: (p) => p.$1,
                preview: (p) => SummaryClockPreview(
                  settings: settings.copyWith(hereColor: p.$2),
                  style: settings.summaryClockStyle,
                ),
                onChanged: (p) => set(settings.copyWith(hereColor: p.$2)),
              ),
              LookPicker<(String, int)>(
                id: 'summary-there-preset',
                label: 'Second city',
                value: _calendarPresets.firstWhere(
                  (p) => p.$2 == settings.thereColor,
                  orElse: () => ('', -1),
                ),
                values: _calendarPresets,
                name: (p) => p.$1,
                preview: (p) => SummaryClockPreview(
                  settings: settings.copyWith(thereColor: p.$2),
                  style: settings.thereStyle,
                  second: true,
                ),
                onChanged: (p) => set(settings.copyWith(thereColor: p.$2)),
              ),
            ],
          ),
        ),
        SettingsSection(
          title: 'Colors',
          scope: 'Summary',
          nested: true,
          child: Column(
            children: [
              ColorRow(
                label: 'Here tile',
                autoLabel: 'Plain',
                value: settings.hereColor,
                onChanged: (c) => set(settings.copyWith(hereColor: c)),
              ),
              ColorRow(
                label: 'Second city tile',
                autoLabel: 'Plain',
                value: settings.thereColor,
                onChanged: (c) => set(settings.copyWith(thereColor: c)),
              ),
              ColorRow(
                label: 'Time',
                autoLabel: 'Like the tile',
                value: settings.summaryTimeColor,
                onChanged: (c) => set(settings.copyWith(summaryTimeColor: c)),
              ),
              ColorRow(
                label: 'AM / PM and the day line',
                autoLabel: 'Like the tile',
                value: settings.summaryDetailColor,
                onChanged: (c) => set(settings.copyWith(summaryDetailColor: c)),
              ),
            ],
          ),
        ),
        SettingsSection(
          title: 'Options',
          scope: 'Summary',
          nested: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EnumPicker<int>(
                label: 'Hours',
                value: settings.summaryHours,
                values: const [0, 1, 2],
                display: (v) => switch (v) {
                  1 => '12-hour',
                  2 => '24-hour',
                  _ => 'Like the Clock',
                },
                onChanged: (v) => set(settings.copyWith(summaryHours: v)),
              ),
              CityRow(settings: settings, onTap: onCity, onChanged: set),
            ],
          ),
        ),
      ],
    );
  }
}

/// The calendar's style, ready-made colors and accent, as parts.
class CalendarBody extends StatelessWidget {
  const CalendarBody({super.key, required this.controller});

  final StandbyController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    void set(StandbySettings v) => controller.updateSettings(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Style',
          scope: 'Calendar',
          nested: true,
          first: true,
          child: CalendarLookPicker(settings: settings, onChanged: set),
        ),
        SettingsSection(
          title: 'Presets',
          scope: 'Calendar',
          nested: true,
          subtitle: 'Ready-made colors, shown in the style you picked',
          child: LookPicker<(String, int)>(
            label: '',
            value: _calendarPresets.firstWhere(
              (p) => p.$2 == settings.calendarColor,
              orElse: () => ('', -1),
            ),
            values: _calendarPresets,
            name: (p) => p.$1,
            preview: (p) => CalendarCard(
              settings: settings.copyWith(calendarColor: p.$2),
              now: DateTime(2026, 1, 17, 10, 9),
              entrance: false,
              compact: true,
            ),
            onChanged: (p) => set(settings.copyWith(calendarColor: p.$2)),
          ),
        ),
        SettingsSection(
          title: 'Colors',
          scope: 'Calendar',
          nested: true,
          child: ColorRow(
            label: 'Accent color',
            autoLabel: 'Like the theme',
            value: settings.calendarColor,
            onChanged: (c) => set(settings.copyWith(calendarColor: c)),
          ),
        ),
      ],
    );
  }
}

/// Digital / Flip, each drawn small.
class TimerLookPicker extends StatelessWidget {
  const TimerLookPicker({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final StandbySettings settings;
  final ValueChanged<StandbySettings> onChanged;

  @override
  Widget build(BuildContext context) => LookPicker<TimerStyle>(
    label: '',
    value: settings.timerStyle,
    values: TimerStyle.values,
    name: (v) => v == TimerStyle.digital ? 'Digital' : 'Flip',
    preview: (v) => _TimerSketch(
      style: v,
      color: settings.timerColor,
      figure: settings.timerFigureColor,
    ),
    onChanged: (v) => onChanged(settings.copyWith(timerStyle: v)),
  );
}

/// A small sketch of the timer in a style and color: the time and, under it,
/// the horse (Digital) or the player (Flip) on their track.
class _TimerSketch extends StatelessWidget {
  const _TimerSketch({
    required this.style,
    required this.color,
    required this.figure,
  });

  final TimerStyle style;
  final int color;
  final int figure;

  @override
  Widget build(BuildContext context) {
    final ink = color == 0 ? Colors.white : Color(color);
    final runner = figure == 0 ? ink : Color(figure);
    TextStyle text(FontWeight w) =>
        TextStyle(fontSize: 30, fontWeight: w, color: ink);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: style == TimerStyle.digital
                  ? Text('05:00', style: text(FontWeight.w200))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final d in ['05', '00'])
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: ink.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(d, style: text(FontWeight.w600)),
                          ),
                      ],
                    ),
            ),
          ),
          TimerTrack(
            kind: style == TimerStyle.digital
                ? TrackKind.horse
                : TrackKind.field,
            progress: 0.55,
            color: runner,
            height: 26,
          ),
        ],
      ),
    );
  }
}

/// One panel or two, drawn as the screen would be split.
class PanelsPreview extends StatelessWidget {
  const PanelsPreview({super.key, required this.two, required this.settings});

  final bool two;
  final StandbySettings settings;

  @override
  Widget build(BuildContext context) {
    // each panel shows the widget it holds now, so the picture is the screen
    Widget panel(StandbyWidgetType type) => Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: FittedBox(
            child: SizedBox(
              width: 160,
              height: 110,
              child: WidgetPreview(type: type, settings: settings),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        // stretch: an empty box would otherwise have no height at all
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          panel(settings.leftWidget),
          if (two) ...[const SizedBox(width: 6), panel(settings.rightWidget)],
        ],
      ),
    );
  }
}

/// A widget type as a small picture of the card itself: the real clock and
/// calendar, a still sketch of the weather, music and timer (so a preview
/// never starts a timer or loads anything), and the Summary as its tiles.
class WidgetPreview extends StatelessWidget {
  const WidgetPreview({super.key, required this.type, required this.settings});

  final StandbyWidgetType type;
  final StandbySettings settings;

  static final _when = DateTime(2026, 1, 17, 10, 9, 30);

  Widget _weather() {
    final tint = WeatherNowView.tintFor(2, true);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: tint,
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bloomington',
                style: TextStyle(fontSize: 13, color: Colors.white),
              ),
              Text(
                '23°',
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w200,
                  height: 1,
                  color: Colors.white,
                ),
              ),
              Text(
                'Cloudy  H:24° L:18°',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _music() => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF8E3A59), Color(0xFF1B2A55)],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text(
            'Song name',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const Text(
            'Artist',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: const LinearProgressIndicator(
              value: 0.35,
              minHeight: 3,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Icon(Icons.skip_previous_rounded, size: 22),
              Icon(Icons.pause_circle_filled_rounded, size: 30),
              Icon(Icons.skip_next_rounded, size: 22),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _calendar() => CalendarCard(
    settings: settings,
    now: _when,
    entrance: false,
    compact: true,
  );

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case StandbyWidgetType.clock:
        return Center(child: MiniClock(settings: settings));
      case StandbyWidgetType.weather:
        return Padding(padding: const EdgeInsets.all(6), child: _weather());
      case StandbyWidgetType.calendar:
        return _calendar();
      case StandbyWidgetType.music:
        return Padding(padding: const EdgeInsets.all(6), child: _music());
      case StandbyWidgetType.timer:
        return _TimerSketch(
          style: settings.timerStyle,
          color: settings.timerColor,
          figure: settings.timerFigureColor,
        );
      case StandbyWidgetType.summary:
        // the real Summary card at a normal size, shrunk into the frame (its
        // weather, music and timer are still sketches)
        return FittedBox(
          child: SizedBox(
            width: 480,
            height: 330,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SummaryCard(
                now: _when,
                settings: settings,
                weather: _weather(),
                music: _music(),
                timer: _TimerSketch(
                  style: settings.timerStyle,
                  color: settings.timerColor,
                  figure: settings.timerFigureColor,
                ),
              ),
            ),
          ),
        );
    }
  }
}
