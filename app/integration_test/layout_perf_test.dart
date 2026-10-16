// Frame times while switching between one and two panels (O and T), in the
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

  testWidgets('switching between one and two panels', (t) async {
    const start = StandbySettings(
      layoutMode: StandbyLayoutMode.single,
      leftWidget: StandbyWidgetType.calendar,
      rightWidget: StandbyWidgetType.weather,
      showSeconds: true,
    );
    SharedPreferences.setMockInitialValues({
      'standby_settings_v1': jsonEncode(start.toJson()),
    });
    await t.pumpWidget(const StandbyProApp(fitScreen: true));
    if (_fullscreen) await StandbySystemService().setFullscreen(true);
    await Future<void>.delayed(const Duration(seconds: 3));

    // one -> two -> one ..., eight times; "1_two" is the first switch to two
    for (var i = 0; i < 8; i++) {
      await binding.watchPerformance(() async {
        i.isEven
            ? _press(LogicalKeyboardKey.keyT, PhysicalKeyboardKey.keyT)
            : _press(LogicalKeyboardKey.keyO, PhysicalKeyboardKey.keyO);
        await Future<void>.delayed(const Duration(milliseconds: 1800));
      }, reportKey: '${i ~/ 2 + 1}_${i.isEven ? 'two' : 'one'}');
    }

    if (_fullscreen) await StandbySystemService().setFullscreen(false);
  });
}
