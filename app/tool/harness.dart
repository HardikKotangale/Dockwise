// Shared by the README recorders: fonts, a frame recorder, a stage widget and
// sample data (no real names, places or accounts).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/services/spotify_service.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';

const fps = 15;

Future<void> loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = File(p).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> loadFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter';
  final mf = '$root/bin/cache/artifacts/material_fonts';
  await loadFont('Roboto', [
    for (final w in ['Regular', 'Medium', 'Bold', 'Light', 'Thin'])
      if (File('$mf/Roboto-$w.ttf').existsSync()) '$mf/Roboto-$w.ttf',
  ]);
  await loadFont('MaterialIcons', ['$mf/MaterialIcons-Regular.otf']);
  await loadFont('BebasNeue', ['assets/fonts/BebasNeue-Regular.ttf']);
}

/// Pumps and saves frames.
class Rec {
  Rec(this.tester, this.key, String name, {this.scale = 1.5}) {
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
    const step = 1000 ~/ fps;
    for (var t = 0; t < ms; t += step) {
      await tester.pump(Duration(milliseconds: step));
      await shot();
    }
  }
}

Widget stage(GlobalKey key, Size size, Widget child) => RepaintBoundary(
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

void surface(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<Uint8List> makeArt(WidgetTester tester) async {
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

Map<String, dynamic> sampleForecast({int base = 17}) => {
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

NowPlayingSnapshot sampleSong(Uint8List art, {bool playing = true}) =>
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
      fetchedAt: DateTime.now(),
    );

/// Spotify with a made-up account: devices, a queue and search results.
class DemoSpotify extends SpotifyService {
  @override
  bool get isConnected => true;
  @override
  bool get isConfigured => true;

  @override
  Future<List<SpotifyDevice>> devices() async => const [
    SpotifyDevice('mac', 'MacBook Pro', 'Computer', true, volume: 55),
    SpotifyDevice('phone', 'iPhone', 'Smartphone', false, volume: 70),
    SpotifyDevice('room', 'Living Room', 'Speaker', false, volume: 40),
  ];

  @override
  Future<List<SpotifyPlaylist>> playlists() async => const [
    SpotifyPlaylist('spotify:playlist:1', 'Late Night Drive', null),
    SpotifyPlaylist('spotify:playlist:2', 'Focus', null),
    SpotifyPlaylist('spotify:playlist:3', 'Sunday Morning', null),
  ];

  @override
  Future<SpotifyQueue?> queue() async => const SpotifyQueue(
    SpotifyHit(
      'spotify:track:0',
      'Blinding Lights',
      'The Weeknd',
      'track',
      null,
    ),
    [
      SpotifyHit(
        'spotify:track:1',
        'Save Your Tears',
        'The Weeknd',
        'track',
        null,
      ),
      SpotifyHit(
        'spotify:track:2',
        'Starboy',
        'The Weeknd, Daft Punk',
        'track',
        null,
      ),
      SpotifyHit('spotify:track:3', 'Levitating', 'Dua Lipa', 'track', null),
      SpotifyHit(
        'spotify:track:4',
        'Heat Waves',
        'Glass Animals',
        'track',
        null,
      ),
      SpotifyHit('spotify:track:5', 'As It Was', 'Harry Styles', 'track', null),
    ],
  );

  @override
  Future<List<SpotifyHit>> search(String query) async => const [
    SpotifyHit(
      'spotify:track:11',
      'Blinding Lights',
      'The Weeknd',
      'track',
      null,
    ),
    SpotifyHit('spotify:album:12', 'After Hours', 'The Weeknd', 'album', null),
    SpotifyHit(
      'spotify:track:13',
      'Starboy',
      'The Weeknd, Daft Punk',
      'track',
      null,
    ),
    SpotifyHit(
      'spotify:playlist:14',
      'This Is The Weeknd',
      'Spotify',
      'playlist',
      null,
    ),
    SpotifyHit(
      'spotify:track:15',
      'Save Your Tears',
      'The Weeknd',
      'track',
      null,
    ),
  ];

  @override
  Future<bool> addToQueue(String uri) async => true;
  @override
  Future<bool> playUri(String uri, {String? deviceId}) async => true;
  @override
  Future<bool> skipNext(int times) async => true;
  @override
  Future<bool> setVolume(int percent, String deviceId) async => true;
}

/// A phone with nothing of its own playing.
class DemoSystem extends StandbySystemService {
  @override
  Future<NowPlayingSnapshot?> nowPlaying() async => null;
  @override
  Future<List<({String package, String app})>> mediaPlayers() async => const [];
}
