import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/motion/motion.dart';
import '../../../core/palette.dart';
import '../../../domain/standby_models.dart';
import '../../../services/weather_service.dart';
import '../../../state/standby_controller.dart';
import '../widgets/dock.dart';
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
    final settings = controller.settings;
    return ListView(
      padding: dockPadding,
      children: [
        EnumPicker<CalendarStyle>(
          label: 'View',
          value: settings.calendarStyle,
          values: CalendarStyle.values,
          display: (v) => v == CalendarStyle.day ? 'Today' : 'Whole month',
          onChanged: (v) =>
              controller.updateSettings(settings.copyWith(calendarStyle: v)),
        ),
        const Text(
          'Tip: swipe up or down on the calendar to switch.',
          style: TextStyle(color: Colors.white54),
        ),
        TextButton(onPressed: onAll, child: const Text('All settings')),
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
  });

  final StandbyController controller;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final problem = controller.weatherProblem;
    return ListView(
      padding: dockPadding,
      children: [
        const Text(
          'Weather uses this phone\'s location.',
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
        TextButton(onPressed: onAll, child: const Text('All settings')),
      ],
    );
  }
}

/// A row of colors with "Auto" first: the same swatches as the clock's.
class ColorRow extends StatelessWidget {
  const ColorRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.autoLabel = 'Auto',
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String autoLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: Text(autoLabel),
                selected: value == 0,
                onSelected: (_) => onChanged(0),
              ),
              for (final c in clockPalette)
                Semantics(
                  button: true,
                  selected: value == c.argb,
                  label: '$label ${c.name}',
                  child: GestureDetector(
                    onTap: () => onChanged(c.argb),
                    child: AnimatedContainer(
                      duration: calm(context, Motion.fast),
                      curve: easeOutStrong,
                      width: 38,
                      height: 38,
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
        ],
      ),
    );
  }
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
        EnumPicker<TimerStyle>(
          label: 'Style',
          value: settings.timerStyle,
          values: TimerStyle.values,
          display: (v) => v == TimerStyle.digital ? 'Digital' : 'Flip',
          onChanged: (v) => set(settings.copyWith(timerStyle: v)),
        ),
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
        TextButton(onPressed: onAll, child: const Text('All settings')),
      ],
    );
  }
}
