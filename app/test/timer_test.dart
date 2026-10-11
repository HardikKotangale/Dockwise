import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/timer_card.dart';
import 'package:standby_pro/src/features/standby/widgets/timer_entry.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  StandbyController make() {
    final c = StandbyController(
      autostartTicker: false,
      initialSettings: const StandbySettings(),
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'before it starts, +1 min and the presets change the starting length',
    () {
      final c = make();
      expect(c.timerLeftMs, 300000); // 5 minutes
      c.timerAdd(const Duration(minutes: 1));
      expect(c.settings.timerSeconds, 360);
      c.timerSet(600);
      expect(c.timerLeftMs, 600000);
      expect(c.timerStarted, isFalse);
    },
  );

  test('start, +1 min while running, pause keeps the time, reset clears', () {
    final c = make();
    c.timerSet(60);
    c.timerStart();
    expect(c.timerRunning, isTrue);
    expect(c.timerLeftMs, closeTo(60000, 200));
    c.timerAdd(const Duration(minutes: 1));
    expect(c.timerLeftMs, closeTo(120000, 200));
    c.timerPause();
    final paused = c.timerLeftMs;
    expect(c.timerRunning, isFalse);
    expect(c.timerStarted, isTrue); // paused, not reset
    expect(c.timerLeftMs, paused); // does not run down while paused
    c.timerReset();
    expect(c.timerStarted, isFalse);
    expect(c.timerLeftMs, 60000);
  });

  test('the timer style toggles and is saved with the settings', () {
    final c = make();
    expect(c.settings.timerStyle, TimerStyle.digital);
    c.toggleTimerStyle();
    expect(c.settings.timerStyle, TimerStyle.flip);
    final back = StandbySettings.fromJson(c.settings.toJson());
    expect(back.timerStyle, TimerStyle.flip);
    expect(back.timerSeconds, 300);
  });

  testWidgets('the card shows the time and the buttons, in both styles', (
    tester,
  ) async {
    final calls = <String>[];
    Widget card(TimerStyle style, {bool started = false}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 700,
          height: 400,
          child: TimerCard(
            settings: StandbySettings(timerStyle: style),
            leftMs: 300000,
            totalMs: 300000,
            running: false,
            started: started,
            done: false,
            onStart: () => calls.add('start'),
            onPause: () => calls.add('pause'),
            onReset: () => calls.add('reset'),
            onAdd: (m) => calls.add('add $m'),
            onPreset: (s) => calls.add('preset $s'),
            onType: () => calls.add('type'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(card(TimerStyle.digital));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('05'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.tap(find.text('+5 min'));
    await tester.tap(find.text('10 min'));
    await tester.tap(find.text('2 hr'));
    await tester.tap(find.text('Type'));
    expect(calls, ['start', 'add 5', 'preset 600', 'preset 7200', 'type']);

    await tester.pumpWidget(card(TimerStyle.flip));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Start'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing 1 5 0 0 on the number pad sets 15 minutes', (
    tester,
  ) async {
    final c = make();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 700,
            child: TimerEntry(controller: c, onDone: () {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600)); // it fades in
    Future<void> key(String k) async {
      await tester.tap(find.text(k));
      await tester.pump();
    }

    await key('1');
    await key('5');
    await key('0');
    await key('0');
    expect(c.settings.timerSeconds, 900);
    await key('0'); // 1 5 0 0 0 is 1:50:00
    expect(c.settings.timerSeconds, 6600);
    await tester.tap(find.bySemanticsLabel('Backspace'));
    await tester.pump();
    expect(c.settings.timerSeconds, 900);
  });

  test(
    '+1 min while running lengthens the run, so the runner keeps moving',
    () {
      final c = make();
      c.timerSet(300);
      c.timerStart();
      expect(c.timerTotalMs, 300000);
      c.timerAdd(const Duration(minutes: 1));
      // the total grew with the time left, so progress stays below 1 and the
      // figure on the track is not pinned at the start
      expect(c.timerTotalMs, 360000);
      expect(c.timerLeftMs / c.timerTotalMs, lessThan(1.0));
      c.timerPause();
      c.timerAdd(const Duration(minutes: 5));
      expect(c.timerTotalMs, 660000);
      c.timerReset();
      expect(c.timerTotalMs, 300000); // back to the starting length
    },
  );

  test('the end sound and vibration are saved with the settings', () {
    final c = make();
    expect(c.settings.timerSound, 'alarm');
    expect(c.settings.timerVibrate, isTrue);
    c.updateSettings(
      c.settings.copyWith(timerSound: 'fanfare', timerVibrate: false),
    );
    final back = StandbySettings.fromJson(c.settings.toJson());
    expect(back.timerSound, 'fanfare');
    expect(back.timerVibrate, isFalse);
  });

  testWidgets(
    'the number pad opens on the current length; backspace edits it',
    (tester) async {
      final c = make();
      c.timerSet(300); // 5:00
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 700,
              child: TimerEntry(controller: c, onDone: () => closed++),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600)); // it fades in
      expect(find.text('05'), findsOneWidget); // the minutes of 5:00 are shown
      await tester.tap(find.bySemanticsLabel('Backspace'));
      await tester.pump();
      expect(c.settings.timerSeconds, 50); // 5:00 -> 0:50: edited, not cleared
      // a swipe on the time goes back
      await tester.fling(
        find.text('Swipe up or down to go back'),
        const Offset(0, -200),
        1000,
      );
      expect(closed, 1);
    },
  );

  test('the timer has its own colors, separate from the clock', () {
    final c = make();
    expect(c.settings.timerColor, 0); // follows the clock until you pick one
    c.updateSettings(
      c.settings.copyWith(
        hoursColor: 0xFFFF453A, // the clock's hours: red
        timerColor: 0xFF30D158, // the timer's time: green
        timerFigureColor: 0xFFFF9F0A,
      ),
    );
    final back = StandbySettings.fromJson(c.settings.toJson());
    expect(back.timerColor, 0xFF30D158);
    expect(back.timerFigureColor, 0xFFFF9F0A);
    expect(back.hoursColor, 0xFFFF453A); // the clock keeps its own
  });
}
