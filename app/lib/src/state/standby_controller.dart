import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/burn_in_protection.dart';
import '../core/clock_cadence.dart';
import '../data/settings_repository.dart';
import '../domain/standby_models.dart';
import '../services/spotify_service.dart';
import '../services/standby_system_service.dart';
import '../services/weather_service.dart';

class StandbyController extends ChangeNotifier with WidgetsBindingObserver {
  StandbyController({
    StandbySettings? initialSettings,
    IntegrationSnapshotBundle? snapshots,
    SettingsRepository? settingsRepository,
    StandbySystemService? systemService,
    SpotifyService? spotifyService,
    WeatherService? weatherService,
    bool autostartTicker = true,
  }) : settings = initialSettings ?? const StandbySettings(),
       snapshots =
           snapshots ?? IntegrationSnapshotBundle.fallback(now: DateTime.now()),
       _settingsRepository = settingsRepository,
       _systemService = systemService ?? StandbySystemService(),
       _spotify = spotifyService ?? SpotifyService(),
       _weatherService = weatherService ?? WeatherService(),
       _autostartTicker = autostartTicker,
       now = DateTime.now();

  StandbySettings settings;
  IntegrationSnapshotBundle snapshots;
  DateTime now;
  bool appVisible = true;
  int burnInTick = 0;
  DateTime? _lastShift = DateTime.now(); // when the burn-in shift last moved
  bool weatherIsLive = false;

