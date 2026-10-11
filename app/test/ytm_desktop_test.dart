import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/services/ytm_desktop_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const song = {
    'title': 'Blinding Lights',
    'artist': 'The Weeknd',
    'imageSrc': 'https://img/x.jpg',
    'isPaused': false,
    'songDuration': 200,
    'elapsedSeconds': 50,
  };

  test('an address with or without port and scheme is understood', () async {
    final s = YtmDesktopService(
      client: MockClient((_) async => http.Response('', 204)),
    );
    await s.setAddress(' http://my-mac.local:26538/ ');
    expect(s.address, 'my-mac.local');
    await s.setAddress('192.168.1.20:9000');
    expect(s.address, '192.168.1.20:9000');
    await s.setAddress('');
    expect(s.isConfigured, isFalse);
  });

  test('now playing is read from the song endpoint', () async {
    final seen = <Uri>[];
    final s = YtmDesktopService(
      client: MockClient((r) async {
        seen.add(r.url);
        return http.Response(jsonEncode(song), 200);
      }),
    );
    await s.setAddress('192.168.1.20');
    final np = (await s.nowPlaying())!;
    expect(seen.single.toString(), 'http://192.168.1.20:26538/api/v1/song');
    expect(np.title, 'Blinding Lights');
    expect(np.artist, 'The Weeknd');
    expect(np.isPlaying, isTrue);
    expect(np.positionMs, 50000);
    expect(np.durationMs, 200000);
    expect(np.progress, closeTo(0.25, 1e-9));
    expect(np.viaYtm, isTrue);
    expect(np.viaSpotifyApi, isFalse);
  });

  test('nothing playing (204) and unreachable both read as nothing', () async {
    final none = YtmDesktopService(
      client: MockClient((_) async => http.Response('', 204)),
    );
    await none.setAddress('mac.local');
    expect(await none.nowPlaying(), isNull);
    final down = YtmDesktopService(
      client: MockClient((_) async => throw Exception('no route')),
    );
    await down.setAddress('mac.local');
    expect(await down.nowPlaying(), isNull);
    expect(down.lastError, contains('Cannot reach'));
  });

  test('commands go to the matching endpoints', () async {
    final calls = <String>[];
    final s = YtmDesktopService(
      client: MockClient((r) async {
        calls.add('${r.method} ${r.url.path} ${r.body}');
        return http.Response('', 204);
      }),
    );
    await s.setAddress('mac.local');
    expect(await s.command('playPause'), isTrue);
    await s.command('next');
    await s.command('previous');
    await s.command('forward10');
    await s.seekTo(75500);
    await s.setVolume(40);
    expect(calls, [
      'POST /api/v1/toggle-play ',
      'POST /api/v1/next ',
      'POST /api/v1/previous ',
      'POST /api/v1/go-forward {"seconds":10}',
      'POST /api/v1/seek-to {"seconds":75.5}',
      'POST /api/v1/volume {"volume":40}',
    ]);
    expect(await s.command('nonsense'), isFalse);
  });

  test('the first request signs in, remembers the token and retries', () async {
    final log = <String>[];
    final s = YtmDesktopService(
      client: MockClient((r) async {
        log.add('${r.method} ${r.url.path} ${r.headers['Authorization']}');
        if (r.url.path == '/auth/dockwise') {
          return http.Response(jsonEncode({'accessToken': 'tok123'}), 200);
        }
        if (r.headers['Authorization'] != 'Bearer tok123') {
          return http.Response('', 401);
        }
        return http.Response(jsonEncode(song), 200);
      }),
    );
    await s.setAddress('mac.local');
    expect(await s.nowPlaying(), isNotNull);
    expect(log, [
      'GET /api/v1/song null',
      'POST /auth/dockwise null',
      'GET /api/v1/song Bearer tok123',
    ]);
    // the token is kept: the next request does not sign in again
    log.clear();
    await s.nowPlaying();
    expect(log, ['GET /api/v1/song Bearer tok123']);
    // and survives a restart
    final again = YtmDesktopService(
      client: MockClient((r) async {
        log.add(r.headers['Authorization'] ?? '');
        return http.Response(jsonEncode(song), 200);
      }),
    );
    await again.load();
    log.clear();
    await again.nowPlaying();
    expect(log, ['Bearer tok123']);
  });

  test('a refused sign-in says what to do', () async {
    final s = YtmDesktopService(
      client: MockClient(
        (r) async =>
            http.Response('', r.url.path.startsWith('/auth') ? 403 : 401),
      ),
    );
    await s.setAddress('mac.local');
    expect(await s.check(), isFalse);
    expect(s.lastError, contains('Allow'));
  });

  test('volume is read as a percent', () async {
    final s = YtmDesktopService(
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'state': 65.0, 'isMuted': false}), 200),
      ),
    );
    await s.setAddress('mac.local');
    expect(await s.volume(), 65);
  });

  test(
    'the music card follows YouTube Music and its buttons control it',
    () async {
      final calls = <String>[];
      final ytm = YtmDesktopService(
        client: MockClient((r) async {
          calls.add('${r.method} ${r.url.path}');
          return r.url.path.endsWith('/song')
              ? http.Response(jsonEncode(song), 200)
              : http.Response('', 204);
        }),
      );
      await ytm.setAddress('mac.local');
      final c = StandbyController(
        autostartTicker: false,
        ytmService: ytm,
        initialSettings: const StandbySettings(
          leftWidget: StandbyWidgetType.music,
          musicSource: 'ytm',
        ),
      );
      addTearDown(c.dispose);
      await c.refreshMusic();
      expect(c.snapshots.nowPlaying.title, 'Blinding Lights');
      expect(c.snapshots.nowPlaying.viaYtm, isTrue);
      expect(await c.sendMediaCommand('next'), isTrue);
      expect(await c.seekToMs(60000), isTrue);
      expect(calls, contains('POST /api/v1/next'));
      expect(calls, contains('POST /api/v1/seek-to'));
    },
  );
}
