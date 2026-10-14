import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/services/spotify_service.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

// Spotify lists a phone as a device, but transferring to it fails until the
// Spotify app on that phone is awake.
class _Spotify extends SpotifyService {
  _Spotify() {
    phoneName = 'iPhone';
  }
  bool awake = false;
  final transfers = <String>[];

  @override
  bool get isConnected => true;
  @override
  bool get isConfigured => true;

  @override
  Future<List<SpotifyDevice>> devices() async => const [
    SpotifyDevice('mac', 'MacBook Pro', 'Computer', true),
    SpotifyDevice('phone', 'iPhone', 'Smartphone', false),
  ];

  @override
  Future<bool> transferTo(String deviceId) async {
    transfers.add(deviceId);
    final ok = deviceId == 'mac' ? awake : awake;
    lastError = ok ? null : 'Spotify: Spotify is not open on that device';
    return ok;
  }
}

class _System extends StandbySystemService {
  _System(this.spotify, {this.installed = true});
  final _Spotify spotify;
  final bool installed;
  int opened = 0;

  @override
  Future<bool> openSpotify() async {
    opened++;
    if (installed) spotify.awake = true; // the app wakes up and registers
    return installed;
  }

  @override
  Future<NowPlayingSnapshot?> nowPlaying() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  StandbyController make(_Spotify s, _System sys) {
    final c = StandbyController(
      autostartTicker: false,
      spotifyService: s,
      systemService: sys,
      spotifyRetryDelay: Duration.zero,
    );
    addTearDown(c.dispose);
    return c;
  }

  test('playing on this phone opens Spotify there, then carries on', () async {
    final s = _Spotify();
    final sys = _System(s);
    final c = make(s, sys);
    expect(await c.playOnSpotifyDevice('phone'), isTrue);
    expect(sys.opened, 1);
    expect(s.transfers.length, greaterThanOrEqualTo(2)); // failed, then worked
    expect(c.musicError, isNull);
  });

  test(
    'another device that is not awake gets a clear message and nothing is opened',
    () async {
      final s = _Spotify();
      final sys = _System(s);
      final c = make(s, sys);
      expect(await c.playOnSpotifyDevice('mac'), isFalse);
      expect(sys.opened, 0); // it cannot wake a Mac from here
      expect(c.musicError, contains('not open on that device'));
    },
  );

  test('without the Spotify app installed it says so', () async {
    final s = _Spotify();
    final sys = _System(s, installed: false);
    final c = make(s, sys);
    expect(await c.playOnSpotifyDevice('phone'), isFalse);
    expect(sys.opened, 1);
    expect(c.musicError, contains('not installed'));
  });

  test('a device that already works plays at once', () async {
    final s = _Spotify()..awake = true;
    final sys = _System(s);
    final c = make(s, sys);
    expect(await c.playOnSpotifyDevice('phone'), isTrue);
    expect(sys.opened, 0);
    expect(s.transfers, ['phone']);
  });
}
