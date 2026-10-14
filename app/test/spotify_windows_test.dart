import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/services/spotify_service.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

// A PC: the Spotify desktop app only shows up as a device once it is open.
class _Spotify extends SpotifyService {
  _Spotify() {
    phoneName = 'HARDIK-MSI'; // the PC's name, as the runner reports it
  }
  bool open = false;
  final transfers = <String>[];

  @override
  bool get isConnected => true;
  @override
  bool get isConfigured => true;

  @override
  Future<List<SpotifyDevice>> devices() async => [
    const SpotifyDevice('phone', 'Pixel 8', 'Smartphone', false),
    if (open) const SpotifyDevice('pc', 'HARDIK-MSI', 'Computer', false),
  ];

  @override
  Future<bool> transferTo(String deviceId) async {
    transfers.add(deviceId);
    return open;
  }
}

class _Pc extends StandbySystemService {
  _Pc(this.spotify, {this.installed = true});
  final _Spotify spotify;
  final bool installed;
  int opened = 0, raised = 0;

  @override
  Future<bool> openSpotify() async {
    opened++;
    if (installed) spotify.open = true;
    return installed;
  }

  @override
  Future<bool> bringToFront() async {
    raised++;
    return true;
  }

  @override
  Future<NowPlayingSnapshot?> nowPlaying() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  StandbyController make(_Spotify s, _Pc pc) {
    final c = StandbyController(
      autostartTicker: false,
      spotifyService: s,
      systemService: pc,
      spotifyRetryDelay: Duration.zero,
    );
    addTearDown(c.dispose);
    return c;
  }

  test('Play on a PC opens Spotify, plays here, and comes back', () async {
    final s = _Spotify();
    final pc = _Pc(s);
    final c = make(s, pc);
    expect(await c.playOnThisDevice(), isTrue);
    expect(pc.opened, 1);
    expect(s.transfers.last, 'pc'); // this PC, not the phone
    expect(c.musicError, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(pc.raised, 1); // Hushdock back over Spotify's window
  });

  test('without Spotify on the PC it says so and offers it', () async {
    final s = _Spotify();
    final pc = _Pc(s, installed: false);
    final c = make(s, pc);
    expect(await c.playOnThisDevice(), isFalse);
    expect(c.musicError, 'Spotify is not installed on this PC');
    expect(c.spotifyMissing, isTrue);
    expect(c.musicError, isNot(contains('phone')));
  });

  group('this device in Spotify\'s list', () {
    const list = [
      SpotifyDevice('mac', 'MacBook Pro', 'Computer', true),
      SpotifyDevice('pixel', 'Pixel 8', 'Smartphone', false),
      SpotifyDevice('pc', 'HARDIK-MSI', 'Computer', false),
    ];

    test('a phone is the Smartphone with its name', () {
      expect(
        thisSpotifyDevice(list, name: 'Pixel', computer: false)?.id,
        'pixel',
      );
      expect(thisSpotifyDevice(list, name: 'iPhone', computer: false), isNull);
    });

    test('a PC is the Computer with its name, not a phone or a Mac', () {
      expect(
        thisSpotifyDevice(list, name: 'hardik-msi', computer: true)?.id,
        'pc',
      );
    });

    test('a PC named differently in Spotify: the only Computer listed', () {
      const one = [
        SpotifyDevice('pixel', 'Pixel 8', 'Smartphone', false),
        SpotifyDevice('pc', 'Hardik\'s laptop', 'Computer', false),
      ];
      expect(
        thisSpotifyDevice(one, name: 'HARDIK-MSI', computer: true)?.id,
        'pc',
      );
      // with two computers and no name match it does not guess
      expect(thisSpotifyDevice(list, name: 'OTHER-PC', computer: true), isNull);
    });
  });

  group('the sign-in redirect', () {
    test('the default comes back on hushdock:', () {
      expect(SpotifyService.usableRedirect(''), SpotifyService.defaultRedirect);
      final back = SpotifyService.callbackFor(SpotifyService.defaultRedirect);
      expect(back.scheme, 'hushdock');
      expect(back.options.httpsHost, isNull);
    });

    test('a custom one is used as given; the window watches its scheme', () {
      const mine = 'myapp://spotify/done';
      expect(SpotifyService.usableRedirect('  $mine '), mine);
      expect(SpotifyService.callbackFor(mine).scheme, 'myapp');
    });

    test('a web address is watched by host and path too', () {
      final back = SpotifyService.callbackFor(
        'https://example.com/spotify/callback',
      );
      expect(back.scheme, 'https');
      expect(back.options.httpsHost, 'example.com');
      expect(back.options.httpsPath, '/spotify/callback');
    });

    test('something that is not an address falls back to the default', () {
      expect(
        SpotifyService.usableRedirect('not a uri'),
        SpotifyService.defaultRedirect,
      );
    });
  });
}
