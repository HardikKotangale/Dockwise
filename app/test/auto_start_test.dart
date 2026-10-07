import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/integration_cards.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

/// Stands in for the Android side: records calls, replays scripted answers.
class _FakeAndroid extends StandbySystemService {
  final configured =
      <({bool enabled, double lean, bool landscape, bool exit})>[];
  final probe = <bool>[];
  var overlayOpened = 0;
  AutoStartStatus status = (
    overlay: false,
    notifications: true,
    battery: false,
    running: false,
  );
  PostureNow? posture = (lean: 62.0, roll: 88.0, matches: true);

  @override
  Future<bool> configureAutoStart({
    required bool enabled,
    required double leanDeg,
    required bool landscapeOnly,
    required bool exitOnUnplug,
  }) async {
    configured.add((
      enabled: enabled,
      lean: leanDeg,
      landscape: landscapeOnly,
      exit: exitOnUnplug,
    ));
    return true;
  }

  @override
  Future<AutoStartStatus> autoStartStatus() async => status;

  @override
  Future<bool> openOverlaySettings() async {
    overlayOpened++;
    status = (
      overlay: true,
      notifications: true,
      battery: false,
      running: false,
    );
    return true;
  }

  @override
  Future<bool> postureProbe(bool on) async {
    probe.add(on);
    return true;
  }

  @override
  Future<PostureNow?> postureNow({
    required double leanDeg,
    required bool landscapeOnly,
  }) async => posture;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('auto-start settings default to landscape, 40 degrees, off', () {
    const s = StandbySettings();
    expect(s.autoStart, isFalse);
    expect(s.autoLeanDeg, 40);
    expect(s.autoLandscapeOnly, isTrue);
    expect(s.autoExitOnUnplug, isTrue);
    final back = StandbySettings.fromJson(
      const StandbySettings(
        autoStart: true,
        autoLeanDeg: 55,
        autoLandscapeOnly: false,
        autoExitOnUnplug: false,
      ).toJson(),
    );
    expect(back.autoStart, isTrue);
    expect(back.autoLeanDeg, 55);
    expect(back.autoLandscapeOnly, isFalse);
    expect(back.autoExitOnUnplug, isFalse);
  });

  test('auto-start reaches Android only when its settings change', () async {
    SharedPreferences.setMockInitialValues({});
    final android = _FakeAndroid();
    final c = StandbyController(
      systemService: android,
      autostartTicker: false,
      initialSettings: const StandbySettings(),
    );

    await c.updateSettings(c.settings.copyWith(autoStart: true));
    expect(android.configured, hasLength(1));
    expect(android.configured.single.enabled, isTrue);
    expect(android.configured.single.lean, 40);
    expect(android.configured.single.landscape, isTrue);

    // an unrelated setting must not restart the Android watcher
    await c.updateSettings(c.settings.copyWith(fontScale: 0.8));
    expect(android.configured, hasLength(1));

    await c.updateSettings(c.settings.copyWith(autoLeanDeg: 55));
    expect(android.configured, hasLength(2));
    expect(android.configured.last.lean, 55);

    await c.updateSettings(c.settings.copyWith(autoStart: false));
    expect(android.configured.last.enabled, isFalse);
    c.dispose();
  });

  testWidgets(
    'Auto-start section: checklist, live tilt, and sensor off on exit',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final android = _FakeAndroid();
      await tester.pumpWidget(
        StandbyProApp(
          systemService: android,
          initialSettings: const StandbySettings(
            layoutMode: StandbyLayoutMode.single,
            leftWidget: StandbyWidgetType.calendar,
            autoStart: true,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(CalendarCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All settings'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(); // the first status answer arrives, then it redraws

      expect(find.text('Auto-start'), findsOneWidget);
      await tester.ensureVisible(find.text('Display over other apps'));
      await tester.pump(const Duration(milliseconds: 700));

      // checklist: overlay and battery still missing, notifications fine
      expect(find.text('Display over other apps'), findsOneWidget);
      expect(find.text('Battery: Unrestricted'), findsOneWidget);
      expect(find.text('Allow'), findsNWidgets(2));
      expect(find.byIcon(Icons.check_circle), findsWidgets);

      // live tilt reading, and it says it would start
      expect(find.textContaining('leaning 62°'), findsOneWidget);
      expect(find.textContaining('landscape'), findsWidgets);
      expect(find.textContaining('would start'), findsOneWidget);

      // the Allow button opens the system screen; the list refreshes on its own
      await tester.tap(find.widgetWithText(FilledButton, 'Allow').first);
      await tester.pump(const Duration(milliseconds: 700));
      expect(android.overlayOpened, 1);
      expect(find.text('Allow'), findsOneWidget); // only battery is left

      // the tilt sensor was started for this screen...
      expect(android.probe.first, isTrue);
      // ...and is switched off again when it goes away (no battery use)
      await tester.pumpWidget(const SizedBox());
      expect(android.probe.last, isFalse);
    },
  );

  testWidgets('not propped up yet is shown as such', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final android = _FakeAndroid()
      ..posture = (lean: 5.0, roll: 10.0, matches: false);
    await tester.pumpWidget(
      StandbyProApp(
        systemService: android,
        initialSettings: const StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.calendar,
          autoStart: true,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(CalendarCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All settings'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(); // the first status answer arrives, then it redraws
    await tester.ensureVisible(find.text('Display over other apps'));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.textContaining('leaning 5°'), findsOneWidget);
    expect(find.textContaining('portrait'), findsOneWidget);
    expect(find.textContaining('Not propped up'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