  final SettingsRepository? _settingsRepository;
  final StandbySystemService _systemService;
  final WeatherService _weatherService;
  final SpotifyService _spotify;
  final bool _autostartTicker;
  Timer? _timer;
  Timer? _musicTimer;
  String? musicError;

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    final repository =
        _settingsRepository ??
        SettingsRepository(await SharedPreferences.getInstance());
    settings = await repository.load();
    await _applySystemSettings();
    unawaited(refreshWeather());
    await _spotify.load();
    _spotify.phoneName = await _systemService.deviceModel();
    if (_autostartTicker) {
      _scheduleNextTick();
      unawaited(refreshMusic());
    }
    notifyListeners();
  }

  void initializeForTest() {
    if (_autostartTicker) _scheduleNextTick();
  }

  /// Why weather is not shown (null when live data is available).
  WeatherProblem? weatherProblem;
  Timer? _weatherTimer;

  // Weather needs the phone's location; so does the World clock, which names
  // this phone's city next to its time.
  bool get _weatherOnScreen =>
      settings.leftWidget == StandbyWidgetType.weather ||
      (settings.layoutMode == StandbyLayoutMode.duo &&
          settings.rightWidget == StandbyWidgetType.weather) ||
      (settings.clockStyle == ClockStyle.world &&
          (settings.leftWidget == StandbyWidgetType.clock ||
              (settings.layoutMode == StandbyLayoutMode.duo &&
                  settings.rightWidget == StandbyWidgetType.clock)));

  // Battery: fetch only while a weather card is visible, then every 30 min.
  Future<void> refreshWeather() async {
    _weatherTimer?.cancel();
    if (_weatherOnScreen && appVisible) {
      try {
        final weather = await _weatherService.fetchForPhone();
        snapshots = IntegrationSnapshotBundle(
          weather: weather,
          nowPlaying: snapshots.nowPlaying,
        );
        weatherIsLive = true;
        weatherProblem = null;
        // remember the city so the World clock can name it right away
        if (weather.city != 'Current location' &&
            weather.city != settings.localCity) {
          unawaited(updateSettings(settings.copyWith(localCity: weather.city)));
        }
      } on WeatherException catch (e) {
        weatherIsLive = false;
        weatherProblem = e.problem;
      } catch (_) {
        weatherIsLive = false;
        weatherProblem = WeatherProblem.offline;
      }
      notifyListeners();
    }
    if (_autostartTicker) {
      // retry sooner after a failure so granting permission shows up quickly
      _weatherTimer = Timer(
        Duration(minutes: weatherIsLive ? 30 : 2),
        () => unawaited(refreshWeather()),
      );
    }
  }

  Future<void> updateSettings(StandbySettings value) async {
    settings = value;
    // The pending tick was planned for the old settings (e.g. a 60 s wait for a
    // style without seconds). Re-plan it now, or seconds would sit frozen.
    now = DateTime.now();
    if (_autostartTicker) _scheduleNextTick();
    notifyListeners(); // update the screen first so changes preview live
    final preferences = await SharedPreferences.getInstance();
    await SettingsRepository(preferences).save(value);
    await _applySystemSettings();
    if (_autostartTicker) {
      unawaited(refreshMusic());
      if (_weatherOnScreen && !weatherIsLive) unawaited(refreshWeather());
    }
  }

  // ponytail: not saved, so after an app restart the cards stay as they are
  bool _soloWasSecond = false;

  /// [soloSecond]: going to one panel, keep the second (right/bottom) one; it
  /// shows in the left slot meanwhile and goes back to its place on two panels.
  void setLayout(StandbyLayoutMode mode, {bool soloSecond = false}) {
    if (mode == settings.layoutMode) return;
    final single = mode == StandbyLayoutMode.single;
    final swap = single ? soloSecond : _soloWasSecond;
    _soloWasSecond = single && soloSecond;
    unawaited(
      updateSettings(
        settings.copyWith(
          layoutMode: mode,
          leftWidget: swap ? settings.rightWidget : null,
          rightWidget: swap ? settings.leftWidget : null,
        ),
      ),
    );
  }

  void toggleLayout() {
    final next = settings.layoutMode == StandbyLayoutMode.duo
        ? StandbyLayoutMode.single
        : StandbyLayoutMode.duo;
    unawaited(updateSettings(settings.copyWith(layoutMode: next)));
  }

  void cycleTheme() {
    final index = standbyThemes.indexWhere(
      (theme) => theme.id == settings.activeThemeId,
    );
    final next = standbyThemes[(index + 1) % standbyThemes.length];
    unawaited(updateSettings(settings.copyWith(activeThemeId: next.id)));
  }

  void cycleClockStyle([int step = 1]) {
    final styles = ClockStyle.values;
    final next = styles[(settings.clockStyle.index + step) % styles.length];
    unawaited(updateSettings(settings.copyWith(clockStyle: next)));
  }

  void toggleCalendarStyle() {
    final next = settings.calendarStyle == CalendarStyle.day
        ? CalendarStyle.month
        : CalendarStyle.day;
    unawaited(updateSettings(settings.copyWith(calendarStyle: next)));
  }

  /// Swipe a panel sideways to flip it to the next/previous widget.
  /// Skips the widget already shown in the other panel.
  void cyclePanelWidget({required bool left, required int step}) {
    const all = StandbyWidgetType.values;
    final current = left ? settings.leftWidget : settings.rightWidget;
    final other = left ? settings.rightWidget : settings.leftWidget;
    final duo = settings.layoutMode == StandbyLayoutMode.duo;
    var next = current;
    for (var i = 0; i < all.length; i++) {
      next = all[(next.index + step) % all.length];
      if (!duo || next != other) break;
    }
    unawaited(
      updateSettings(
        left
            ? settings.copyWith(leftWidget: next)
            : settings.copyWith(rightWidget: next),
      ),
    );
  }

  // Music: Spotify Web API when connected and playing anywhere (e.g. a Mac),
  // otherwise the Android media session of this phone.
  bool get spotifyConfigured => _spotify.isConfigured;
  bool get spotifyConnected => _spotify.isConnected;
  Future<List<SpotifyPlaylist>> spotifyPlaylists() => _spotify.playlists();
  Future<List<SpotifyDevice>> spotifyDevices() => _spotify.devices();

  Future<bool> playSpotifyPlaylist(String uri, {String? deviceId}) async {
    final ok = await _spotify.playPlaylist(uri, deviceId: deviceId);
    musicError = ok ? null : _spotify.lastError;
    if (ok) _refreshSoon();
    return ok;
  }

  Future<List<SpotifyHit>> searchSpotify(String query) async {
    final hits = await _spotify.search(query);
    musicError = _spotify.lastError;
    return hits;
  }

  Future<SpotifyQueue?> spotifyQueue() async {
    final q = await _spotify.queue();
    musicError = _spotify.lastError;
    return q;
  }

  /// Jump to the song [index] places down the queue (0 = the next one).
  Future<bool> skipInQueue(int index) async {
    final ok = await _spotify.skipNext(index + 1);
    musicError = ok ? null : _spotify.lastError;
    if (ok) _refreshSoon();
    return ok;
  }

  Future<bool> playSpotifyUri(String uri) async {
    final ok = await _spotify.playUri(uri);
    musicError = ok ? null : _spotify.lastError;
    if (ok) _refreshSoon();
    return ok;
  }

  Future<bool> queueSpotifyUri(String uri) async {
    final ok = await _spotify.addToQueue(uri);
    musicError = ok ? null : _spotify.lastError;
    return ok;
  }

  Future<bool> setSpotifyVolume(String deviceId, int percent) async {
    final ok = await _spotify.setVolume(percent, deviceId);
    musicError = ok ? null : _spotify.lastError;
    return ok;
  }

  Future<bool> playOnSpotifyDevice(String deviceId) async {
    final ok = await _spotify.transferTo(deviceId);
    musicError = ok ? null : _spotify.lastError;
    if (ok) _refreshSoon();
    return ok;
  }

  Future<List<({String package, String app})>> mediaPlayers() =>
      _systemService.mediaPlayers();

  Future<bool> openSpotifyApp() =>
      _systemService.launchApp('com.spotify.music');
  Future<bool> hasNotificationAccess() =>
      _systemService.hasNotificationAccess();
  Future<bool> openNotificationAccess() =>
      _systemService.openNotificationAccessSettings();

  Future<bool> connectSpotify() async {
    final ok = await _spotify.connect();
    notifyListeners();
    if (ok) unawaited(refreshMusic());
    return ok;
  }

  Future<void> disconnectSpotify() async {
    await _spotify.disconnect();
    notifyListeners();
  }

  bool get _musicOnScreen =>
      settings.leftWidget == StandbyWidgetType.music ||
      (settings.layoutMode == StandbyLayoutMode.duo &&
          settings.rightWidget == StandbyWidgetType.music);

  // Battery: only poll while a music widget is on screen and the app is
  // visible; poll slowly when nothing is playing.
  // After a command Spotify needs a moment to catch up: look twice, soon.
  void _refreshSoon() {
    unawaited(Future.delayed(const Duration(milliseconds: 400), refreshMusic));
    unawaited(Future.delayed(const Duration(milliseconds: 1200), refreshMusic));
  }

  int _idlePolls = 0; // consecutive times Spotify said "nothing is playing"

  Future<void> refreshMusic() async {
    _musicTimer?.cancel();
    final started = DateTime.now();
    try {
      if (_musicOnScreen && appVisible) {
        // musicSource: 'auto' = Spotify account if playing, else this phone;
        // 'spotify' = account only; anything else = that phone app only.
        final src = settings.musicSource;
        final fromSpotify = src == 'auto' || src == 'spotify';
        final fromPhone = src != 'spotify';
        // a read that hangs must not stop the polling, so each one has a limit
        final playing =
            (fromSpotify && _spotify.isConnected
                ? await _spotify.nowPlaying().timeout(
                    const Duration(seconds: 10),
                    onTimeout: () => null,
                  )
                : null) ??
            (fromPhone
                ? await _systemService.nowPlaying().timeout(
                    const Duration(seconds: 10),
                    onTimeout: () => null,
                  )
                : null);
        if (playing != null) {
          _idlePolls = 0;
          snapshots = IntegrationSnapshotBundle(
            weather: snapshots.weather,
            nowPlaying: playing,
          );
          notifyListeners();
        } else if (fromSpotify && _spotify.isConnected && _spotify.playerIdle) {
          // Spotify says nothing is playing anywhere. Do not keep showing the
          // last song as if it still played; wait for two answers in a row so
          // the moment between songs or devices does not flash "nothing".
          if (++_idlePolls >= 2 && snapshots.nowPlaying.viaSpotifyApi) {
            snapshots = IntegrationSnapshotBundle(
              weather: snapshots.weather,
              nowPlaying: IntegrationSnapshotBundle.fallback(
                now: DateTime.now(),
              ).nowPlaying,
            );
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint(
        'music refresh failed: $e',
      ); // never let one failure end polling
    } finally {
      if (_autostartTicker) _scheduleMusicPoll(started);
    }
  }

  void _scheduleMusicPoll(DateTime started) {
    _musicTimer?.cancel();
    final np = snapshots.nowPlaying;
    // On screen: look every 1 s while playing (so a song changed on another
    // device shows up fast) and every 5 s when nothing plays. Spotify has no
    // push, so polling is the only way; 429 answers are honored in the service.
    var wait = !_musicOnScreen
        ? const Duration(seconds: 30)
        : (np.isPlaying
              ? const Duration(milliseconds: 1000)
              : const Duration(seconds: 4));
    // Spotify told us to slow down recently: back off for a couple of minutes
    final slowedDown =
        DateTime.now().difference(_spotify.lastRateLimitedAt) <
        const Duration(minutes: 2);
    if (slowedDown && wait < const Duration(seconds: 3)) {
      wait = const Duration(seconds: 3);
    }
    if (_musicOnScreen && np.isPlaying && np.durationMs > 0) {
      // when the song should end, look right then: natural song changes are instant
      final left = np.durationMs - np.positionAt(DateTime.now());
      final atEnd = Duration(milliseconds: left + 400);
      if (left > 0 && atEnd < wait) {
        wait = atEnd < const Duration(milliseconds: 300)
            ? const Duration(milliseconds: 300)
            : atEnd;
      }
    }
    // count the wait from when the last look STARTED, so the time the request
    // itself took does not add to the delay
    final remaining = wait - DateTime.now().difference(started);
    _musicTimer = Timer(
      remaining < const Duration(milliseconds: 150)
          ? const Duration(milliseconds: 150)
          : remaining,
      () => unawaited(refreshMusic()),
    );
  }

  /// Jump to [ms] in the song (press-and-hold on the progress bar).
  Future<bool> seekToMs(int ms) async {
    final now = snapshots.nowPlaying;
    final target = now.durationMs > 0 ? ms.clamp(0, now.durationMs) : ms;
    // show the new position immediately; the real one arrives on the next poll
    snapshots = IntegrationSnapshotBundle(
      weather: snapshots.weather,
      nowPlaying: now.withPosition(target),
    );
    notifyListeners();
    final ok = now.viaSpotifyApi
        ? await _spotify.seekTo(target)
        : await _systemService.seekTo(target);
    musicError = ok
        ? null
        : (now.viaSpotifyApi
              ? _spotify.lastError
              : 'Grant Notification access in Music sources');
    unawaited(Future.delayed(const Duration(milliseconds: 450), refreshMusic));
    return ok;
  }

  /// Commands: playPause, next, previous, back10, forward10.
  Future<bool> sendMediaCommand(String command) async {
    final now = snapshots.nowPlaying;
    final bool ok;
    if (now.viaSpotifyApi) {
      ok = await _spotify.command(
        command,
        isPlaying: now.isPlaying,
        positionMs: now.positionMs,
        durationMs: now.durationMs,
      );
      musicError = ok ? null : _spotify.lastError;
    } else if (command == 'back10' || command == 'forward10') {
      ok = await _systemService.seekBy(command == 'back10' ? -10000 : 10000);
      musicError = ok ? null : 'Grant Notification access in Music sources';
    } else {
      ok = await _systemService.mediaCommand(command);
      musicError = ok ? null : 'Could not control the player';
    }
    unawaited(Future.delayed(const Duration(milliseconds: 700), refreshMusic));
    return ok;
  }

  // Auto-start settings last sent to the Android watcher (only re-sent on change).
  (bool, double, bool, bool)? _autoSent;

  Future<AutoStartStatus> autoStartStatus() => _systemService.autoStartStatus();
  Future<bool> openOverlaySettings() => _systemService.openOverlaySettings();
  Future<bool> openBatterySettings() => _systemService.openBatterySettings();
  Future<bool> requestNotifications() => _systemService.requestNotifications();
  Future<bool> postureProbe(bool on) => _systemService.postureProbe(on);
  Future<PostureNow?> postureNow() => _systemService.postureNow(
    leanDeg: settings.autoLeanDeg,
    landscapeOnly: settings.autoLandscapeOnly,
  );

  Future<void> _applySystemSettings() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await _systemService.setKeepAwake(settings.keepAwakeWhileCharging);
    await _systemService.setBrightness(settings.brightness);
    final auto = (
      settings.autoStart,
      settings.autoLeanDeg,
      settings.autoLandscapeOnly,
      settings.autoExitOnUnplug,
    );
    if (auto != _autoSent) {
      _autoSent = auto;
      await _systemService.configureAutoStart(
        enabled: auto.$1,
        leanDeg: auto.$2,
        landscapeOnly: auto.$3,
        exitOnUnplug: auto.$4,
      );
    }
    final src = settings.musicSource;
    await _systemService.setPreferredPlayer(
      src == 'auto' || src == 'spotify' ? '' : src,
    );
  }

  void _scheduleNextTick() {
    _timer?.cancel();
    _timer = Timer(
      ClockCadence.nextDelay(now, settings, appVisible: appVisible),
      () {
        now = DateTime.now();
        // the burn-in shift moves once a minute, even if the clock ticks
        // every second (otherwise the whole screen jumps each second)
        if (BurnInProtection.shouldAdvance(_lastShift, now)) {
          burnInTick += 1;
          _lastShift = now;
        }
        notifyListeners();
        _scheduleNextTick();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appVisible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _scheduleNextTick();
    if (appVisible && _autostartTicker) {
      unawaited(refreshMusic());
      unawaited(refreshWeather());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _musicTimer?.cancel();
    _weatherTimer?.cancel();
    super.dispose();
  }
}
