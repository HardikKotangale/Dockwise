import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/core/motion/split_panels.dart';
import 'package:standby_pro/src/data/settings_repository.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/standby_screen.dart';
import 'package:standby_pro/src/features/standby/widgets/dock.dart';
import 'package:standby_pro/src/features/standby/widgets/timer_entry.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

// A PC: the keyboard does what a swipe or a tap does, F11 is full screen.
class _FakePc extends StandbySystemService {
  final fullscreen = <bool>[];
  // answered here: an unanswered platform call never ends in a widget test,
  // and full screen is applied right after it
  @override
  Future<bool> setKeepAwake(bool enabled) async => true;
  @override
  Future<bool> setFullscreen(bool enabled) async {
    fullscreen.add(enabled);
    return true;
  }
}

const _start = StandbySettings(
  layoutMode: StandbyLayoutMode.single,
  leftWidget: StandbyWidgetType.clock,
  clockStyle: ClockStyle.digital,
  nightModeEnabled: true,
  nightStartMin: 0,
  nightEndMin: 0, // no night hours: the night look is off until N
);

Future<StandbySettings> _saved() async =>
    SettingsRepository(await SharedPreferences.getInstance()).load();

Future<void> _key(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600)); // the save, the springs
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final pc = TargetPlatformVariant({TargetPlatform.windows, TargetPlatform.macOS});

  Future<_FakePc> pumpPc(WidgetTester t, {Widget? over}) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final fake = _FakePc();
    await t.pumpWidget(
      over == null
          ? StandbyProApp(initialSettings: _start, systemService: fake)
          : MaterialApp(
              home: Stack(
                children: [
                  StandbyScreen(initialSettings: _start, systemService: fake),
                  over,
                ],
              ),
            ),
    );
    await t.pump();
    return fake;
  }

  testWidgets('arrows change the card and the clock style like swipes', (
    t,
  ) async {
    await pumpPc(t);
    await _key(t, LogicalKeyboardKey.arrowRight);
    expect((await _saved()).leftWidget, StandbyWidgetType.weather);
    await _key(t, LogicalKeyboardKey.arrowLeft);
    expect((await _saved()).leftWidget, StandbyWidgetType.clock);
    await _key(t, LogicalKeyboardKey.arrowUp);
    expect((await _saved()).clockStyle, ClockStyle.analog); // the next style
    await _key(t, LogicalKeyboardKey.arrowDown);
    expect((await _saved()).clockStyle, ClockStyle.digital);
    await t.pumpWidget(const SizedBox());
  }, variant: pc);

  testWidgets('1, 2 and D pick the panels; Shift moves the second card', (
    t,
  ) async {
    await pumpPc(t);
    await _key(t, LogicalKeyboardKey.digit2);
    var s = await _saved();
    expect(s.layoutMode, StandbyLayoutMode.duo);
    final left = s.leftWidget, right = s.rightWidget;
    // Shift + → : the second card moves on, the first stays
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _key(t, LogicalKeyboardKey.arrowRight);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    s = await _saved();
    expect(s.leftWidget, left);
    expect(s.rightWidget, isNot(right));
    // plain → : the first card
    await _key(t, LogicalKeyboardKey.arrowRight);
    expect((await _saved()).leftWidget, isNot(left));
    await _key(t, LogicalKeyboardKey.digit1);
    expect((await _saved()).layoutMode, StandbyLayoutMode.single);
    await _key(t, LogicalKeyboardKey.keyD);
    expect((await _saved()).layoutMode, StandbyLayoutMode.duo);
    await _key(t, LogicalKeyboardKey.keyD);
    expect((await _saved()).layoutMode, StandbyLayoutMode.single);
    await t.pumpWidget(const SizedBox());
  }, variant: pc);

  testWidgets('F11 goes full screen and Esc leaves it; it is saved', (t) async {
    final fake = await pumpPc(t);
    await _key(t, LogicalKeyboardKey.f11);
    expect(fake.fullscreen, [true]);
    expect((await _saved()).fullscreen, isTrue);
    await _key(t, LogicalKeyboardKey.escape);
    expect(fake.fullscreen, [true, false]);
    expect((await _saved()).fullscreen, isFalse);
    await t.pumpWidget(const SizedBox());
  }, variant: pc);

  testWidgets('S opens the settings dock, Esc closes it first', (t) async {
    final fake = await pumpPc(t);
    expect(find.byType(Dock), findsNothing);
    await _key(t, LogicalKeyboardKey.keyS);
    expect(find.byType(Dock), findsOneWidget);
    // the cards stay put while the dock is open
    await _key(t, LogicalKeyboardKey.arrowRight);
    expect((await _saved()).leftWidget, StandbyWidgetType.clock);
    await _key(t, LogicalKeyboardKey.escape);
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(Dock), findsNothing);
    expect(fake.fullscreen, isEmpty); // Esc closed the dock, nothing else
    await t.pumpWidget(const SizedBox());
  }, variant: pc);

  testWidgets('? shows the keys, and again hides them', (t) async {
    await pumpPc(t);
    await _key(t, LogicalKeyboardKey.f1);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Turn full screen on or off'), findsOneWidget);
    await _key(t, LogicalKeyboardKey.slash);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Keyboard shortcuts'), findsNothing);
    await t.pumpWidget(const SizedBox());
  }, variant: pc);

  testWidgets('N turns the night look on and off', (t) async {
    await pumpPc(t);
    final tinted = find.byWidgetPredicate(
      (w) => w is ColorFiltered && w.child is Transform,
    );
    expect(tinted, findsNothing);
    await _key(t, LogicalKeyboardKey.keyN);
    expect(tinted, findsOneWidget);
    await _key(t, LogicalKeyboardKey.keyN);
    expect(tinted, findsNothing);
    await t.pumpWidget(const SizedBox());
  }, variant: pc);

  testWidgets('typing in a text field never fires a shortcut', (t) async {
    await pumpPc(
      t,
      over: const Positioned(
        left: 0,
        top: 0,
        width: 300,
        child: Material(child: TextField(autofocus: true)),
      ),
    );
    await _key(t, LogicalKeyboardKey.arrowRight);
    await _key(t, LogicalKeyboardKey.keyS);
    expect(find.byType(Dock), findsNothing);
    expect((await _saved()).leftWidget, StandbyWidgetType.clock);
    await t.pumpWidget(const SizedBox());
  }, variant: pc);

  testWidgets('the timer pad types from the keyboard', (t) async {
    final c = StandbyController(
      initialSettings: const StandbySettings(timerSeconds: 300),
      autostartTicker: false,
    );
    addTearDown(c.dispose);
    var done = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: TimerEntry(controller: c, onDone: () => done++),
          ),
        ),
      ),
    );
    for (final k in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.numpad0, // the keypad types too
      LogicalKeyboardKey.digit0,
    ]) {
      await t.sendKeyEvent(k);
    }
    await t.pump();
    expect(c.settings.timerSeconds, 15 * 60); // 1 5 0 0 = 15:00
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pump();
    expect(c.settings.timerSeconds, 60 + 50); // 1 5 0 = 1:50
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(done, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('while the timer pad is open, 2 types, not two panels', (
    t,
  ) async {
    final pad = StandbyController(autostartTicker: false);
    addTearDown(pad.dispose);
    await pumpPc(
      t,
      over: Positioned(
        left: 0,
        top: 0,
        width: 800,
        height: 600,
        child: Material(
          child: TimerEntry(controller: pad, onDone: () {}),
        ),
      ),
    );
    await _key(t, LogicalKeyboardKey.digit2);
    // the screen still shows one panel (the pad's own controller saves
    // settings too, so look at the screen, not at what was saved)
    expect(
      find.byWidgetPredicate((w) => w is SplitPanels && w.duo),
      findsNothing,
    );
    expect(pad.settings.timerSeconds, 2); // it typed a 2 instead
    await t.pumpWidget(const SizedBox());
  }, variant: pc);

  testWidgets('F11 does nothing on a phone', (t) async {
    final phone = _FakePc();
    await t.pumpWidget(
      StandbyProApp(initialSettings: _start, systemService: phone),
    );
    await _key(t, LogicalKeyboardKey.f11);
    expect(phone.fullscreen, isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  test('Space starts and pauses the timer when it is on screen', () {
    final c = StandbyController(
      initialSettings: const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.timer,
      ),
      autostartTicker: false,
    );
    expect(c.playPauseShown(), isTrue);
    expect(c.timerRunning, isTrue);
    expect(c.playPauseShown(), isTrue);
    expect(c.timerRunning, isFalse);
    c.dispose();
  });

  test('Space does nothing without music or a timer on screen', () {
    final c = StandbyController(
      initialSettings: const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.clock,
      ),
      autostartTicker: false,
    );
    expect(c.playPauseShown(), isFalse);
    c.dispose();
  });

  test('full screen survives a save and a restart', () {
    const s = StandbySettings(fullscreen: true);
    expect(StandbySettings.fromJson(s.toJson()).fullscreen, isTrue);
    expect(StandbySettings.fromJson(const {}).fullscreen, isFalse);
  });
}
