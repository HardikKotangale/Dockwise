// Frame times while the settings dock beside a card, and scrolling the key list (O and T), in the
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

  Future<void> dockRound(WidgetTester t, StandbyWidgetType type) async {
    const start = StandbySettings(layoutMode: StandbyLayoutMode.single);
    SharedPreferences.setMockInitialValues({
      'standby_settings_v1': jsonEncode(
        start.copyWith(leftWidget: type).toJson(),
      ),
    });
    await t.pumpWidget(const StandbyProApp(fitScreen: true));
    await Future<void>.delayed(const Duration(seconds: 3));
    for (var i = 0; i < 3; i++) {
      await binding.watchPerformance(() async {
        _press(LogicalKeyboardKey.keyS, PhysicalKeyboardKey.keyS);
        await Future<void>.delayed(const Duration(milliseconds: 1800));
      }, reportKey: '${i + 1}_open_${type.name}');
      await binding.watchPerformance(() async {
        _press(LogicalKeyboardKey.keyS, PhysicalKeyboardKey.keyS);
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }, reportKey: '${i + 1}_close_${type.name}');
    }
  }

  testWidgets('settings dock beside a card', (t) async {
    await dockRound(t, StandbyWidgetType.calendar);
    await dockRound(t, StandbyWidgetType.summary);
  });

  testWidgets('swiping a card with the settings dock open', (t) async {
    const start = StandbySettings(
      layoutMode: StandbyLayoutMode.single,
      leftWidget: StandbyWidgetType.calendar,
    );
    SharedPreferences.setMockInitialValues({
      'standby_settings_v1': jsonEncode(start.toJson()),
    });
    await t.pumpWidget(const StandbyProApp(fitScreen: true));
    await Future<void>.delayed(const Duration(seconds: 3));
    _press(LogicalKeyboardKey.keyS, PhysicalKeyboardKey.keyS);
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    // the card is the left part of the screen while the dock is open
    final size = t.view.physicalSize / t.view.devicePixelRatio;
    final at = Offset(size.width * 0.25, size.height * 0.5);
    final moves = {
      'up': const Offset(0, -240),
      'down': const Offset(0, 240),
      'left': const Offset(-260, 0),
      'right': const Offset(260, 0),
    };
    for (var round = 0; round < 2; round++) {
      for (final e in moves.entries) {
        await binding.watchPerformance(() async {
          await t.flingFrom(at, e.value, 1500);
          await t.pump(const Duration(milliseconds: 1500));
        }, reportKey: '${round + 1}_swipe_${e.key}_dock_open');
      }
    }
  });

  testWidgets('scrolling the keyboard list', (t) async {
    const start = StandbySettings(layoutMode: StandbyLayoutMode.single);
    SharedPreferences.setMockInitialValues({
      'standby_settings_v1': jsonEncode(start.toJson()),
    });
    await t.pumpWidget(const StandbyProApp(fitScreen: true));
    await Future<void>.delayed(const Duration(seconds: 3));
    _press(LogicalKeyboardKey.f1, PhysicalKeyboardKey.f1);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final list = find.byType(SingleChildScrollView).last;
    for (var i = 0; i < 4; i++) {
      await binding.watchPerformance(() async {
        await t.fling(list, const Offset(0, -700), 2500);
        await t.pump(const Duration(seconds: 2));
      }, reportKey: '${i + 1}_scroll_down');
      await binding.watchPerformance(() async {
        await t.fling(list, const Offset(0, 700), 2500);
        await t.pump(const Duration(seconds: 2));
      }, reportKey: '${i + 1}_scroll_up');
    }
  });
}
