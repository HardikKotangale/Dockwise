// Frame times while each Summary tile alone (O and T), in the
// real app. Run like card_switch_perf_test.dart.
//
//   flutter drive --profile -d windows \
//     --driver test_driver/perf_driver.dart \
//     --target integration_test/card_switch_perf_test.dart
//
// Add --dart-define=FULLSCREEN=true to measure on a PC in full screen. The app
// starts with
// its own settings in memory: the ones saved on the device are not touched.
// The summary (build and raster times, missed frames) is in
// build/integration_response_data.json.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';

const _fullscreen = bool.fromEnvironment('FULLSCREEN');

// A key press straight into HardwareKeyboard, where Hushdock listens (the
// test key simulator has no key tables in a profile build).
void _press(LogicalKeyboardKey logical, PhysicalKeyboardKey physical) {
  final k = HardwareKeyboard.instance;
  k.handleKeyEvent(
    KeyDownEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    ),
  );
  k.handleKeyEvent(
    KeyUpEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    ),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('summary tiles one by one', (t) async {
    final layouts = {
      'all': 'v2:here,there,date,weather,music',
      'clocks': 'v2:here,there',
      'here': 'v2:here',
      'date': 'v2:date',
      'weather': 'v2:weather',
      'music': 'v2:music',
      'timer': 'v2:timer',
    };
    for (final e in layouts.entries) {
      final start = StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.summary,
        summaryLayout: e.value,
      );
      SharedPreferences.setMockInitialValues({
        'standby_settings_v1': jsonEncode(start.toJson()),
      });
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(const StandbyProApp(fitScreen: true));
      await Future<void>.delayed(const Duration(seconds: 3));
      for (var i = 0; i < 3; i++) {
        await binding.watchPerformance(() async {
          _press(LogicalKeyboardKey.keyS, PhysicalKeyboardKey.keyS);
          await Future<void>.delayed(const Duration(milliseconds: 1800));
        }, reportKey: '${e.key}_open${i + 1}');
        await binding.watchPerformance(() async {
          _press(LogicalKeyboardKey.keyS, PhysicalKeyboardKey.keyS);
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }, reportKey: '${e.key}_close${i + 1}');
      }
    }
  });
}
