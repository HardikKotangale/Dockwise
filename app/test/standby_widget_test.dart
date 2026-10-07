import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:standby_pro/src/services/city_search.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/core/clock_cadence.dart';
import 'package:standby_pro/src/core/pinch_layout.dart';
import 'package:standby_pro/src/features/standby/widgets/battery_badge.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/state/standby_controller.dart';
import 'package:standby_pro/src/features/standby/widgets/clock_faces.dart';
import 'package:standby_pro/src/features/standby/widgets/integration_cards.dart';
import 'package:standby_pro/src/features/standby/widgets/weather_scene.dart';
import 'package:intl/intl.dart';
import 'package:standby_pro/src/services/weather_service.dart';

void main() {
  testWidgets('renders the StandBy screen with duo widgets and customization', (
    tester,
  ) async {
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.duo,
          activeThemeId: 'aurora',
          leftWidget: StandbyWidgetType.clock,
          rightWidget: StandbyWidgetType.weather,
          clockStyle: ClockStyle.digital,
        ),
      ),
    );

    await tester.pump();

    expect(find.textContaining('Loading weather'), findsOneWidget);
  });

  testWidgets('single focus mode shows the configured clock face', (
    tester,
  ) async {
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          clockStyle: ClockStyle.flip,
          leftWidget: StandbyWidgetType.clock,
          rightWidget: StandbyWidgetType.music,
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(FlipClockFace), findsOneWidget);
    expect(find.text('Flip'), findsNothing); // no label above the tiles
    expect(find.text('Music'), findsNothing);
  });

  testWidgets('customization sheet exposes widget and clock controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const StandbyProApp(initialSettings: StandbySettings()),
    );

    // tapping the weather panel opens its settings; "All settings" has the rest
    await tester.tap(find.textContaining('Loading weather'));
    await tester.pumpAndSettle();
    expect(find.text('Temperature in °F'), findsOneWidget);
    await tester.tap(find.text('All settings'));
    await tester.pumpAndSettle();

    for (final t in [
      'Layout',
      'Left widget',
      'Right widget',
      'Clock',
      'Style',
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    // the same clock choices as the Clock panel: presets and per-part colors
    for (final t in ['Presets', 'Clock colors', 'Options']) {
      await tester.scrollUntilVisible(
        find.text(t),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.scrollUntilVisible(
      find.text('OLED burn-in protection'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('OLED burn-in protection'), findsOneWidget);
  });

  testWidgets('world clock shows exactly two times, 12-hour with AM/PM', (
    tester,
  ) async {
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          clockStyle: ClockStyle.world,
          use24HourTime: false,
          worldZone: 'Asia/Tokyo',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Local'), findsOneWidget);
    expect(find.textContaining('Tokyo'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'AM' || w.data == 'PM'),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('tapping the clock opens clock settings with 12/24h and styles', (
    tester,
  ) async {
    await tester.pumpWidget(
      const StandbyProApp(initialSettings: StandbySettings()),
    );

    await tester.tap(find.byType(FittedBox).first);
    await tester.pumpAndSettle();

    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Frame'), findsOneWidget);
    expect(find.text('Clock colors'), findsOneWidget);
    expect(find.text('Blue & white'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('24-hour time'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('24-hour time'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('All settings'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('All settings'), findsOneWidget);
  });

  test('city search finds zones offline', () {
    expect(searchZones('tok'), contains('Asia/Tokyo'));
    expect(searchZones('new york').first, 'America/New_York');
    expect(searchZones(''), isEmpty);
    expect(zoneLabel('America/Argentina/Buenos_Aires'), 'Buenos Aires');
  });

  testWidgets('world clock has no default city and prompts for one', (
    tester,
  ) async {
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          clockStyle: ClockStyle.world,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tap to add a city'), findsOneWidget);
  });

  testWidgets('swiping a panel sideways flips it to the next widget', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const StandbyProApp(initialSettings: StandbySettings()),
    );
    await tester.pump();
    expect(find.textContaining('Loading weather'), findsOneWidget);

    await tester.fling(
      find.textContaining('Loading weather'),
      const Offset(-300, 0),
      1500,
    );
    // settings are saved through real async prefs I/O before the UI updates
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Loading weather'), findsNothing);
  });

  for (final size in [
    const Size(190, 380),
    const Size(330, 400),
    const Size(420, 300),
  ]) {
    testWidgets('music card never overflows at ${size.width}x${size.height}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: size,
                child: MusicCard(
                  snapshot: const NowPlayingSnapshot(
                    title: 'A very long song title that must be cut off',
                    artist: 'An artist',
                    source: 'Spotify',
                    progress: 0.3,
                    isPlaying: true,
                    isControllable: true,
                    durationMs: 180000,
                    positionMs: 54000,
                  ),
                  settings: const StandbySettings(),
                  onCommand: (_) async => true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull); // overflow would throw here
      expect(find.byTooltip('Pause'), findsOneWidget);
    });
  }

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 360, height: 360, child: child)),
  );

  testWidgets('date card shows only the weekday, day number and month', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        CalendarCard(
          settings: const StandbySettings(),
          now: DateTime(2026, 10, 6),
        ),
      ),
    );

    expect(find.text('TUESDAY'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
  });

  testWidgets('weather card shows city and converts to Fahrenheit', (
    tester,
  ) async {
    final snap = WeatherSnapshot(
      city: 'Pune',
      condition: 'Clear',
      temperatureCelsius: 20,
      highCelsius: 25,
      lowCelsius: 15,
      updatedAt: DateTime(2026),
      code: 0,
    );
    await tester.pumpWidget(
      host(
        WeatherCard(
          snapshot: snap,
          settings: const StandbySettings(fahrenheit: true),
        ),
      ),
    );

    expect(find.text('Pune'), findsOneWidget);
    expect(find.text('68°'), findsOneWidget); // 20C
    expect(find.text('H:77°   L:59°'), findsOneWidget);
  });

  testWidgets('weather card explains a missing location permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const WeatherCard(
          snapshot: null,
          settings: StandbySettings(),
          problem: WeatherProblem.permission,
        ),
      ),
    );

    expect(find.textContaining('Allow location'), findsOneWidget);
  });

  testWidgets('city search types on our own keyboard, no system keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(clockStyle: ClockStyle.world),
      ),
    );
    await tester.pump();

    // no second city yet: tapping the clock goes straight to the search + keyboard
    await tester.tap(find.text('Tap to add a city'));
    await tester.pumpAndSettle();

    final screen = const Rect.fromLTWH(0, 0, 400, 800);
    expect(screen.contains(tester.getCenter(find.text('q'))), isTrue);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);

    for (final k in ['t', 'o', 'k']) {
      await tester.tap(find.text(k));
    }
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'tok',
    );
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'to',
    );

    // tear the page down so the search debounce timer is cancelled
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'with a second city set, tapping the clock opens clock settings',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const StandbyProApp(
          initialSettings: StandbySettings(
            clockStyle: ClockStyle.world,
            worldZone: 'Asia/Tokyo',
            worldCity: 'Tokyo',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(FittedBox).first);
      await tester.pumpAndSettle();
      expect(
        find.text('Clock'),
        findsWidgets,
      ); // the settings dock, not the search
      expect(find.byType(TextField), findsNothing);
    },
  );

  test('worldwide city search maps timezone, name and region', () async {
    final client = MockClient(
      (request) async => http.Response(
        '{"results":[{"name":"Boston","admin1":"Massachusetts",'
        '"country":"United States","timezone":"America/New_York"},'
        '{"name":"No zone","country":"X"}]}',
        200,
      ),
    );

    final found = await searchCities('bos', client: client);

    expect(found, hasLength(1)); // entries without a timezone are dropped
    expect(found.first.name, 'Boston');
    expect(found.first.region, 'Massachusetts, United States');
    expect(found.first.timezone, 'America/New_York');
    expect(await searchCities('b', client: client), isEmpty); // too short
  });

  test('weather code maps to the right animated scene', () {
    expect(sceneFor(0, true).sun, isTrue);
    expect(sceneFor(0, false).stars, isTrue);
    expect(sceneFor(3, true).clouds, 3);
    expect(sceneFor(61, true).precip, Precip.rain);
    expect(sceneFor(73, true).precip, Precip.snow);
    expect(sceneFor(95, true).lightning, isTrue);
    expect(sceneFor(45, true).fog, isTrue);
    expect(sceneFor(null, true).sun, isTrue);
  });

  testWidgets('every weather scene paints and stops its animation timer', (
    tester,
  ) async {
    for (final code in [0, 2, 3, 45, 53, 63, 73, 95]) {
      for (final day in [true, false]) {
        await tester.pumpWidget(host(WeatherScene(spec: sceneFor(code, day))));
        await tester.pump(const Duration(milliseconds: 500)); // animate
        expect(tester.takeException(), isNull);
      }
    }
    // removing the scene must cancel its timer (test fails on a pending timer)
    await tester.pumpWidget(const SizedBox());
  });

  test('month grid pads full weeks and starts on the right weekday', () {
    final cells = monthCells(DateTime(2026, 10, 6)); // 1 Oct 2026 = Thursday
    expect(cells.length % 7, 0);
    expect(cells.take(4), everyElement(isNull)); // Sun..Wed blank
    expect(cells[4], 1);
    expect(cells.whereType<int>().length, 31);
    expect(monthCells(DateTime(2026, 2, 1)).whereType<int>().length, 28);
  });

  testWidgets('month calendar shows every day with today highlighted', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        CalendarCard(
          settings: const StandbySettings(calendarStyle: CalendarStyle.month),
          now: DateTime(2026, 10, 6),
        ),
      ),
    );

    expect(find.text('OCTOBER'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('S'), findsNWidgets(2)); // Sunday + Saturday initials
  });

  testWidgets('swiping the calendar flips between today and the month', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.calendar,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('31'), findsNothing); // day view: only today's number

    await tester.fling(find.byType(CalendarCard), const Offset(0, -300), 1500);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CalendarCard), findsOneWidget);
    expect(
      find.text(DateFormat('MMMM').format(DateTime.now()).toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets('two-color clock paints hours white and minutes blue', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ClockFace(
          time: DateTime(2026, 10, 6, 10, 25),
          settings: const StandbySettings(
            use24HourTime: true,
            hoursColor: 0xFFFFFFFF,
            minutesColor: 0xFF0A84FF,
          ),
        ),
      ),
    );

    final root = tester.widget<RichText>(find.byType(RichText).first).text;
    final spans = <TextSpan>[];
    root.visitChildren((s) {
      if (s is TextSpan && s.text != null) spans.add(s);
      return true;
    });
    Color? colorOf(String text) =>
        spans.firstWhere((s) => s.text == text).style?.color;

    expect(colorOf('10'), const Color(0xFFFFFFFF)); // hours: white (Midnight)
    expect(colorOf('25'), const Color(0xFF0A84FF)); // minutes: blue
  });

  testWidgets('clock stays one color when two-color is off', (tester) async {
    await tester.pumpWidget(
      host(
        ClockFace(
          time: DateTime(2026, 10, 6, 10, 25),
          settings: const StandbySettings(use24HourTime: true),
        ),
      ),
    );

    final root = tester.widget<RichText>(find.byType(RichText).first).text;
    final colors = <Color?>{};
    root.visitChildren((s) {
      if (s is TextSpan && (s.text == '10' || s.text == '25')) {
        colors.add(s.style?.color);
      }
      return true;
    });
    expect(colors, hasLength(1));
  });

  test('two-color setting survives save and load', () {
    const original = StandbySettings(
      hoursColor: 0xFFFFFFFF,
      minutesColor: 0xFF0A84FF,
      colonColor: 0xFFFF453A,
      detailColor: 0xFF30D158,
    );
    final restored = StandbySettings.fromJson(original.toJson());
    expect(restored, original);
    expect(restored.minutesColor, 0xFF0A84FF);
    expect(restored.detailColor, 0xFF30D158);
    expect(const StandbySettings().hoursColor, 0); // default: follow theme
  });

  testWidgets('Blue & white colors the hours white and the minutes blue', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          activeThemeId: 'solar', // orange theme: hours would be orange
          use24HourTime: true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(FittedBox).first); // clock panel
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Blue & white'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blue & white'));
    await tester.pumpAndSettle();

    final spans = <TextSpan>[];
    tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text)
        .forEach(
          (root) => root.visitChildren((s) {
            if (s is TextSpan && s.text != null) spans.add(s);
            return true;
          }),
        );
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final hours = spans.firstWhere((s) => s.text == two(now.hour));
    final minutes = spans.firstWhere((s) => s.text == two(now.minute));
    expect(hours.style?.color, const Color(0xFFFFFFFF)); // white offered
    expect(minutes.style?.color, const Color(0xFF0A84FF));
    expect(clockPalette.first.argb, 0xFFFFFFFF); // white is the first swatch
  });

  test('each clock style exposes only the parts it draws', () {
    expect(ClockStyle.digital.parts, [
      ClockPart.hours,
      ClockPart.colon,
      ClockPart.minutes,
      ClockPart.detail,
    ]);
    // only World (city names) and Frame (seconds ring) have a label part
    expect(ClockStyle.world.parts, contains(ClockPart.label));
    final withLabel = {ClockStyle.world, ClockStyle.frame};
    for (final style in ClockStyle.values.where(
      (x) => !withLabel.contains(x),
    )) {
      expect(style.parts, isNot(contains(ClockPart.label)), reason: '$style');
    }
    expect(ClockStyle.world.partLabel(ClockPart.label), 'City names');
    expect(ClockStyle.frame.parts, contains(ClockPart.label)); // the ring
    expect(ClockStyle.frame.partLabel(ClockPart.label), 'Tick color');
    expect(ClockStyle.values.map((x) => x.name), isNot(contains('solar')));
    expect(ClockStyle.text.parts, isNot(contains(ClockPart.colon)));
    expect(ClockStyle.float.parts, isNot(contains(ClockPart.colon)));
    expect(ClockStyle.analog.partLabel(ClockPart.hours), 'Hour hand');
    expect(ClockStyle.flip.partLabel(ClockPart.minutes), 'Minutes tile');
    expect(ClockStyle.text.partLabel(ClockPart.hours), 'Hour word');
  });

  test('digital, mono, analog and flip can show seconds', () {
    final can = [
      for (final s in ClockStyle.values)
        if (s.supportsSeconds) s,
    ];
    expect(can, [
      ClockStyle.digital,
      ClockStyle.analog,
      ClockStyle.mono,
      ClockStyle.flip,
    ]);
    // a stale "show seconds" never ticks a style that cannot show them
    expect(
      const StandbySettings(
        showSeconds: true,
        clockStyle: ClockStyle.text,
      ).secondsVisible,
      isFalse,
    );
    expect(
      const StandbySettings(showSeconds: true).secondsVisible,
      isTrue, // digital, clock on the left
    );
    // ...nor when no clock is on screen
    expect(
      const StandbySettings(
        showSeconds: true,
        leftWidget: StandbyWidgetType.weather,
        rightWidget: StandbyWidgetType.music,
      ).secondsVisible,
      isFalse,
    );
  });

  test('AM/PM color row appears only when there is an AM/PM to color', () {
    expect(
      const StandbySettings(use24HourTime: true).colorParts,
      isNot(contains(ClockPart.detail)),
    );
    expect(
      const StandbySettings(use24HourTime: false).colorParts,
      contains(ClockPart.detail),
    );
    expect(
      const StandbySettings(use24HourTime: true, showSeconds: true).colorParts,
      contains(ClockPart.detail), // seconds are colored by this row
    );
  });

  Future<void> openClockDock(WidgetTester tester, StandbySettings s) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StandbyProApp(initialSettings: s));
    await tester.pump();
    await tester.tap(find.byType(FittedBox).first);
    await tester.pumpAndSettle();
  }

  testWidgets('digital offers Hours/Colon/Minutes and Show seconds', (
    tester,
  ) async {
    await openClockDock(
      tester,
      const StandbySettings(layoutMode: StandbyLayoutMode.single),
    );
    for (final t in [
      'Hours',
      'Colon',
      'Minutes',
      'Show seconds',
      '24-hour time',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('flip names its tiles and offers Show seconds', (tester) async {
    await openClockDock(
      tester,
      const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        clockStyle: ClockStyle.flip,
      ),
    );
    for (final t in ['Hours tile', 'Minutes tile', 'Colon dots']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Show seconds'), findsOneWidget); // a third tile
  });

  testWidgets('analog colors hands and dial, hides 24-hour, shows seconds', (
    tester,
  ) async {
    await openClockDock(
      tester,
      const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        clockStyle: ClockStyle.analog,
      ),
    );
    for (final t in [
      'Hour hand',
      'Minute hand',
      'Dial marks',
      'Show seconds',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('24-hour time'), findsNothing); // no digits to format
  });

  testWidgets('frame offers a Tick color color and no Show seconds', (
    tester,
  ) async {
    await openClockDock(
      tester,
      const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        clockStyle: ClockStyle.frame,
      ),
    );
    for (final t in ['Hours', 'Colon', 'Minutes', 'Tick color']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // the ring always counts seconds, so there is nothing to switch on
    expect(find.text('Show seconds'), findsNothing);
  });

  testWidgets('tapping the hours / minutes digits jumps to that color', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          use24HourTime: true,
        ),
      ),
    );
    await tester.pump();
    final clock = find.byType(RichText).first;
    final box = tester.getRect(clock);

    // tap the left end (hours digits): dock opens with Hours highlighted
    await tester.tapAt(Offset(box.left + box.width * 0.12, box.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row-hours-active')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-minutes-active')), findsNothing);

    // tap the right end (minutes digits): highlight moves to Minutes
    final box2 = tester.getRect(find.byType(RichText).first);
    await tester.tapAt(Offset(box2.left + box2.width * 0.9, box2.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row-minutes-active')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-hours-active')), findsNothing);
  });

  test(
    'presets: Apple-style red & white is offered and every theme exists',
    () {
      final names = clockPresets.map((p) => p.name).toList();
      expect(names.first, 'White'); // default look first
      expect(names, containsAll(['Red & white', 'Night red', 'Blue & white']));
      for (final p in clockPresets) {
        expect(themeById(p.themeId).id, p.themeId, reason: p.name);
      }
    },
  );

  test('applying a preset sets the theme and all four part colors', () {
    final red = clockPresets.firstWhere((p) => p.name == 'Red & white');
    final applied = red.apply(
      const StandbySettings(activeThemeId: 'solar', colonColor: 0xFF123456),
    );
    expect(applied.activeThemeId, 'aurora');
    expect(applied.hoursColor, 0xFFFFFFFF); // white hours
    expect(applied.minutesColor, 0xFFFF453A); // red minutes
    expect(applied.colonColor, 0); // old custom colon cleared
    expect(red.matches(applied), isTrue);
    expect(red.matches(const StandbySettings()), isFalse);
  });

  testWidgets(
    'tapping the Red & white preset paints white hours, red minutes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const StandbyProApp(
          initialSettings: StandbySettings(
            layoutMode: StandbyLayoutMode.single,
            use24HourTime: true,
            activeThemeId: 'solar',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(FittedBox).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Red & white'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Red & white'));
      await tester.pumpAndSettle();

      final spans = <TextSpan>[];
      for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
        r.text.visitChildren((s) {
          if (s is TextSpan && s.text != null) spans.add(s);
          return true;
        });
      }
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      expect(
        spans.firstWhere((s) => s.text == two(now.hour)).style?.color,
        const Color(0xFFFFFFFF),
      );
      expect(
        spans.firstWhere((s) => s.text == two(now.minute)).style?.color,
        const Color(0xFFFF453A),
      );
    },
  );

  test('the app accent is its own setting, not tied to the clock', () {
    expect(const StandbySettings().appAccentInk, const Color(0xFFFF453A));
    expect(
      const StandbySettings(appAccent: 0xFF30D158).appAccentInk,
      const Color(0xFF30D158),
    );
    // changing the clock (colors, theme, presets) never moves the accent
    const base = StandbySettings(appAccent: 0xFF30D158);
    for (final preset in clockPresets) {
      expect(preset.apply(base).appAccent, base.appAccent, reason: preset.name);
      expect(preset.apply(base).appAccentInk, const Color(0xFF30D158));
    }
    expect(
      base
          .copyWith(minutesColor: 0xFF0A84FF, activeThemeId: 'solar')
          .appAccentInk,
      const Color(0xFF30D158),
    );
    // and it survives save + load
    expect(StandbySettings.fromJson(base.toJson()).appAccent, 0xFF30D158);
  });

  testWidgets('World clock names this phone city and colors the names', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ClockFace(
          time: DateTime(2026, 10, 6, 10, 9),
          settings: const StandbySettings(
            clockStyle: ClockStyle.world,
            worldZone: 'Asia/Tokyo',
            worldCity: 'Tokyo',
            localCity: 'Cupertino',
            labelColor: 0xFF30D158, // green
          ),
        ),
      ),
    );

    expect(find.text('Local'), findsNothing); // replaced by the real city
    final local = tester.widget<Text>(find.text('Cupertino'));
    final other = tester.widget<Text>(find.textContaining('Tokyo'));
    expect(local.style?.color, const Color(0xFF30D158));
    expect(other.style?.color, const Color(0xFF30D158));
  });

  testWidgets('without a location the World clock says Local', (tester) async {
    await tester.pumpWidget(
      host(
        ClockFace(
          time: DateTime(2026, 10, 6, 10, 9),
          settings: const StandbySettings(clockStyle: ClockStyle.world),
        ),
      ),
    );
    expect(find.text('Local'), findsOneWidget);
  });

  testWidgets('tapping a city name jumps to the City names color row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          clockStyle: ClockStyle.world,
          localCity: 'Cupertino',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Cupertino'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('row-label-active')), findsOneWidget);
    expect(find.text('City names'), findsOneWidget);
  });

  testWidgets('the Size slider resizes every clock style', (tester) async {
    for (final style in [
      ClockStyle.digital,
      ClockStyle.analog,
      ClockStyle.flip,
      ClockStyle.text,
      ClockStyle.world,
      ClockStyle.frame,
    ]) {
      Future<double> widthAt(double size) async {
        await tester.pumpWidget(
          host(
            ClockFace(
              time: DateTime(2026, 10, 6, 10, 9),
              settings: StandbySettings(clockStyle: style, fontScale: size),
            ),
          ),
        );
        return tester.getSize(find.byType(FittedBox).first).width;
      }

      final full = await widthAt(1.0);
      final half = await widthAt(0.5);
      expect(half, closeTo(full / 2, 1), reason: '$style');
    }
  });

  testWidgets('press and hold on the progress bar seeks to that point', (
    tester,
  ) async {
    int? sought;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 420,
              child: MusicCard(
                snapshot: const NowPlayingSnapshot(
                  title: 'Song',
                  artist: 'Artist',
                  source: 'Spotify',
                  progress: 0.1,
                  isPlaying: false,
                  isControllable: true,
                  durationMs: 200000,
                  positionMs: 20000,
                ),
                settings: const StandbySettings(),
                onCommand: (_) async => true,
                onSeek: (ms) async {
                  sought = ms;
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    );

    final semantics = find.bySemanticsLabel(RegExp('Song position'));
    final rect = tester.getRect(semantics);
    final start = Offset(rect.left + 10, rect.top + 14);
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700)); // hold
    expect(sought, isNull); // nothing happens until you let go
    await g.moveTo(Offset(rect.left + rect.width * 0.75, start.dy));
    await tester.pump();
    await g.up();
    await tester.pump();

    // released ~75% along the bar of a 200 s song
    expect(sought, closeTo(150000, 6000));
  });

  testWidgets('a quick tap on the bar does not seek', (tester) async {
    int? sought;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 420,
            child: MusicCard(
              snapshot: const NowPlayingSnapshot(
                title: 'Song',
                artist: 'A',
                source: 'Spotify',
                progress: 0.1,
                isPlaying: false,
                isControllable: true,
                durationMs: 200000,
                positionMs: 20000,
              ),
              settings: const StandbySettings(),
              onCommand: (_) async => true,
              onSeek: (ms) async {
                sought = ms;
                return true;
              },
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.bySemanticsLabel(RegExp('Song position')));
    await tester.tapAt(Offset(rect.left + rect.width * 0.8, rect.top + 14));
    await tester.pump(const Duration(seconds: 1));
    expect(sought, isNull);
  });

  test('city-name color and local city survive save and load', () {
    const original = StandbySettings(
      labelColor: 0xFF0A84FF,
      localCity: 'Cupertino',
      fontScale: 0.6,
    );
    final restored = StandbySettings.fromJson(original.toJson());
    expect(restored, original);
    expect(restored.labelColor, 0xFF0A84FF);
    expect(restored.localCity, 'Cupertino');
    expect(restored.fontScale, 0.6);
    expect(const StandbySettings().labelColor, 0); // default: auto
  });

  testWidgets('the clock keeps one size while the seconds tick', (
    tester,
  ) async {
    Future<Size> sizeAt(int second) async {
      await tester.pumpWidget(
        host(
          ClockFace(
            time: DateTime(2026, 10, 6, 10, 9, second),
            settings: const StandbySettings(
              showSeconds: true,
              use24HourTime: true,
            ),
          ),
        ),
      );
      // the box around the digits: it must not depend on which digits show
      return tester.getSize(
        find
            .ancestor(
              of: find.byType(RichText).first,
              matching: find.byType(SizedBox),
            )
            .first,
      );
    }

    final narrow = await sizeAt(11); // '1' is a narrow digit in most fonts
    final wide = await sizeAt(48);
    expect(wide, narrow);
  });

  testWidgets('switching to a seconds style updates the time right away', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // a no-seconds style plans its next tick up to a minute away
    final c = StandbyController(
      initialSettings: const StandbySettings(clockStyle: ClockStyle.text),
    )..initializeForTest();
    c.now = DateTime(2000); // stale on purpose

    // not awaited: saving to disk is real I/O; the time refresh and the
    // re-planned tick both happen before it, which is what we check
    unawaited(
      c.updateSettings(
        const StandbySettings(showSeconds: true), // digital + seconds
      ),
    );

    expect(c.now.year, DateTime.now().year); // refreshed immediately
    final afterUpdate = c.now;
    if (DateTime.now().second < 55) {
      // ...and the tick was re-planned for the next second, not the next minute
      await tester.pump(const Duration(milliseconds: 1100));
      expect(c.now.isAfter(afterUpdate), isTrue);
    }
    c.dispose();
  });

  testWidgets('style and preset tiles preview the real clock, name on top', (
    tester,
  ) async {
    await openClockDock(
      tester,
      const StandbySettings(layoutMode: StandbyLayoutMode.single),
    );

    // dashboard clock + one preview per style + one per preset
    expect(
      find.byType(ClockFace),
      findsNWidgets(1 + ClockStyle.values.length + clockPresets.length),
    );
    final tile = find
        .ancestor(of: find.text('Red & white'), matching: find.byType(Column))
        .first;
    final preview = find.descendant(of: tile, matching: find.byType(ClockFace));
    expect(
      tester.getCenter(preview).dy,
      greaterThan(tester.getCenter(find.text('Red & white')).dy),
    );
  });

  testWidgets('preset previews follow the chosen clock style', (tester) async {
    await openClockDock(
      tester,
      const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        clockStyle: ClockStyle.flip,
      ),
    );
    final tile = find
        .ancestor(of: find.text('Red & white'), matching: find.byType(Column))
        .first;
    // a Flip preview draws the flip tiles, not plain digits
    expect(
      find.descendant(of: tile, matching: find.byType(FlipClockFace)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tile, matching: find.byType(DigitalClockFace)),
      findsNothing,
    );
  });

  testWidgets('holding the progress bar for ~300 ms is enough to seek', (
    tester,
  ) async {
    int? sought;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 420,
              child: MusicCard(
                snapshot: const NowPlayingSnapshot(
                  title: 'Song',
                  artist: 'A',
                  source: 'Spotify',
                  progress: 0.1,
                  isPlaying: false,
                  isControllable: true,
                  durationMs: 200000,
                  positionMs: 20000,
                ),
                settings: const StandbySettings(),
                onCommand: (_) async => true,
                onSeek: (ms) async {
                  sought = ms;
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.bySemanticsLabel(RegExp('Song position')));
    final g = await tester.startGesture(Offset(rect.left + 10, rect.top + 14));
    await tester.pump(const Duration(milliseconds: 300)); // < Flutter's 500
    await g.moveTo(Offset(rect.left + rect.width * 0.5, rect.top + 14));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(sought, closeTo(100000, 6000));
  });

  testWidgets('the screen does not shift while the seconds tick', (
    tester,
  ) async {
    final c = StandbyController(
      initialSettings: const StandbySettings(showSeconds: true),
    )..initializeForTest();
    final before = c.burnInTick;

    // three one-second ticks (skip if a minute rolls over mid-test)
    final start = DateTime.now();
    await tester.pump(const Duration(milliseconds: 3200));

    if (start.second < 55) {
      expect(
        c.burnInTick,
        before,
        reason: 'seconds ticked, but the burn-in shift must not move',
      );
    }
    c.dispose();
  });

  test('the frame line counts seconds even when "show seconds" is off', () {
    const frame = StandbySettings(clockStyle: ClockStyle.frame);
    expect(frame.showSeconds, isFalse);
    expect(frame.secondsVisible, isTrue); // so the clock ticks every second
    expect(ClockStyle.frame.supportsSeconds, isFalse); // no digits for seconds
    final now = DateTime(2026, 10, 6, 12, 0, 10, 500);
    expect(
      ClockCadence.nextDelay(now, frame),
      const Duration(milliseconds: 500),
    );
  });

  testWidgets('the frame draws the time in the middle of a tick border', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ClockFace(
          time: DateTime(2026, 10, 6, 10, 9, 30),
          settings: const StandbySettings(
            clockStyle: ClockStyle.frame,
            use24HourTime: true,
          ),
        ),
      ),
    );
    expect(find.byType(FrameClockFace), findsOneWidget);
    final frame = tester.getRect(find.byType(FrameClockFace));
    final digits = tester.getRect(find.byType(RichText).first);
    // the digits sit in the centre of the square
    expect(digits.center.dx, closeTo(frame.center.dx, 2));
    expect(digits.center.dy, closeTo(frame.center.dy, 24));
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter != null &&
            w.painter.runtimeType.toString() == '_FramePainter',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Clock settings and All settings are split into sections', (
    tester,
  ) async {
    await openClockDock(
      tester,
      const StandbySettings(layoutMode: StandbyLayoutMode.single),
    );
    for (final t in ['Style', 'Presets', 'Clock colors', 'Options']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // a divider line between the sections
    expect(find.byType(Divider), findsAtLeastNWidgets(4));
  });

  testWidgets(
    'only the frame border selects the seconds ticks, not its middle',
    (tester) async {
      final taps = <ClockPart>[];
      await tester.pumpWidget(
        host(
          ClockFace(
            time: DateTime(2026, 10, 6, 10, 9, 30),
            settings: const StandbySettings(
              clockStyle: ClockStyle.frame,
              use24HourTime: true,
            ),
            onPartTap: taps.add,
          ),
        ),
      );
      final frame = tester.getRect(find.byType(FrameClockFace));

      // empty interior (above the digits): nothing selected
      await tester.tapAt(
        Offset(frame.center.dx, frame.top + frame.height * 0.28),
      );
      expect(taps, isEmpty);

      // on the border strip: the line is selected
      await tester.tapAt(
        Offset(frame.left + frame.width * 0.02, frame.center.dy),
      );
      expect(taps, [ClockPart.label]);
    },
  );

  test('frame ticks fade like a tail behind the current second', () {
    const second = 30;
    expect(frameTickBrightness(30, second), 1.0); // now: brightest
    // each older tick is dimmer than the one after it
    for (var age = 1; age < 59; age++) {
      expect(
        frameTickBrightness(30 - age, second),
        greaterThan(frameTickBrightness(30 - age - 1, second)),
        reason: 'age $age',
      );
    }
    // the tick about to light up is the darkest, but never fully off
    final next = frameTickBrightness(31, second);
    expect(next, closeTo(0.1, 0.001));
    expect(next, greaterThan(0));
    // wraps around the minute
    expect(frameTickBrightness(59, 0), greaterThan(frameTickBrightness(1, 0)));
  });

  testWidgets('the frame time has no leading zero, like Apple (8:13)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ClockFace(
          time: DateTime(2026, 10, 6, 8, 13, 5),
          settings: const StandbySettings(
            clockStyle: ClockStyle.frame,
            use24HourTime: true,
          ),
        ),
      ),
    );
    final spans = <String>[];
    tester.widget<RichText>(find.byType(RichText).first).text.visitChildren((
      s,
    ) {
      if (s is TextSpan && s.text != null) spans.add(s.text!);
      return true;
    });
    expect(spans, containsAllInOrder(['8', ':', '13']));
    expect(spans, isNot(contains('08')));
  });

  test('frame ticks are smaller than before and follow the size setting', () {
    final base = frameTickSize(1);
    expect(base.length, lessThan(24)); // was 24
    expect(base.width, lessThan(5.2)); // was 5.2
    expect(frameTickSize(0.5).length, closeTo(base.length / 2, 0.01));
    expect(frameTickSize(1.6).length, greaterThan(base.length));
    // out-of-range values are clamped, never absurd
    expect(frameTickSize(99).length, frameTickSize(1.6).length);
    expect(frameTickSize(0).length, frameTickSize(0.5).length);
    expect(const StandbySettings().tickScale, 1);
    final restored = StandbySettings.fromJson(
      const StandbySettings(tickScale: 0.7).toJson(),
    );
    expect(restored.tickScale, 0.7);
  });

  testWidgets('frame offers Tick color first and a Tick size slider', (
    tester,
  ) async {
    await openClockDock(
      tester,
      const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        clockStyle: ClockStyle.frame,
      ),
    );
    expect(find.text('Tick size'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Tick color')).dy,
      lessThan(tester.getTopLeft(find.text('Hours')).dy),
    );
  });

  testWidgets('other styles have no Tick size slider', (tester) async {
    await openClockDock(
      tester,
      const StandbySettings(layoutMode: StandbyLayoutMode.single),
    );
    expect(find.text('Tick size'), findsNothing);
    expect(find.text('Tick color'), findsNothing);
  });

  testWidgets('the date card and today circle use the app accent', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        CalendarCard(
          settings: const StandbySettings(
            calendarStyle: CalendarStyle.month,
            appAccent: 0xFF30D158,
            minutesColor: 0xFFFF453A, // clock color: must not leak in
          ),
          now: DateTime(2026, 10, 6),
        ),
      ),
    );
    final circles = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).shape == BoxShape.circle,
        );
    expect(circles, hasLength(1));
    expect(
      (circles.single.decoration as BoxDecoration).color,
      const Color(0xFF30D158),
    );
  });

  testWidgets('the music card fallback uses the app accent', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 420,
            child: MusicCard(
              snapshot: const NowPlayingSnapshot(
                title: 'Nothing playing',
                artist: '',
                source: 'Idle',
                progress: 0,
                isPlaying: false,
                isControllable: false,
              ),
              settings: const StandbySettings(
                appAccent: 0xFF30D158,
                activeThemeId: 'solar', // clock theme: must not leak in
              ),
              onCommand: (_) async => true,
            ),
          ),
        ),
      ),
    );
    final gradients = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>();
    expect(
      gradients.any((g) => g.colors.first == const Color(0xFF30D158)),
      isTrue,
    );
  });

  testWidgets('All settings has a Theme section that sets the accent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.calendar,
          calendarStyle: CalendarStyle.month,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(CalendarCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All settings'));
    await tester.pumpAndSettle();

    expect(find.text('Theme'), findsOneWidget);
    await tester.ensureVisible(find.bySemanticsLabel('Accent Blue'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Accent Blue'));
    await tester.pumpAndSettle();

    // the date card behind the panel picked it up
    final today = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).shape == BoxShape.circle &&
              (c.decoration as BoxDecoration).color == const Color(0xFF0A84FF),
        )
        .isNotEmpty;
    expect(today, isTrue);
  });

  test('pinch: spread = one panel, pinch together = two panels', () {
    expect(PinchLayout.layoutFor(100, 260), StandbyLayoutMode.single); // spread
    expect(PinchLayout.layoutFor(300, 100), StandbyLayoutMode.duo); // pinch
    // hardly moving, or fingers too close to measure: nothing happens
    expect(PinchLayout.layoutFor(200, 220), isNull);
    expect(PinchLayout.layoutFor(200, 170), isNull);
    expect(PinchLayout.layoutFor(10, 400), isNull);
  });

  testWidgets('pinching with two fingers switches the layout, no white box', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const StandbyProApp(initialSettings: StandbySettings()), // two panels
    );
    await tester.pump();
    final c = tester.view.physicalSize / tester.view.devicePixelRatio;
    final y = c.height / 2;
    expect(find.textContaining('Loading weather'), findsOneWidget);

    // spread two fingers: zoom into ONE panel
    final a = await tester.startGesture(Offset(c.width * 0.45, y), pointer: 1);
    final b = await tester.startGesture(Offset(c.width * 0.55, y), pointer: 2);
    await a.moveTo(Offset(c.width * 0.2, y));
    await b.moveTo(Offset(c.width * 0.8, y));
    await a.up();
    await b.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Loading weather'), findsNothing); // one panel
    expect(find.text('One panel'), findsOneWidget); // dark pop-up
    expect(find.byType(SnackBar), findsNothing); // not a light snackbar

    // pinch together: back to TWO panels; the pinch must not swipe a card
    await tester.pump(const Duration(seconds: 2));
    final d = await tester.startGesture(Offset(c.width * 0.15, y), pointer: 3);
    final e = await tester.startGesture(Offset(c.width * 0.85, y), pointer: 4);
    await d.moveTo(Offset(c.width * 0.45, y));
    await e.moveTo(Offset(c.width * 0.55, y));
    await d.up();
    await e.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Loading weather'), findsOneWidget);
    expect(find.text('Two panels'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // let the pop-up timer end
  });

  testWidgets('spreading on the right card keeps that card, not the left', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(),
      ), // clock | weather
    );
    await tester.pump();
    final c = tester.view.physicalSize / tester.view.devicePixelRatio;
    final y = c.height / 2;
    expect(find.textContaining('Loading weather'), findsOneWidget);

    final a = await tester.startGesture(Offset(c.width * 0.70, y), pointer: 1);
    final b = await tester.startGesture(Offset(c.width * 0.80, y), pointer: 2);
    await a.moveTo(Offset(c.width * 0.60, y));
    await b.moveTo(Offset(c.width * 0.95, y));
    await a.up();
    await b.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('Loading weather'),
      findsOneWidget,
    ); // weather stays
    expect(find.text('One panel'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    // pinch back out: the clock is on the left again, weather on the right
    final d = await tester.startGesture(Offset(c.width * 0.15, y), pointer: 3);
    final e = await tester.startGesture(Offset(c.width * 0.85, y), pointer: 4);
    await d.moveTo(Offset(c.width * 0.45, y));
    await e.moveTo(Offset(c.width * 0.55, y));
    await d.up();
    await e.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final weather = tester.getCenter(find.textContaining('Loading weather'));
    expect(weather.dx, greaterThan(c.width / 2)); // back on the right
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a one-finger sideways swipe still changes the card', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const StandbyProApp(initialSettings: StandbySettings()),
    );
    await tester.pump();
    await tester.fling(
      find.textContaining('Loading weather'),
      const Offset(-300, 0),
      1500,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Loading weather'),
      findsNothing,
    ); // card changed
    expect(find.text('One panel'), findsNothing);
    expect(find.text('Two panels'), findsNothing);
  });

  testWidgets('the flip clock shows a seconds tile when seconds are on', (
    tester,
  ) async {
    Future<int> tiles(bool seconds) async {
      await tester.pumpWidget(
        host(
          ClockFace(
            time: DateTime(2026, 10, 6, 10, 9, 41),
            settings: StandbySettings(
              clockStyle: ClockStyle.flip,
              use24HourTime: true,
              showSeconds: seconds,
            ),
          ),
        ),
      );
      return find.text('4').evaluate().length; // the tens digit of the seconds
    }

    expect(await tiles(false), 0); // hours + minutes only
    expect(await tiles(true), 1); // seconds tiles ('4' and '1') appear
  });

  testWidgets('a flip tile flips to the new digits instead of jumping', (
    tester,
  ) async {
    Widget clock(int minute) => host(
      ClockFace(
        time: DateTime(2026, 10, 6, 10, minute),
        settings: const StandbySettings(
          clockStyle: ClockStyle.flip,
          use24HourTime: true,
        ),
      ),
    );

    await tester.pumpWidget(clock(15)); // 10:15
    expect(find.text('5'), findsOneWidget);

    await tester.pumpWidget(clock(16)); // only the ones digit changes
    await tester.pump(const Duration(milliseconds: 120)); // mid-flip
    expect(find.text('5'), findsWidgets); // old digit folding away
    expect(find.text('6'), findsWidgets); // new digit coming in
    // the tens digit of the minutes did not flip: still one '1' there + one in the hour
    expect(find.text('1'), findsNWidgets(2));

    await tester.pumpAndSettle(); // flip finished
    expect(find.text('5'), findsNothing);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('world clock names the day and date instead of "Tomorrow"', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ClockFace(
          time: DateTime.utc(2026, 10, 6, 20), // already Oct 7 in Tokyo
          settings: const StandbySettings(
            clockStyle: ClockStyle.world,
            worldZone: 'Asia/Tokyo',
            worldCity: 'Tokyo',
          ),
        ),
      ),
    );
    expect(find.text('Tokyo · Wed, Oct 7'), findsOneWidget);
    expect(find.textContaining('Tomorrow'), findsNothing);
  });

  testWidgets(
    'the music card shows a volume bar on demand and hides it again',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 420,
              child: MusicCard(
                snapshot: const NowPlayingSnapshot(
                  title: 'Song',
                  artist: 'Artist',
                  source: 'Spotify',
                  progress: 0.1,
                  isPlaying: false,
                  isControllable: true,
                  durationMs: 200000,
                  positionMs: 20000,
                ),
                settings: const StandbySettings(),
                onCommand: (_) async => true,
                volumeBar: (keepOpen) => const Text('VOLUME BAR'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('VOLUME BAR'), findsNothing); // closed by default

      await tester.tap(find.byTooltip('Volume'));
      await tester.pump();
      expect(find.text('VOLUME BAR'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5)); // idle: closes itself
      expect(find.text('VOLUME BAR'), findsNothing);
    },
  );
  group('battery badge and low battery prompt', () {
    final live = <BatteryMonitor>[];
    BatteryMonitor monitor(BatteryReading? r) {
      final m = BatteryMonitor(
        read: () async => r,
        every: const Duration(hours: 1),
      );
      live.add(m);
      return m;
    }

    // unmount, then stop the monitors' timers (a test must not leave any)
    Future<void> finish(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      for (final m in live) {
        m.dispose();
      }
      live.clear();
    }

    Future<void> showBadge(WidgetTester tester, BatteryReading? r) async {
      final m = monitor(r);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BatteryBadge(monitor: m)),
        ),
      );
      await tester.pump();
    }

    testWidgets('badge: percentage on battery, red when low', (t) async {
      await showBadge(t, (level: 73, charging: false, full: false));
      expect(find.text('73%'), findsOneWidget);
      expect(t.widget<Text>(find.text('73%')).style!.color, Colors.white54);
      await showBadge(t, (level: 15, charging: false, full: false));
      expect(
        t.widget<Text>(find.text('15%')).style!.color,
        const Color(0xFFFF453A),
      );
      await finish(t);
    });

    testWidgets('badge: green while charging but not yet full', (t) async {
      await showBadge(t, (level: 80, charging: true, full: false));
      expect(find.text('80%'), findsOneWidget);
      expect(
        t.widget<Text>(find.text('80%')).style!.color,
        const Color(0xFF30D158),
      );
      await finish(t);
    });

    testWidgets('badge: hidden when full on the charger or unknown', (t) async {
      await showBadge(t, (level: 100, charging: true, full: true));
      expect(find.textContaining('%'), findsNothing);
      await showBadge(t, (level: 100, charging: true, full: false));
      expect(find.textContaining('%'), findsNothing);
      await showBadge(t, null);
      expect(find.textContaining('%'), findsNothing);
      await showBadge(t, (level: 100, charging: false, full: false));
      expect(
        find.text('100%'),
        findsOneWidget,
      ); // unplugged at 100%: still shown
      await finish(t);
    });

    Future<void> app(
      WidgetTester tester,
      BatteryReading? r, {
      bool alert = true,
      int at = 20,
    }) async {
      final m = monitor(r);
      await tester.pumpWidget(
        StandbyProApp(
          initialSettings: StandbySettings(
            lowBatteryAlert: alert,
            lowBatteryLevel: at,
          ),
          battery: m,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('prompt: at 20% and not charging, asks to charge', (t) async {
      await app(t, (level: 20, charging: false, full: false));
      expect(find.text('Charge your phone'), findsOneWidget);
      expect(find.text('Plug it in to keep using Dockwise.'), findsOneWidget);
      await finish(t);
    });

    testWidgets('prompt follows the level you choose', (t) async {
      await app(t, (level: 35, charging: false, full: false), at: 40);
      expect(find.text('Charge your phone'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await app(t, (level: 35, charging: false, full: false), at: 30);
      expect(find.text('Charge your phone'), findsNothing);
      await finish(t);
    });

    testWidgets('prompt: not shown above 20%, while charging, or when off', (
      t,
    ) async {
      await app(t, (level: 21, charging: false, full: false));
      expect(find.text('Charge your phone'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await app(t, (level: 8, charging: true, full: false)); // plugged in
      expect(find.text('Charge your phone'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await app(t, (level: 8, charging: false, full: false), alert: false);
      expect(find.text('Charge your phone'), findsNothing);
      await finish(t);
    });
  });
}
