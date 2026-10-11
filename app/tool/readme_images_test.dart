// Renders the README screenshots of the music card and the settings dock from
// the app's own widgets, with sample data only (a made-up Spotify account):
//
//   cd app && flutter test tool/readme_images_test.dart
//
// The PNGs go to ../docs/screenshots/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/battery_badge.dart';
import 'package:standby_pro/src/features/standby/widgets/integration_cards.dart';
import 'package:standby_pro/src/features/standby/widgets/music_sources_sheet.dart';
import 'package:standby_pro/src/features/standby/widgets/spotify_queue.dart';
import 'package:standby_pro/src/features/standby/widgets/spotify_search.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

import 'harness.dart';

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../docs/screenshots/$name.png');
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  StandbyController controller() {
    final c = StandbyController(
      autostartTicker: false,
      spotifyService: DemoSpotify(),
      systemService: DemoSystem(),
      initialSettings: const StandbySettings(),
    );
    addTearDown(c.dispose);
    return c;
  }

  // The music card as it is in the app, with all three header buttons.
  Future<(GlobalKey, StandbyController)> musicCard(WidgetTester tester) async {
    const size = Size(400, 500);
    surface(tester, size);
    final key = GlobalKey();
    final c = controller();
    final art = await makeArt(tester);
    final song = NowPlayingSnapshot(
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      source: 'Spotify · MacBook Pro',
      progress: 0.38,
      isPlaying: true,
      isControllable: true,
      viaSpotifyApi: true,
      durationMs: 200000,
      positionMs: 76000,
      artBytes: art,
      fetchedAt: DateTime.now(),
    );
    await tester.pumpWidget(
      stage(
        key,
        size,
        Padding(
          padding: const EdgeInsets.all(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: MusicCard(
              snapshot: song,
              settings: const StandbySettings(),
              onCommand: (_) async => true,
              onSearch: () {},
              loadDevices: c.spotifyDevices,
              onSource: (_) {},
              onDevice: (_) {},
              queueView: (close, keepOpen) => SpotifyQueueView(
                controller: c,
                onClose: close,
                onTouch: keepOpen,
                onSearch: () {},
              ),
              volumeBar: (keepOpen) => SpotifyVolume(
                controller: c,
                compact: true,
                onTouch: keepOpen,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => precacheImage(
        MemoryImage(art),
        tester.element(find.byType(MusicCard)),
      ),
    );
    await c.spotifyDevices();
    await tester.pump(const Duration(milliseconds: 600));
    return (key, c);
  }

  testWidgets('music card with its buttons', (tester) async {
    final (key, _) = await musicCard(tester);
    await _save(tester, key, 'spotify-card-buttons');
  });

  testWidgets('music card with the volume bar', (tester) async {
    final (key, _) = await musicCard(tester);
    expect(find.byTooltip('Volume'), findsOneWidget);
    await tester.tap(find.byTooltip('Volume'));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(SpotifyVolume), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await _save(tester, key, 'music-card-volume');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('music card with the queue', (tester) async {
    final (key, _) = await musicCard(tester);
    await tester.tap(find.byTooltip('Up next'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await _save(tester, key, 'spotify-queue');
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('spotify search', (tester) async {
    const size = Size(700, 380);
    surface(tester, size);
    final key = GlobalKey();
    final c = controller();
    await tester.pumpWidget(stage(key, size, SpotifySearchPage(controller: c)));
    await tester.pump(const Duration(milliseconds: 300));
    for (final ch in 'weeknd'.split('')) {
      await tester.tap(find.text(ch).first);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(const Duration(milliseconds: 1500));
    await _save(tester, key, 'spotify-search');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('music settings', (tester) async {
    const size = Size(520, 600);
    surface(tester, size);
    final key = GlobalKey();
    final c = controller();
    await tester.pumpWidget(
      stage(
        key,
        size,
        Material(
          color: const Color(0xFF1C1C1E),
          child: MusicSourcesPanel(controller: c),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await _save(tester, key, 'music-settings');
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('settings dock', (tester) async {
    const size = Size(844, 390);
    surface(tester, size);
    final key = GlobalKey();
    final battery = BatteryMonitor(
      read: () async => (level: 72, charging: false, full: false),
      every: const Duration(days: 1),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: StandbyProApp(
          battery: battery,
          systemService: DemoSystem(),
          initialSettings: const StandbySettings(
            leftWidget: StandbyWidgetType.clock,
            rightWidget: StandbyWidgetType.calendar,
            use24HourTime: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(200, 200)); // tap the clock panel
    await tester.pump(const Duration(milliseconds: 1200));
    await _save(tester, key, 'settings-dock');
    await tester.pump(const Duration(seconds: 3));
    battery.dispose();
  });
}
