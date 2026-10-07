import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/integration_cards.dart';
import 'package:standby_pro/src/features/standby/widgets/music_sources_sheet.dart';
import 'package:standby_pro/src/features/standby/widgets/spotify_queue.dart';
import 'package:standby_pro/src/features/standby/widgets/spotify_search.dart';
import 'package:standby_pro/src/services/spotify_service.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

class _FakeSystem extends StandbySystemService {
  final calls = <String>[];
  @override
  Future<NowPlayingSnapshot?> nowPlaying() async => null; // no phone player here
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

class _SearchSpotify extends SpotifyService {
  final played = <String>[];
  final queued = <String>[];
  final searched = <String>[];
  final skips = <int>[];
  @override
  bool get isConnected => true;
  @override
  Future<SpotifyQueue?> queue() async => const SpotifyQueue(
    SpotifyHit('spotify:track:0', 'Now Song', 'Artist N', 'track', null),
    [
      SpotifyHit('spotify:track:11', 'Next One', 'Artist 1', 'track', null),
      SpotifyHit('spotify:track:12', 'Next Two', 'Artist 2', 'track', null),
    ],
  );
  @override
  Future<bool> skipNext(int times) async {
    skips.add(times);
    return true;
  }

  @override
  Future<List<SpotifyHit>> search(String query) async {
    searched.add(query);
    return const [
      SpotifyHit('spotify:track:1', 'Song A', 'Artist X', 'track', null),
      SpotifyHit('spotify:album:2', 'Album B', 'Artist Y', 'album', null),
      SpotifyHit('spotify:playlist:3', 'List C', 'Someone', 'playlist', null),
    ];
  }

  @override
  Future<bool> playUri(String uri, {String? deviceId}) async {
    played.add(uri);
    return true;
  }

  @override
  Future<bool> addToQueue(String uri) async {
    queued.add(uri);
    return true;
  }
}

class _PollSpotify extends SpotifyService {
  int polls = 0;
  @override
  bool get isConnected => true;
  @override
  Future<NowPlayingSnapshot?> nowPlaying() async {
    polls++;
    return NowPlayingSnapshot(
      title: 'Song $polls',
      artist: 'A',
      source: 'Spotify',
      progress: 0,
      isPlaying: true,
      isControllable: true,
      durationMs: 200000,
      positionMs: 0,
      viaSpotifyApi: true,
      fetchedAt: DateTime.now(),
    );
  }
}

/// Lets a test change the song as if another device did.
class _SongController extends StandbyController {
  _SongController(SpotifyService s)
    : super(spotifyService: s, autostartTicker: false);
  void song(String title) {
    snapshots = IntegrationSnapshotBundle(
      weather: snapshots.weather,
      nowPlaying: NowPlayingSnapshot(
        title: title,
        artist: 'A',
        source: 'Spotify',
        progress: 0,
        isPlaying: true,
        isControllable: true,
      ),
    );
    notifyListeners();
  }
}

class _CountingQueueSpotify extends SpotifyService {
  _CountingQueueSpotify(this.onQueue);
  final void Function() onQueue;
  @override
  bool get isConnected => true;
  @override
  Future<SpotifyQueue?> queue() async {
    onQueue();
    return const SpotifyQueue(null, []);
  }
}

/// Spotify that fails on the second read, then says nothing plays anywhere.
class _FlakySpotify extends SpotifyService {
  int polls = 0;
  @override
  bool get isConnected => true;
  @override
  bool get playerIdle => polls >= 4;
  @override
  Future<NowPlayingSnapshot?> nowPlaying() async {
    polls++;
    if (polls == 2) throw StateError('network blip');
    if (polls >= 4) return null; // 204: nothing playing anywhere
    return NowPlayingSnapshot(
      title: 'Old Song',
      artist: 'A',
      source: 'Spotify · Speaker',
      progress: 0,
      isPlaying: true,
      isControllable: true,
      durationMs: 200000,
      positionMs: 0,
      viaSpotifyApi: true,
      fetchedAt: DateTime.now(),
    );
  }
}

/// Spotify that is slow to switch devices: it keeps saying the old one plays
/// for the first few answers after a transfer.
class _SlowSwitchSpotify extends SpotifyService {
  String active = 's';
  String? target;
  int staleAnswers = 0;
  @override
  bool get isConnected => true;
  @override
  Future<List<SpotifyDevice>> devices() async {
    if (target != null && staleAnswers-- <= 0) {
      active = target!;
      target = null;
    }
    return [
      SpotifyDevice('p', 'Phone', 'Smartphone', active == 'p', volume: 50),
      SpotifyDevice('s', 'Speaker', 'Speaker', active == 's', volume: 40),
    ];
  }

