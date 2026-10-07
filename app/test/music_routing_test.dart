import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/music_sources_sheet.dart';
import 'package:standby_pro/src/services/spotify_service.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

class _FakeSystem extends StandbySystemService {
  final calls = <String>[];
  @override
  Future<bool> mediaCommand(String command) async {
    calls.add(command);
    return true;
  }

  @override
  Future<bool> seekBy(int deltaMs) async {
    calls.add('seek$deltaMs');
    return true;
  }

  @override
  Future<bool> seekTo(int positionMs) async {
    calls.add('to$positionMs');
    return true;
  }
}

class _VolumeSpotify extends SpotifyService {
  _VolumeSpotify(this.volume);
  final int? volume;
  final sent = <int>[];
  @override
  bool get isConnected => true;
  @override
  Future<List<SpotifyDevice>> devices() async => [
    SpotifyDevice('mac', 'Mac', 'Computer', true, volume: volume),
  ];
  @override
  Future<bool> setVolume(int percent, String deviceId) async {
    sent.add(percent);
    return true;
  }
}

class _FakeSpotify extends SpotifyService {
  final calls = <String>[];
  @override
  Future<bool> seekTo(int positionMs) async {
    calls.add('to$positionMs');
    return true;
  }

  @override
  Future<bool> command(
    String command, {
    required bool isPlaying,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    calls.add(command);
    return true;
  }
}

IntegrationSnapshotBundle _bundle({required bool viaApi}) =>
    IntegrationSnapshotBundle(nowPlaying: _snap(viaApi: viaApi));

NowPlayingSnapshot _snap({required bool viaApi}) => NowPlayingSnapshot(
  title: 't',
  artist: 'a',
  source: 'Spotify',
  progress: 0,
  isPlaying: true,
  isControllable: true,
  viaSpotifyApi: viaApi,
);

void main() {
  testWidgets('volume card follows the slider and sends what you chose', (
    tester,
  ) async {
    final spotify = _VolumeSpotify(35);
    final c = StandbyController(
      spotifyService: spotify,
      systemService: _FakeSystem(),
      autostartTicker: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SpotifyVolume(controller: c)),
      ),
    );
    await tester.pump();
    expect(find.text('35%'), findsOneWidget);
    expect(find.text('Volume · Mac'), findsOneWidget);

    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(spotify.sent, isNotEmpty);
    expect(spotify.sent.last, greaterThan(35));
    // the slider keeps the new value instead of snapping back to 35
    expect(find.text('${spotify.sent.last}%'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_up_rounded)); // mute
    await tester.pump();
    expect(spotify.sent.last, 0);
    expect(find.text('0%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // let timers finish
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a device without remote volume says so', (tester) async {
    final c = StandbyController(
      spotifyService: _VolumeSpotify(null),
      systemService: _FakeSystem(),
      autostartTicker: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SpotifyVolume(controller: c)),
      ),
    );
    await tester.pump();
    expect(find.textContaining("doesn't allow volume control"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'Spotify volume: devices report it and the slider sets it by device',
    () async {
      SharedPreferences.setMockInitialValues({'spotify_refresh': 'r'});
      final seen = <String>[];
      final spotify = SpotifyService(
        client: MockClient((request) async {
          seen.add(
            '${request.method} ${request.url.path}?${request.url.query}',
          );
          if (request.url.path.endsWith('/token')) {
            return http.Response('{"access_token":"a","expires_in":3600}', 200);
          }
          if (request.url.path.endsWith('/devices')) {
            return http.Response(
              '{"devices":[{"id":"mac1","name":"Mac","type":"Computer",'
              '"is_active":true,"volume_percent":35},'
              '{"id":"tv","name":"TV","type":"TV","is_active":false,'
              '"volume_percent":null}]}',
              200,
            );
          }
          return http.Response('', 204);
        }),
      );
      await spotify.load();

      final devices = await spotify.devices();
      expect(devices.first.volume, 35);
      expect(devices.last.volume, isNull); // cannot be controlled remotely

      expect(await spotify.setVolume(70, 'mac1'), isTrue);
      expect(
        seen.last,
        'PUT /v1/me/player/volume?volume_percent=70&device_id=mac1',
      );
      await spotify.setVolume(150, 'mac1'); // clamped
      expect(seen.last, contains('volume_percent=100'));
    },
  );

  test(
    'a Spotify card read from the phone is controlled on the phone',
    () async {
      final system = _FakeSystem();
      final spotify = _FakeSpotify();
      final c = StandbyController(
        systemService: system,
        spotifyService: spotify,
        snapshots: _bundle(viaApi: false),
        autostartTicker: false,
      );

      await c.sendMediaCommand('next');
      await c.sendMediaCommand('forward10');

      expect(system.calls, ['next', 'seek10000']);
      expect(spotify.calls, isEmpty);
    },
  );

  test(
    'a card read from the Spotify Web API is controlled through it',
    () async {
      final system = _FakeSystem();
      final spotify = _FakeSpotify();
      final c = StandbyController(
        systemService: system,
        spotifyService: spotify,
        snapshots: _bundle(viaApi: true),
        autostartTicker: false,
      );

      await c.sendMediaCommand('next');

      expect(spotify.calls, ['next']);
      expect(system.calls, isEmpty);
    },
  );

  test(
    'seeking goes to the player shown on the card and shows at once',
    () async {
      final system = _FakeSystem();
      final spotify = _FakeSpotify();
      final phone = StandbyController(
        systemService: system,
        spotifyService: spotify,
        snapshots: _bundle(viaApi: false),
        autostartTicker: false,
      );
      final web = StandbyController(
        systemService: system,
        spotifyService: spotify,
        snapshots: _bundle(viaApi: true),
        autostartTicker: false,
      );

      await phone.seekToMs(90000);
      await web.seekToMs(45000);

      expect(system.calls, ['to90000']); // phone session
      expect(spotify.calls, ['to45000']); // Spotify account
      // the card jumps immediately, before the next poll confirms it
      expect(phone.snapshots.nowPlaying.positionMs, 90000);
      expect(web.snapshots.nowPlaying.positionMs, 45000);
    },
  );
}
