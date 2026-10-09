import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/core/night_mode_policy.dart';
import 'package:standby_pro/src/core/room_light.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

/// A phone with (or without) a light sensor, remembering what brightness was set.
class _LightSystem extends StandbySystemService {
  double? lux;
  final set = <double>[];
  @override
  Future<double?> ambientLux() async => lux;
  @override
  Future<bool> setBrightness(double value) async {
    set.add(value);
    return true;
  }
}

void main() {
  test(
    'brightness rises with the room light, and never passes your maximum',
    () {
      double at(double lux) => roomBrightness(lux, 0.8);
      expect(at(0), closeTo(0.08, 0.001)); // pitch dark: very dim, not black
      expect(at(1), lessThan(at(10)));
      expect(at(10), lessThan(at(100)));
      expect(at(100), lessThan(at(1000)));
      expect(at(1000), closeTo(0.8, 0.001)); // daylight: your maximum
      expect(at(50000), closeTo(0.8, 0.001)); // never above it
      expect(roomBrightness(0, 0.1), 0.05); // and never fully off
    },
  );

  test('the dark-room test has two thresholds, so it does not flicker', () {
    expect(isDarkRoom(5, wasDark: false), isTrue); // gets dark: night look
    expect(
      isDarkRoom(12, wasDark: false),
      isFalse,
    ); // 12 is not dark enough to start...
    expect(
      isDarkRoom(12, wasDark: true),
      isTrue,
    ); // ...but stays dark once it is
    expect(isDarkRoom(25, wasDark: true), isFalse); // clearly lit again
  });

  test(
    'night look in a dark room, only if night mode and "when dark" are on',
    () {
      final noon = DateTime(2026, 10, 7, 12);
      const on = StandbySettings(nightModeEnabled: true);
      expect(NightModePolicy.shouldTint(noon, on), isFalse); // midday, lit room
      expect(
        NightModePolicy.shouldTint(noon, on, dark: true),
        isTrue,
      ); // dark room
      expect(
        NightModePolicy.shouldTint(
          noon,
          const StandbySettings(nightModeEnabled: true, nightByLight: false),
          dark: true,
        ),
        isFalse,
      ); // "also when the room is dark" is off
      expect(
        NightModePolicy.shouldTint(noon, const StandbySettings(), dark: true),
        isFalse,
      ); // night mode itself is off
    },
  );

  test(
    'the controller dims in a dark room and brightens with the light',
    () async {
      final system = _LightSystem();
      final c = StandbyController(
        systemService: system,
        autostartTicker: false,
        initialSettings: const StandbySettings(brightness: 0.8),
      );
      system.lux = 1; // a dark bedroom
      for (var i = 0; i < 6; i++) {
        await c.pollLight();
      }
      expect(system.set.last, lessThan(0.25));
      expect(c.roomDark, isTrue);

      system.lux = 800; // the lights come on
      for (var i = 0; i < 12; i++) {
        await c.pollLight();
      }
      expect(system.set.last, greaterThan(0.7));
      expect(c.roomDark, isFalse);
      // changes are applied in steps, not on every 2-second reading
      expect(system.set.length, lessThan(14));
    },
  );

  test(
    'without a light sensor (iPhone) or with auto off, brightness is left alone',
    () async {
      final noSensor = _LightSystem(); // lux stays null
      final c = StandbyController(
        systemService: noSensor,
        autostartTicker: false,
        initialSettings: const StandbySettings(),
      );
      await c.pollLight();
      expect(noSensor.set, isEmpty);
      expect(c.roomDark, isFalse);

      final sensor = _LightSystem()..lux = 1;
      final off = StandbyController(
        systemService: sensor,
        autostartTicker: false,
        initialSettings: const StandbySettings(autoBrightness: false),
      );
      await off.pollLight();
      expect(sensor.set, isEmpty); // auto brightness is off: the slider rules
    },
  );
}
