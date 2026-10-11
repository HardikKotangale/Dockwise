import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/burn_in_protection.dart';
import '../core/clock_cadence.dart';
import '../core/room_light.dart';
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
      // look at the room light every couple of seconds while the app is on screen
      _lightTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (appVisible) unawaited(pollLight());
      });
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
  // is [t] one of the panels on screen right now?
  bool _showing(StandbyWidgetType t) =>
      settings.leftWidget == t ||
      (settings.layoutMode == StandbyLayoutMode.duo &&
          settings.rightWidget == t);

  bool get _weatherOnScreen =>
      _showing(StandbyWidgetType.weather) ||
      _showing(StandbyWidgetType.summary) ||
      (settings.clockStyle == ClockStyle.world &&
          (settings.leftWidget == StandbyWidgetType.clock ||
              (settings.layoutMode == StandbyLayoutMode.duo &&
                  settings.rightWidget == StandbyWidgetType.clock)));

  /// The weather card's pages, swiped up and down: 0 now, 1 the temperature
  /// in Fahrenheit alone, 2 the forecast, 3 the second city.
  int weatherPage = 0;
  static const weatherPages = 4;
  static const secondCityPage = 3;

  /// Weather in the second city (page 2), once fetched.
  WeatherSnapshot? secondWeather;
  bool secondWeatherFailed = false;
  String _secondWeatherFor = ''; // which city [secondWeather] belongs to

  void cycleWeatherPage(int step) {
    weatherPage = (weatherPage + step) % weatherPages;
    if (weatherPage < 0) weatherPage += weatherPages;
    notifyListeners();
    if (weatherPage == secondCityPage) unawaited(refreshSecondWeather());
  }

  /// The second city's weather: only fetched when that page is wanted.
  Future<void> refreshSecondWeather() async {
    final s = settings;
    if (s.worldZone.isEmpty || (s.worldLat == 0 && s.worldLon == 0)) {
      secondWeather = null;
      secondWeatherFailed = false;
      notifyListeners();
      return;
    }
    final key = '${s.worldZone}|${s.worldLat}|${s.worldLon}';
    if (_secondWeatherFor != key) secondWeather = null; // a different city
    try {
      final city = s.worldCity.isNotEmpty ? s.worldCity : s.worldZone;
      secondWeather = await _weatherService.fetchForCity(
        city: city,
        latitude: s.worldLat,
        longitude: s.worldLon,
      );
      _secondWeatherFor = key;
      secondWeatherFailed = false;
    } catch (_) {
      secondWeatherFailed = true;
    }
    notifyListeners();
  }

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
      if (weatherPage == secondCityPage &&
          _showing(StandbyWidgetType.weather)) {
        unawaited(refreshSecondWeather());
      }
    }
    if (_autostartTicker) {
      // retry sooner after a failure so granting permission shows up quickly
      _weatherTimer = Timer(
        Duration(minutes: weatherIsLive ? 30 : 2),
        () => unawaited(refreshWeather()),
      );
    }
  }

  /// With two panels there is no Summary: whichever panel had it goes back to
  /// what it showed before.
  StandbySettings _noSummaryInDuo(StandbySettings v) {
    if (v.layoutMode != StandbyLayoutMode.duo) return v;
    if (v.leftWidget != StandbyWidgetType.summary &&
        v.rightWidget != StandbyWidgetType.summary) {
      return v;
    }
    final l = v.leftWidget == StandbyWidgetType.summary
        ? (_beforeSummaryLeft ?? StandbyWidgetType.clock)
        : v.leftWidget;
    var r = v.rightWidget == StandbyWidgetType.summary
        ? (_beforeSummaryRight ?? StandbyWidgetType.weather)
        : v.rightWidget;
    if (l == r) {
      r = l == StandbyWidgetType.clock
          ? StandbyWidgetType.weather
          : StandbyWidgetType.clock;
    }
    return v.copyWith(leftWidget: l, rightWidget: r);
  }

  Future<void> updateSettings(StandbySettings value) async {
    value = _noSummaryInDuo(value);
    final cityChanged =
        value.worldZone != settings.worldZone ||
        value.worldLat != settings.worldLat ||
        value.worldLon != settings.worldLon;
    settings = value;
    // the second city changed while its weather is on screen: fetch it now
    if (cityChanged && weatherPage == secondCityPage) {
      unawaited(refreshSecondWeather());
    }
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

  void cycleClockStyle([int step = 1]) {
    const styles = ClockStyle.values;
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
  // what each panel showed before a three-finger swipe sent it to Summary
  StandbyWidgetType? _beforeSummaryLeft;
  StandbyWidgetType? _beforeSummaryRight;

  /// Three-finger swipe: this panel jumps to Summary; swipe again to go back
  /// to what it showed before.
  void toggleSummary({required bool left}) {
    final current = left ? settings.leftWidget : settings.rightWidget;
    final other = left ? settings.rightWidget : settings.leftWidget;
    final duo = settings.layoutMode == StandbyLayoutMode.duo;
    if (duo) return; // Summary fills the screen: one panel only
    StandbyWidgetType next;
    if (current == StandbyWidgetType.summary) {
      next =
          (left ? _beforeSummaryLeft : _beforeSummaryRight) ??
          StandbyWidgetType.clock;
      if (duo && next == other) next = StandbyWidgetType.clock;
      if (duo && next == other) next = StandbyWidgetType.weather;
    } else {
      if (duo && other == StandbyWidgetType.summary) return; // already shown
      if (left) {
        _beforeSummaryLeft = current;
      } else {
        _beforeSummaryRight = current;
      }
      next = StandbyWidgetType.summary;
    }
    unawaited(
      updateSettings(
        left
            ? settings.copyWith(leftWidget: next)
            : settings.copyWith(rightWidget: next),
      ),
    );
  }

  void cyclePanelWidget({required bool left, required int step}) {
    final duo = settings.layoutMode == StandbyLayoutMode.duo;
    // Summary is a whole-screen panel: it is only offered with one panel
    final all = [
      for (final t in StandbyWidgetType.values)
        if (!duo || t != StandbyWidgetType.summary) t,
    ];
    final current = left ? settings.leftWidget : settings.rightWidget;
    final other = left ? settings.rightWidget : settings.leftWidget;
    var next = current;
    for (var i = 0; i < all.length; i++) {
      final at = all.indexOf(next);
      next = all[((at < 0 ? 0 : at) + step) % all.length];
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

  /// The last device list Spotify gave us, so the volume bar can show at once.
  List<SpotifyDevice> lastSpotifyDevices = const [];
  Future<List<SpotifyDevice>> spotifyDevices() async {
    final list = await _spotify.devices();
    lastSpotifyDevices = list;
    return list;
  }

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

  /// Where the music card gets its song: 'auto', 'spotify' or a phone app.
  Future<void> setMusicSource(String source) {
    snapshots = IntegrationSnapshotBundle(
      weather: snapshots.weather,
      nowPlaying: IntegrationSnapshotBundle.fallback(
        now: DateTime.now(),
      ).nowPlaying,
    );
    return updateSettings(settings.copyWith(musicSource: source));
  }

  bool get _musicOnScreen =>
      _showing(StandbyWidgetType.music) || _showing(StandbyWidgetType.summary);

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

  // OLED care: with nobody touching the screen, dim it to about half. A bright
  // static clock is what wears an OLED, so this matters even in daylight.
  DateTime lastTouch = DateTime.now();

  bool get idle =>
      settings.idleDimMinutes > 0 &&
      DateTime.now().difference(lastTouch) >=
          Duration(minutes: settings.idleDimMinutes);

  /// Any touch wakes the screen from its idle dim.
  void touched() {
    final wasIdle = idle;
    lastTouch = DateTime.now();
    if (wasIdle) notifyListeners();
  }

  // Room light (Android): the screen follows it, and a dark room switches the
  // night look on. iPhone gives apps no light sensor, so there the controller
  // leaves brightness alone and iOS's own auto-brightness does the adapting.
  Timer? _lightTimer;
  double?
  _luxLog; // smoothed log10(lux + 1), so a passing shadow does not flicker
  double _lastBrightness = -1;
  bool roomDark = false;

  Future<void> pollLight() async {
    if (!settings.autoBrightness) return;
    final lux = await _systemService.ambientLux();
    if (lux == null) return; // no readable light sensor on this device
    final l = math.log(lux.clamp(0, 100000) + 1) / math.ln10;
    _luxLog = _luxLog == null ? l : _luxLog! + 0.4 * (l - _luxLog!);
    final smooth = math.pow(10, _luxLog!).toDouble() - 1;
    final target = roomBrightness(smooth, settings.brightness);
    if ((target - _lastBrightness).abs() > 0.03) {
      _lastBrightness = target;
      await _systemService.setBrightness(target);
    }
    final dark = isDarkRoom(smooth, wasDark: roomDark);
    if (dark != roomDark) {
      roomDark = dark;
      notifyListeners();
    }
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

  bool _orientationsSet = false;

  Future<void> _applySystemSettings() async {
    // Only once: this runs on every settings change (a clock style swipe...), and
    // setting the orientations again would undo a rotation made with the rotate
    // symbol while the phone's rotation is locked.
    if (!_orientationsSet) {
      _orientationsSet = true;
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await _systemService.setKeepAwake(settings.keepAwakeWhileCharging);
    if (settings.autoBrightness) {
      _lastBrightness = -1; // the next light reading applies it afresh
      unawaited(pollLight());
    } else {
      await _systemService.setBrightness(settings.brightness);
      roomDark = false;
    }
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
    _lightTimer?.cancel();
    super.dispose();
  }
}
