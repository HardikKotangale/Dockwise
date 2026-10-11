import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
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