  @override
  Future<bool> transferTo(String deviceId) async {
    target = deviceId;
    staleAnswers = 1; // the next answer is still the old device
    return true;
  }

  @override
  Future<List<SpotifyPlaylist>> playlists() async => const [];
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
  testWidgets(
    'Play on: your choice shows at once and stays, even if Spotify lags',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final spotify = _SlowSwitchSpotify();
      final c = StandbyController(
        spotifyService: spotify,
        systemService: _FakeSystem(),
        autostartTicker: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MusicSourcesPanel(controller: c)),
        ),
      );
      await tester.pump();
      await tester.pump();
      Finder playingNow(String device) => find.descendant(
        of: find.widgetWithText(ListTile, device),
        matching: find.text('Playing now'),
      );
      expect(playingNow('Speaker'), findsOneWidget);

      await tester.tap(find.text('Phone'));
      await tester.pump(); // no waiting for Spotify
      expect(playingNow('Phone'), findsOneWidget); // shown at once
      expect(playingNow('Speaker'), findsNothing);

      await tester.pump(
        const Duration(milliseconds: 1000),
      ); // 1st re-check: still the old answer
      await tester.pump();
      expect(playingNow('Phone'), findsOneWidget); // did not flip back
      await tester.pump(
        const Duration(milliseconds: 1500),
      ); // 2nd re-check: confirmed
      await tester.pump();
      expect(playingNow('Phone'), findsOneWidget);
      expect(playingNow('Speaker'), findsNothing);
      await tester.pumpWidget(const SizedBox()); // stops the 5 s timer
    },
  );

  testWidgets(
    'one failed read does not stop the polling, and a stale song clears',
    (tester) async {
      final spotify = _FlakySpotify();
      final c = StandbyController(
        initialSettings: const StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.music,
        ),
        spotifyService: spotify,
        systemService: _FakeSystem(),
      );
      c.initializeForTest();
      await c.refreshMusic(); // read 1: a song
      expect(c.snapshots.nowPlaying.title, 'Old Song');
      await tester.pump(const Duration(milliseconds: 1000)); // read 2 throws
      expect(spotify.polls, 2);
      await tester.pump(
        const Duration(milliseconds: 1000),
      ); // polling carried on
      expect(spotify.polls, 3);
      expect(
        c.snapshots.nowPlaying.title,
        'Old Song',
      ); // an error alone changes nothing
      await tester.pump(
        const Duration(milliseconds: 1000),
      ); // read 4: nothing playing
      expect(
        c.snapshots.nowPlaying.title,
        'Old Song',
      ); // one answer is not enough
      await tester.pump(
        const Duration(milliseconds: 1000),
      ); // read 5: nothing playing again
      expect(c.snapshots.nowPlaying.viaSpotifyApi, isFalse);
      expect(c.snapshots.nowPlaying.title, isNot('Old Song')); // no stale song
      c.dispose();
    },
  );

  test('a podcast episode is shown instead of nothing', () async {
    SharedPreferences.setMockInitialValues({'spotify_refresh': 'r'});
    final spotify = SpotifyService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          return http.Response('{"access_token":"a","expires_in":3600}', 200);
        }
        expect(request.url.query, contains('additional_types=episode'));
        return http.Response(
          '{"is_playing":true,"progress_ms":1000,"device":{"name":"iPhone"},'
          '"item":{"uri":"spotify:episode:9","name":"Episode 9","duration_ms":60000,'
          '"show":{"name":"A Podcast"},"images":[{"url":"cover"}]}}',
          200,
        );
      }),
    );
    await spotify.load();
    final np = (await spotify.nowPlaying())!;
    expect(np.title, 'Episode 9');
    expect(np.artist, 'A Podcast');
    expect(np.artUrl, 'cover');
    expect(spotify.playerIdle, isFalse);
  });

  test('204 means nothing is playing; an error does not', () async {
    SharedPreferences.setMockInitialValues({'spotify_refresh': 'r'});
    var status = 204;
    final spotify = SpotifyService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          return http.Response('{"access_token":"a","expires_in":3600}', 200);
        }
        return http.Response('', status);
      }),
    );
    await spotify.load();
    expect(await spotify.nowPlaying(), isNull);
    expect(spotify.playerIdle, isTrue);
    status = 500;
    expect(await spotify.nowPlaying(), isNull);
    expect(spotify.playerIdle, isFalse); // unknown, so keep what is on screen
  });

  testWidgets('a song changed elsewhere shows up within about a second', (
    tester,
  ) async {
    final spotify = _PollSpotify();
    final c = StandbyController(
      initialSettings: const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.music,
      ),
      spotifyService: spotify,
      systemService: _FakeSystem(),
    );
    c.initializeForTest();
    await c.refreshMusic();
    expect(spotify.polls, 1);
    await tester.pump(const Duration(milliseconds: 900));
    expect(spotify.polls, 1); // not yet
    await tester.pump(const Duration(milliseconds: 200));
    expect(spotify.polls, 2); // looked again after ~1 s (was every 5 s)
    expect(c.snapshots.nowPlaying.title, 'Song 2');
    c.dispose(); // stops the timer
  });

  test(
    'after a 429 the service waits as told instead of asking again',
    () async {
      SharedPreferences.setMockInitialValues({'spotify_refresh': 'r'});
      var requests = 0;
      final spotify = SpotifyService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/token')) {
            return http.Response('{"access_token":"a","expires_in":3600}', 200);
          }
          requests++;
          return http.Response('', 429, headers: {'retry-after': '2'});
        }),
      );
      await spotify.load();
      await spotify.devices(); // answered 429
      expect(requests, 1);
      await spotify.devices();
      await spotify.devices();
      expect(requests, 1); // nothing was sent while we are told to wait
    },
  );

  testWidgets(
    'the queue reloads right away when the song changes on another device',
    (tester) async {
      final spotify = _SearchSpotify();
      final c = _SongController(spotify);
      c.song('First');
      var loads = 0;
      final counting = _CountingQueueSpotify(() => loads++);
      final c2 = _SongController(counting);
      c2.song('First');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: SpotifyQueueView(controller: c2, onClose: () {}),
            ),
          ),
        ),
      );
      await tester.pump();
      final first = loads;
      expect(first, greaterThan(0));
      c2.song('Second'); // another device skipped
      await tester.pump(const Duration(milliseconds: 500));
      expect(loads, greaterThan(first)); // reloaded well before the 10 s timer
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('Spotify queue: now playing, up next, and skipping ahead', () async {
    SharedPreferences.setMockInitialValues({'spotify_refresh': 'r'});
    final seen = <String>[];
    final spotify = SpotifyService(
      client: MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/token')) {
          return http.Response('{"access_token":"a","expires_in":3600}', 200);
        }
        if (request.url.path.endsWith('/queue')) {
          return http.Response(
            '{"currently_playing":{"uri":"spotify:track:0","name":"Now",'
            '"artists":[{"name":"A"}],"album":{"images":[{"url":"u"}]}},'
            '"queue":[{"uri":"spotify:track:1","name":"One","artists":[{"name":"B"}],'
            '"album":{"images":[]}},null,'
            '{"uri":"spotify:episode:2","name":"Episode","artists":[],'
            '"show":{"name":"A Podcast"},"images":[{"url":"e"}]}]}',
            200,
          );
        }
        return http.Response('', 204);
      }),
    );
    await spotify.load();

    final q = (await spotify.queue())!;
    expect(q.now!.title, 'Now');
    expect(q.next.map((h) => h.title), [
      'One',
      'Episode',
    ]); // the null entry is skipped
    expect(q.next[1].subtitle, 'A Podcast'); // episodes show their podcast
    seen.clear();
    expect(await spotify.skipNext(3), isTrue);
    expect(seen.where((r) => r == 'POST /v1/me/player/next').length, 3);
  });

  testWidgets(
    'queue view lists up next, jumps to the song you tap, and closes',
    (tester) async {
      final spotify = _SearchSpotify();
      final c = StandbyController(
        spotifyService: spotify,
        systemService: _FakeSystem(),
        autostartTicker: false,
      );
      var closed = 0;
      var touched = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: SpotifyQueueView(
                controller: c,
                onClose: () => closed++,
                onTouch: () => touched++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('Now playing'), findsOneWidget);
      expect(find.text('Next in queue'), findsOneWidget);
      expect(
        find.text('Now Song'),
        findsOneWidget,
      ); // what is playing, highlighted
      expect(find.text('Next One'), findsOneWidget);
      expect(find.text('Next Two'), findsOneWidget);

      await tester.tap(find.text('Next Two')); // second in the queue = 2 skips
      await tester.pump();
      expect(spotify.skips, [2]);
      expect(touched, greaterThan(0)); // keeps the card from auto-closing
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byTooltip('Close queue'));
      expect(closed, 1);
      await tester.pumpWidget(const SizedBox()); // stops the refresh timer
    },
  );

  testWidgets('the queue has a search button only when search is offered', (
    tester,
  ) async {
    final c = StandbyController(
      spotifyService: _SearchSpotify(),
      systemService: _FakeSystem(),
      autostartTicker: false,
    );
    Widget view({VoidCallback? onSearch}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 500,
          child: SpotifyQueueView(
            controller: c,
            onClose: () {},
            onSearch: onSearch,
          ),
        ),
      ),
    );
    await tester.pumpWidget(view());
    await tester.pump();
    expect(find.byTooltip('Search Spotify'), findsNothing);
    await tester.pumpWidget(const SizedBox()); // stops the refresh timer

    var searches = 0;
    await tester.pumpWidget(view(onSearch: () => searches++));
    await tester.pump();
    await tester.tap(find.byTooltip('Search Spotify'));
    expect(searches, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the music card opens its queue and closes it by itself', (
    tester,
  ) async {
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
              queueView: (close, keepOpen) =>
                  TextButton(onPressed: close, child: const Text('QUEUE OPEN')),
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('QUEUE OPEN'),
      findsNothing,
    ); // the card stays calm by default
    await tester.tap(find.byTooltip('Up next'));
    await tester.pump();
    expect(find.text('QUEUE OPEN'), findsOneWidget);
    await tester.tap(find.text('QUEUE OPEN')); // the view's own close
    await tester.pump();
    expect(find.text('QUEUE OPEN'), findsNothing);

    await tester.tap(find.byTooltip('Up next'));
    await tester.pump();
    expect(find.text('QUEUE OPEN'), findsOneWidget);
    await tester.pump(
      const Duration(seconds: 21),
    ); // no touch: back to now playing
    expect(find.text('QUEUE OPEN'), findsNothing);
  });

  testWidgets('search page: type, results, play and add to queue', (
    tester,
  ) async {
    final spotify = _SearchSpotify();
    final c = StandbyController(
      spotifyService: spotify,
      systemService: _FakeSystem(),
      autostartTicker: false,
    );
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SpotifySearchPage(controller: c),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Type to search'), findsOneWidget);

    await tester.tap(find.text('a'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(spotify.searched, isEmpty); // one letter is not enough

    await tester.tap(find.text('b'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(spotify.searched, ['ab']);
    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('Songs'), findsOneWidget); // section headers
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);

    await tester.tap(find.byTooltip('Add to queue'));
    await tester.pump();
    expect(spotify.queued, ['spotify:track:1']);
    expect(find.text('Added to queue'), findsOneWidget);

    await tester.tap(find.text('Album B')); // plays and returns to the card
    await tester.pumpAndSettle();
    expect(spotify.played, ['spotify:album:2']);
    expect(find.byType(SpotifySearchPage), findsNothing);
    expect(find.text('Playing Album B'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'the music card shows a search button only when search is offered',
    (tester) async {
      Widget card({VoidCallback? onSearch}) => MaterialApp(
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
              onSearch: onSearch,
            ),
          ),
        ),
      );
      await tester.pumpWidget(card());
      expect(find.byTooltip('Search Spotify'), findsNothing);
      var opened = 0;
      await tester.pumpWidget(card(onSearch: () => opened++));
      await tester.tap(find.byTooltip('Search Spotify'));
      expect(opened, 1);
    },
  );

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
