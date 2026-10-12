// Records the animations shown in the README as numbered PNG frames, using
// sample data only. Run it, then turn the frames into GIFs:
//
//   cd app
//   flutter test tool/readme_gifs_test.dart
//   python3 tool/frames_to_gif.py
//
// Frames go to build/readme_frames/<scene>/, the GIFs to ../docs/.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/core/apple.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/domain/summary_layout.dart';
import 'package:standby_pro/src/features/standby/widgets/battery_badge.dart';
import 'package:standby_pro/src/features/standby/widgets/clock_faces.dart';
import 'package:standby_pro/src/features/standby/widgets/integration_cards.dart';
import 'package:standby_pro/src/features/standby/widgets/summary_card.dart';
import 'package:standby_pro/src/features/standby/widgets/timer_card.dart';
import 'package:standby_pro/src/features/standby/widgets/timer_entry.dart';
import 'package:standby_pro/src/features/standby/widgets/timer_tile.dart';
import 'package:standby_pro/src/services/weather_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

import 'harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadFonts);

  // 1. The page indicator: tap to show, press and slide, lift to go there.
  testWidgets('page dots', (tester) async {
    const size = Size(440, 250);
    surface(tester, size);
    final key = GlobalKey();
    const names = ['Clock', 'Weather', 'Calendar', 'Music', 'Summary'];
    const colors = [
      Color(0xFF2C2C2E),
      Color(0xFF1E4E8C),
      Color(0xFF3A2D52),
      Color(0xFF5B2A3C),
      Color(0xFF214C3A),
    ];
    var page = 0;
    late StateSetter set;
    await tester.pumpWidget(
      stage(
        key,
        size,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Column(
              children: [
                const SizedBox(height: 10),
                SizedBox(
                  height: 22,
                  child: PageDots(
                    labels: names,
                    icons: const [
                      Icons.schedule_rounded,
                      Icons.wb_sunny_rounded,
                      Icons.calendar_today_rounded,
                      Icons.music_note_rounded,
                      Icons.dashboard_rounded,
                    ],
                    index: page,
                    bright: false,
                    onSelect: (i) => set(() => page = i),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 44, 16, 16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        color: colors[page],
                        borderRadius: BorderRadius.circular(28),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        names[page],
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    final rec = Rec(tester, key, 'page-dots');
    final left = tester.getCenter(find.byType(PageDots)).dx - 75;
    Offset dot(int i) => Offset(left + 30.0 * i + 15, 21);
    await rec.play(500);
    await tester.tapAt(dot(0)); // brings the dots back
    await rec.play(700);
    final g = await tester.startGesture(dot(1));
    await rec.play(500);
    for (final i in [2, 3, 4]) {
      await g.moveTo(dot(i));
      await rec.play(450);
    }
    await g.up();
    await rec.play(1100);
    await tester.pump(const Duration(seconds: 4));
  });

  // 2. Summary: cards deal in, hold to edit, drag to swap, Done.
  testWidgets('summary', (tester) async {
    const size = Size(660, 330);
    surface(tester, size);
    final key = GlobalKey();
    final art = await makeArt(tester);
    var layout = SummaryLayout.standard.encode();
    final weather = parseForecast(sampleForecast(), city: 'Austin');
    late StateSetter set;
    await tester.pumpWidget(
      stage(
        key,
        size,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            final s = StandbySettings(
              worldZone: 'Asia/Tokyo',
              worldCity: 'Tokyo',
              worldLat: 35.7,
              worldLon: 139.7,
              localCity: 'Austin',
              use24HourTime: false,
              summaryLayout: layout,
            );
            return SummaryCard(
              now: DateTime(2026, 10, 11, 14, 30),
              settings: s,
              weather: WeatherCard(
                snapshot: weather,
                settings: s,
                onCityTap: () {},
              ),
              music: MusicCard(
                snapshot: sampleSong(art),
                settings: s,
                onCommand: (_) async => true,
              ),
              onLayout: (v) => set(() => layout = v),
            );
          },
        ),
      ),
    );
    await tester.runAsync(
      () async => precacheImage(
        MemoryImage(art),
        tester.element(find.byType(SummaryCard)),
      ),
    );
    final rec = Rec(tester, key, 'summary');
    await rec.play(1300); // the cards deal in
    await rec.play(500);
    final date = tester.getCenter(find.text('SUNDAY'));
    final hold = await tester.startGesture(date); // hold: they start to jiggle
    await rec.play(900);
    await hold.up();
    await rec.play(600);
    final from = tester.getCenter(find.text('SUNDAY'));
    final to = tester.getCenter(find.text('Austin').first);
    final drag = await tester.startGesture(from);
    await rec.play(250);
    for (var i = 1; i <= 8; i++) {
      await drag.moveTo(Offset.lerp(from, to, i / 8)!);
      await rec.play(70);
    }
    await rec.play(200);
    await drag.up();
    await rec.play(1000); // they glide to their new places
    await tester.tap(find.text('Done'));
    await rec.play(700);
  });

  // 3. The clock rearranges when the panel turns: hours up, minutes down.
  testWidgets('clock rotate', (tester) async {
    const size = Size(560, 520);
    surface(tester, size);
    final key = GlobalKey();
    var landscape = true;
    var style = ClockStyle.digital;
    late StateSetter set;
    await tester.pumpWidget(
      stage(
        key,
        size,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Center(
              child: SizedBox(
                width: landscape ? 540 : 260,
                height: landscape ? 240 : 500,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: ClockFace(
                    time: DateTime(2026, 10, 11, 10, 9, 30),
                    settings: StandbySettings(
                      clockStyle: style,
                      use24HourTime: true,
                      layoutMode: StandbyLayoutMode.single,
                      worldZone: 'Asia/Tokyo',
                      worldCity: 'Tokyo',
                      localCity: 'Austin',
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final rec = Rec(tester, key, 'clock-rotate', scale: 1.2);
    for (final s in [ClockStyle.digital, ClockStyle.flip, ClockStyle.world]) {
      set(() {
        style = s;
        landscape = true;
      });
      await rec.play(500);
      set(() => landscape = false);
      await rec.play(1100);
      set(() => landscape = true);
      await rec.play(1000);
    }
  });

  // 4. The weather card: now, Fahrenheit, forecast, a second city.
  testWidgets('weather pages', (tester) async {
    const size = Size(400, 330);
    surface(tester, size);
    final key = GlobalKey();
    var page = 0;
    late StateSetter set;
    final here = parseForecast(sampleForecast(), city: 'Austin');
    final there = parseForecast(sampleForecast(base: 12), city: 'Tokyo');
    await tester.pumpWidget(
      stage(
        key,
        size,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Padding(
              padding: const EdgeInsets.all(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: WeatherCard(
                  snapshot: here,
                  secondSnapshot: there,
                  settings: const StandbySettings(
                    use24HourTime: false,
                    worldZone: 'Asia/Tokyo',
                    worldCity: 'Tokyo',
                    worldLat: 35.7,
                    worldLon: 139.7,
                  ),
                  page: page,
                  onCityTap: () {},
                ),
              ),
            );
          },
        ),
      ),
    );
    final rec = Rec(tester, key, 'weather-pages');
    await rec.play(900);
    for (final p in [1, 2, 3, 0]) {
      set(() => page = p);
      await rec.play(1700);
    }
  });

  // 5. The music card's buttons: press feedback, play/pause morph, hold label.
  testWidgets('music buttons', (tester) async {
    const size = Size(380, 470);
    surface(tester, size);
    final key = GlobalKey();
    final art = await makeArt(tester);
    var playing = true;
    late StateSetter set;
    await tester.pumpWidget(
      stage(
        key,
        size,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Padding(
              padding: const EdgeInsets.all(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: MusicCard(
                  snapshot: sampleSong(art, playing: playing),
                  settings: const StandbySettings(),
                  onCommand: (c) async {
                    if (c == 'playPause') set(() => playing = !playing);
                    return true;
                  },
                  nextUp: () async => 'Next: Save Your Tears · The Weeknd',
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.runAsync(
      () async => precacheImage(
        MemoryImage(art),
        tester.element(find.byType(MusicCard)),
      ),
    );
    final rec = Rec(tester, key, 'music-buttons');
    await rec.play(700);
    // tap play/pause: it morphs
    var g = await tester.startGesture(
      tester.getCenter(find.byTooltip('Pause')),
    );
    await rec.play(120);
    await g.up();
    await rec.play(900);
    g = await tester.startGesture(tester.getCenter(find.byTooltip('Play')));
    await rec.play(120);
    await g.up();
    await rec.play(800);
    // tap next: it hops
    g = await tester.startGesture(tester.getCenter(find.byTooltip('Next')));
    await rec.play(100);
    await g.up();
    await rec.play(700);
    // hold next: a glass label names the song that is coming
    g = await tester.startGesture(tester.getCenter(find.byTooltip('Next')));
    await rec.play(1500);
    await g.up();
    await rec.play(1400);
  });

  // 6. The flip clock: each digit flips on its own card, only when it changes.
  testWidgets('flip clock', (tester) async {
    const size = Size(520, 290);
    surface(tester, size);
    final key = GlobalKey();
    var time = DateTime(2026, 10, 11, 10, 59, 57);
    late StateSetter set;
    await tester.pumpWidget(
      stage(
        key,
        size,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Center(
              child: SizedBox(
                width: 500,
                height: 260,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: ClockFace(
                    time: time,
                    settings: const StandbySettings(
                      clockStyle: ClockStyle.flip,
                      use24HourTime: true,
                      showSeconds: true,
                      layoutMode: StandbyLayoutMode.single,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final rec = Rec(tester, key, 'flip-clock');
    await rec.play(600);
    for (var i = 0; i < 5; i++) {
      set(() => time = time.add(const Duration(seconds: 1)));
      await rec.play(1000);
    }
  });

  // 7. The weather scenes: sun, clouds, fog, night, rain, snow, storm.
  testWidgets('weather scenes', (tester) async {
    const size = Size(340, 290);
    surface(tester, size);
    final key = GlobalKey();
    const scenes = [
      (code: 0, day: true, temp: 24, text: 'Clear'),
      (code: 2, day: true, temp: 19, text: 'Partly cloudy'),
      (code: 45, day: true, temp: 11, text: 'Fog'),
      (code: 0, day: false, temp: 14, text: 'Clear'),
      (code: 61, day: true, temp: 12, text: 'Rain'),
      (code: 71, day: true, temp: -2, text: 'Snow'),
      (code: 95, day: true, temp: 17, text: 'Thunderstorm'),
    ];
    var i = 0;
    late StateSetter set;
    await tester.pumpWidget(
      stage(
        key,
        size,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            final sc = scenes[i];
            return Padding(
              padding: const EdgeInsets.all(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: WeatherNowView(
                    key: ValueKey(i),
                    snapshot: WeatherSnapshot(
                      city: 'Austin',
                      condition: sc.text,
                      temperatureCelsius: sc.temp,
                      highCelsius: sc.temp + 3,
                      lowCelsius: sc.temp - 5,
                      updatedAt: DateTime(2026, 10, 11),
                      code: sc.code,
                      isDay: sc.day,
                    ),
                    settings: const StandbySettings(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final rec = Rec(tester, key, 'weather-scenes', scale: 1.2);
    for (var k = 0; k < scenes.length; k++) {
      set(() => i = k);
      await rec.play(1100);
    }
  });

  // 8. The low-battery prompt: it appears at the level you chose and goes
  // away by itself when the charger is plugged in.
  testWidgets('low battery prompt', (tester) async {
    const size = Size(500, 280);
    surface(tester, size);
    final key = GlobalKey();
    var level = 26;
    var charging = false;
    final monitor = BatteryMonitor(
      read: () async => (level: level, charging: charging, full: false),
      every: const Duration(days: 1),
    );
    await tester.pumpWidget(
      stage(
        key,
        size,
        Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: ClockFace(
                  time: DateTime(2026, 10, 11, 23, 42),
                  settings: const StandbySettings(
                    use24HourTime: true,
                    layoutMode: StandbyLayoutMode.single,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 20,
              top: 16,
              child: BatteryBadge(monitor: monitor),
            ),
            LowBatteryAlert(monitor: monitor, enabled: true),
          ],
        ),
      ),
    );
    Future<void> set(int l, {bool plugged = false}) async {
      level = l;
      charging = plugged;
      await tester.runAsync(monitor.refresh);
    }

    final rec = Rec(tester, key, 'low-battery');
    await tester.runAsync(monitor.refresh);
    await rec.play(900);
    for (final l in [24, 22, 20]) {
      await set(l);
      await rec.play(700);
    }
    await rec.play(1500); // the prompt is up
    await set(20, plugged: true);
    await rec.play(1600); // plugged in: it fades out
    monitor.dispose(); // its timer must not outlive the test
  });

  // 8-9. The timer: a horse runs along the track (digital), a player runs for
  // the end zone (flip) and the touchdown sets off confetti and fireworks.
  Future<void> timerScene(
    WidgetTester tester,
    String name,
    TimerStyle style,
    Size size, {
    required int totalMs,
    required int fromMs,
    required int seconds,
  }) async {
    surface(tester, size);
    final key = GlobalKey();
    var left = fromMs;
    var started = true;
    late StateSetter set;
    await tester.pumpWidget(
      stage(
        key,
        size,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return TimerCard(
              settings: StandbySettings(timerStyle: style),
              leftMs: left,
              totalMs: totalMs,
              running: started && left > 0,
              started: started,
              done: started && left <= 0,
              onStart: () {},
              onPause: () {},
              onReset: () => set(() => started = false),
              onAdd: (_) {},
              onPreset: (_) {},
              onType: () {},
              roomy: true,
              horizontal: false,
            );
          },
        ),
      ),
    );
    final rec = Rec(tester, key, name);
    await rec.play(500);
    for (var i = 0; i < seconds; i++) {
      set(() => left = (left - 1000).clamp(0, totalMs));
      await rec.play(1000);
    }
    return;
  }

  testWidgets('timer horse', (tester) async {
    await timerScene(
      tester,
      'timer-horse',
      TimerStyle.digital,
      const Size(560, 280),
      totalMs: 20000,
      fromMs: 17000,
      seconds: 6,
    );
  });

  testWidgets('timer touchdown', (tester) async {
    await timerScene(
      tester,
      'timer-touchdown',
      TimerStyle.flip,
      const Size(560, 280),
      totalMs: 8000,
      fromMs: 4000,
      seconds: 8,
    );
    await tester.pump(const Duration(seconds: 6));
  });

  // 10. Typing a length on our number pad: it opens on the timer's time, digits
  // rise into place, the first key starts a new number.
  testWidgets('timer type', (tester) async {
    const size = Size(440, 420);
    surface(tester, size);
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final key = GlobalKey();
    final c = StandbyController(
      autostartTicker: false,
      initialSettings: const StandbySettings(),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      stage(key, size, TimerEntry(controller: c, onDone: () {})),
    );
    final rec = Rec(tester, key, 'timer-type');
    await rec.play(900);
    for (final k in ['1', '5', '0', '0']) {
      await tester.tap(find.text(k));
      await rec.play(600);
    }
    await rec.play(900);
  });

  // 11. Summary widgets: hold, take one away with the "-", a "+" appears, add
  // the timer, swipe it to the flip style, drag a card onto the empty place.
  testWidgets('summary widgets', (tester) async {
    const size = Size(660, 330);
    surface(tester, size);
    final key = GlobalKey();
    final art = await makeArt(tester);
    var layout = SummaryLayout.standard.encode();
    var left = 242000;
    var style = TimerStyle.digital;
    final weather = parseForecast(sampleForecast(), city: 'Austin');
    late StateSetter set;
    await tester.pumpWidget(
      stage(
        key,
        size,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            final s = StandbySettings(
              worldZone: 'Asia/Tokyo',
              worldCity: 'Tokyo',
              worldLat: 35.7,
              worldLon: 139.7,
              localCity: 'Austin',
              use24HourTime: false,
              summaryLayout: layout,
              timerStyle: style,
            );
            return SummaryCard(
              now: DateTime(2026, 10, 11, 14, 30),
              settings: s,
              weather: WeatherCard(
                snapshot: weather,
                settings: s,
                onCityTap: () {},
              ),
              music: MusicCard(
                snapshot: sampleSong(art),
                settings: s,
                onCommand: (_) async => true,
              ),
              timer: TimerTile(
                settings: s,
                leftMs: left,
                totalMs: 300000,
                running: true,
                started: true,
                done: false,
                onStart: () {},
                onPause: () {},
                onReset: () {},
                onAddMinute: () {},
                onOpen: () {},
                onSwipe: () => set(
                  () => style = style == TimerStyle.digital
                      ? TimerStyle.flip
                      : TimerStyle.digital,
                ),
              ),
              onAddTile: () {},
              onLayout: (v) => set(() => layout = v),
            );
          },
        ),
      ),
    );
    await tester.runAsync(
      () async => precacheImage(
        MemoryImage(art),
        tester.element(find.byType(SummaryCard)),
      ),
    );
    final rec = Rec(tester, key, 'summary-widgets');
    await rec.play(1500); // the cards deal in
    final hold = await tester.startGesture(
      tester.getCenter(find.text('SUNDAY')),
    );
    await rec.play(900); // hold: they jiggle, each gets a "-"
    await hold.up();
    await rec.play(500);
    // take the second city away: it shrinks, the others close the gap
    await tester.tap(find.byIcon(Icons.remove_rounded).at(1));
    await rec.play(1100); // and a "+" takes the free place
    // add the timer (what the "Add a widget" window does)
    set(
      () => layout = SummaryLayout.parse(
        layout,
      ).added(SummaryTile.timer)!.encode(),
    );
    await rec.play(1000); // it pops in
    await tester.tap(find.text('Done'));
    await rec.play(500);
    for (var i = 0; i < 2; i++) {
      set(() => left -= 1000);
      await rec.play(1000);
    }
    // swipe up on the time: the flip style
    final tile = tester.getRect(find.byType(TimerTile));
    await tester.flingFrom(
      tile.topLeft + Offset(tile.width / 2, tile.height * 0.3),
      const Offset(0, -120),
      900,
    );
    await rec.play(900);
    for (var i = 0; i < 2; i++) {
      set(() => left -= 1000);
      await rec.play(1000);
    }
  });
}
