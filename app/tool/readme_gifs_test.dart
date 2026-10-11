// Records the animations shown in the README as numbered PNG frames, using
// sample data only. Run it, then turn the frames into GIFs:
//
//   cd app
//   flutter test tool/readme_gifs_test.dart
//   python3 tool/frames_to_gif.py
//
// Frames go to build/readme_frames/<scene>/, the GIFs to ../docs/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/core/apple.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/domain/summary_layout.dart';
import 'package:standby_pro/src/features/standby/widgets/clock_faces.dart';
import 'package:standby_pro/src/features/standby/widgets/integration_cards.dart';
import 'package:standby_pro/src/features/standby/widgets/summary_card.dart';
import 'package:standby_pro/src/services/weather_service.dart';

const _fps = 15;

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = File(p).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _fonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter';
  final mf = '$root/bin/cache/artifacts/material_fonts';
  await _loadFont('Roboto', [
    for (final w in ['Regular', 'Medium', 'Bold', 'Light', 'Thin'])
      if (File('$mf/Roboto-$w.ttf').existsSync()) '$mf/Roboto-$w.ttf',
  ]);
  await _loadFont('MaterialIcons', ['$mf/MaterialIcons-Regular.otf']);
  await _loadFont('BebasNeue', ['assets/fonts/BebasNeue-Regular.ttf']);
}

/// Pumps and saves frames.
class _Rec {
  _Rec(this.tester, this.key, String name, {this.scale = 1.5}) {
    dir = Directory('build/readme_frames/$name')..createSync(recursive: true);
    for (final f in dir.listSync()) {
      f.deleteSync();
    }
  }

  final WidgetTester tester;
  final GlobalKey key;
  final double scale;
  late final Directory dir;
  int n = 0;

  Future<void> shot() async {
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: scale);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${dir.path}/${n.toString().padLeft(4, '0')}.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
      n++;
    });
  }

  /// run for [ms], one frame per 1/fps
  Future<void> play(int ms) async {
    const step = 1000 ~/ _fps;
    for (var t = 0; t < ms; t += step) {
      await tester.pump(Duration(milliseconds: step));
      await shot();
    }
  }
}

Widget _stage(GlobalKey key, Size size, Widget child) => RepaintBoundary(
  key: key,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    // plain Text (labels in the overlay) needs the font too, not only Material
    builder: (context, child) => DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Roboto'),
      child: child!,
    ),
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: Colors.black,
    ),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(width: size.width, height: size.height, child: child),
    ),
  ),
);

void _surface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<Uint8List> _art(WidgetTester tester) async {
  final bytes = await tester.runAsync(() async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const r = Rect.fromLTWH(0, 0, 300, 300);
    c.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B8B), Color(0xFF6A4CF0), Color(0xFF1F2A6B)],
        ).createShader(r),
    );
    c.drawCircle(
      const Offset(190, 110),
      70,
      Paint()..color = const Color(0x55FFFFFF),
    );
    final img = await rec.endRecording().toImage(300, 300);
    return (await img.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  });
  return bytes!;
}

Map<String, dynamic> _forecast({int base = 17}) => {
  'current': {
    'time': '2026-10-11T14:30',
    'temperature_2m': base + 2.4,
    'weather_code': 2,
    'is_day': 1,
  },
  'hourly': {
    'time': [
      for (var h = 0; h < 24; h++)
        '2026-10-11T${h.toString().padLeft(2, '0')}:00',
    ],
    'temperature_2m': [
      for (var h = 0; h < 24; h++) base + (h < 15 ? h ~/ 3 : 5 - (h - 15) ~/ 2),
    ],
    'weather_code': [for (var h = 0; h < 24; h++) h > 17 ? 0 : 2],
    'is_day': [for (var h = 0; h < 24; h++) (h > 6 && h < 19) ? 1 : 0],
  },
  'daily': {
    'time': [for (var d = 11; d < 18; d++) '2026-10-$d'],
    'weather_code': [2, 3, 61, 61, 2, 0, 0],
    'temperature_2m_max': [
      base + 5,
      base + 4,
      base + 2,
      base + 3,
      base + 5,
      base + 7,
      base + 8,
    ],
    'temperature_2m_min': [
      base - 3,
      base - 4,
      base - 2,
      base - 5,
      base - 4,
      base - 2,
      base - 1,
    ],
  },
};

NowPlayingSnapshot _song(Uint8List art, {bool playing = true}) =>
    NowPlayingSnapshot(
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      source: 'Spotify · MacBook Pro',
      progress: 0.38,
      isPlaying: playing,
      isControllable: true,
      durationMs: 200000,
      positionMs: 76000,
      artBytes: art,
      fetchedAt: DateTime(2026, 10, 11, 14, 30),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_fonts);

  // 1. The page indicator: tap to show, press and slide, lift to go there.
  testWidgets('page dots', (tester) async {
    const size = Size(440, 250);
    _surface(tester, size);
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
      _stage(
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
    final rec = _Rec(tester, key, 'page-dots');
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
    _surface(tester, size);
    final key = GlobalKey();
    final art = await _art(tester);
    var layout = SummaryLayout.standard.encode();
    final weather = parseForecast(_forecast(), city: 'Austin');
    late StateSetter set;
    await tester.pumpWidget(
      _stage(
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
                snapshot: _song(art),
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
    final rec = _Rec(tester, key, 'summary');
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
    _surface(tester, size);
    final key = GlobalKey();
    var landscape = true;
    var style = ClockStyle.digital;
    late StateSetter set;
    await tester.pumpWidget(
      _stage(
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
    final rec = _Rec(tester, key, 'clock-rotate', scale: 1.2);
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
    _surface(tester, size);
    final key = GlobalKey();
    var page = 0;
    late StateSetter set;
    final here = parseForecast(_forecast(), city: 'Austin');
    final there = parseForecast(_forecast(base: 12), city: 'Tokyo');
    await tester.pumpWidget(
      _stage(
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
    final rec = _Rec(tester, key, 'weather-pages');
    await rec.play(900);
    for (final p in [1, 2, 3, 0]) {
      set(() => page = p);
      await rec.play(1700);
    }
  });

  // 5. The music card's buttons: press feedback, play/pause morph, hold label.
  testWidgets('music buttons', (tester) async {
    const size = Size(380, 470);
    _surface(tester, size);
    final key = GlobalKey();
    final art = await _art(tester);
    var playing = true;
    late StateSetter set;
    await tester.pumpWidget(
      _stage(
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
                  snapshot: _song(art, playing: playing),
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
    final rec = _Rec(tester, key, 'music-buttons');
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
}
