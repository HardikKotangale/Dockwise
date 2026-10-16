import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/burn_in_protection.dart';
import '../core/clock_cadence.dart';
import '../core/night_mode_policy.dart';
import '../core/room_light.dart';
import '../data/settings_repository.dart';
import '../domain/standby_models.dart';
import '../domain/summary_layout.dart';
import '../services/calendar_service.dart';
import '../services/photo_service.dart';
import '../services/spotify_service.dart';
import '../services/standby_system_service.dart';
import '../services/weather_service.dart';

/// Which of Spotify's devices is the one Hushdock runs on: a Smartphone on a
/// phone, a Computer on a PC, whose name contains this device's [name] (its
/// model, or the PC's name). A PC with a single Computer listed is that one,
/// even under another name (the Spotify app may be named differently).
SpotifyDevice? thisSpotifyDevice(
  List<SpotifyDevice> devices, {
  required String name,
  required bool computer,
}) {
  final type = computer ? 'Computer' : 'Smartphone';
  final mine = devices.where((d) => d.type == type).toList();
  final n = name.toLowerCase();
  for (final d in mine) {
    if (n.isEmpty || d.name.toLowerCase().contains(n)) return d;
  }
  return computer && mine.length == 1 ? mine.single : null;
}

class StandbyController extends ChangeNotifier with WidgetsBindingObserver {
  StandbyController({
    StandbySettings? initialSettings,
    IntegrationSnapshotBundle? snapshots,
    SettingsRepository? settingsRepository,
    StandbySystemService? systemService,
    SpotifyService? spotifyService,
    WeatherService? weatherService,
    CalendarService? calendarService,
    PhotoService? photoService,
    bool autostartTicker = true,
    Duration spotifyRetryDelay = const Duration(seconds: 2),
  }) : settings = initialSettings ?? const StandbySettings(),
       snapshots =
           snapshots ?? IntegrationSnapshotBundle.fallback(now: DateTime.now()),
       _settingsRepository = settingsRepository,
       _systemService = systemService ?? StandbySystemService(),
       _spotify = spotifyService ?? SpotifyService(),
       _weatherService = weatherService ?? WeatherService(),
       _calendar = calendarService ?? CalendarService(),
       _photos = photoService ?? PhotoService(),
       _autostartTicker = autostartTicker,
       _spotifyRetryDelay = spotifyRetryDelay,
       now = DateTime.now();

  StandbySettings settings;
  IntegrationSnapshotBundle snapshots;
  DateTime now;
  bool appVisible = true;
  int burnInTick = 0;

  /// True while the notification is only the clock ticking or the song moving
  /// on, so a panel that does not show either (the settings) can skip it.
  bool backgroundNotify = false;

  void _notifyBackground() {
    backgroundNotify = true;
    try {
      notifyListeners();
    } finally {
      backgroundNotify = false;
    }
  }

  DateTime? _lastShift = DateTime.now(); // when the burn-in shift last moved
  bool weatherIsLive = false;

  final SettingsRepository? _settingsRepository;
  final StandbySystemService _systemService;
  final WeatherService _weatherService;
  final SpotifyService _spotify;
  final CalendarService _calendar;
  final PhotoService _photos;
  final bool _autostartTicker;
  final Duration _spotifyRetryDelay;
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
      unawaited(refreshMeetings());
      unawaited(rebuildPhotoFeed());
      _meetingTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (appVisible) unawaited(refreshMeetings());
      });
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
  /// true while the weather is being fetched (the card's refresh button spins)
  bool weatherRefreshing = false;

  Future<void> refreshWeather() async {
    _weatherTimer?.cancel();
    if (_weatherOnScreen && appVisible) {
      weatherRefreshing = true;
      notifyListeners();
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
      weatherRefreshing = false;
      notifyListeners();
      if (weatherPage == secondCityPage &&
          _showing(StandbyWidgetType.weather)) {
        unawaited(refreshSecondWeather());
      }
    }
    if (_autostartTicker) {
      // retry sooner after a failure so granting permission shows up quickly
      _weatherTimer = Timer(
        Duration(minutes: weatherIsLive ? 15 : 2),
        () => unawaited(refreshWeather()),
      );
    }
  }

  /// With two panels there is no Summary: the left panel goes back to the
  /// clock, the right one to the weather.
  StandbySettings _noSummaryInDuo(StandbySettings v) {
    if (v.layoutMode != StandbyLayoutMode.duo) return v;
    if (v.leftWidget != StandbyWidgetType.summary &&
        v.rightWidget != StandbyWidgetType.summary) {
      return v;
    }
    final l = v.leftWidget == StandbyWidgetType.summary
        ? StandbyWidgetType.clock
        : v.leftWidget;
    var r = v.rightWidget == StandbyWidgetType.summary
        ? StandbyWidgetType.weather
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
    final previous = settings;
    settings = value;
    // the second city changed while its weather is on screen: fetch it now
    if (cityChanged && weatherPage == secondCityPage) {
      unawaited(refreshSecondWeather());
    }
    // The pending tick was planned for the old settings (e.g. a 60 s wait for a
    // style without seconds). Re-plan it now, or seconds would sit frozen.
    now = DateTime.now();
    if (_autostartTicker) _scheduleNextTick();
    final meetingsChanged =
        value.calendarStyle != previous.calendarStyle ||
        value.calendarTitles != previous.calendarTitles ||
        value.leftWidget != previous.leftWidget ||
        value.rightWidget != previous.rightWidget;
    if (meetingsChanged) unawaited(refreshMeetings());
    final photosChanged =
        value.photoSource != previous.photoSource ||
        value.photoAlbumId != previous.photoAlbumId ||
        value.photoFolder != previous.photoFolder ||
        value.leftWidget != previous.leftWidget ||
        value.rightWidget != previous.rightWidget ||
        value.layoutMode != previous.layoutMode ||
        value.summaryLayout != previous.summaryLayout;
    if (photosChanged) unawaited(rebuildPhotoFeed());
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

  /// F11 on Windows: borderless over the whole monitor, or back to a window.
  void toggleFullscreen() => unawaited(
    updateSettings(settings.copyWith(fullscreen: !settings.fullscreen)),
  );

  // N on the keyboard flips the night look now; it lasts until the schedule
  // (or the room light) next changes its mind, so it never sticks for good
  bool? _nightForced;
  bool _nightForcedAgainst = false;

  /// Whether the night look is on right now.
  bool get nightNow {
    final scheduled = NightModePolicy.shouldTint(now, settings, dark: roomDark);
    if (_nightForced != null && scheduled != _nightForcedAgainst) {
      _nightForced = null; // the schedule moved on: follow it again
    }
    return _nightForced ?? scheduled;
  }

  void toggleNight() {
    final on = nightNow;
    _nightForcedAgainst = NightModePolicy.shouldTint(
      now,
      settings,
      dark: roomDark,
    );
    _nightForced = !on;
    notifyListeners();
  }

  /// A music key was pressed: (the command, a counter). The music card pulses
  /// that control, wherever the card is (the Music panel or a Summary tile).
  final mediaKey = ValueNotifier<(String, int)>(('', 0));

  void flashMediaKey(String command) =>
      mediaKey.value = (command, mediaKey.value.$2 + 1);

  /// A music key: the button pulses and the command goes out.
  void keyMedia(String command) {
    flashMediaKey(command);
    unawaited(sendMediaCommand(command));
  }

  /// The volume keys: the volume bar opens once the new level is set.
  Future<void> keyVolume(int delta) async {
    if (await nudgeVolume(delta)) {
      flashMediaKey(delta > 0 ? 'volumeUp' : 'volumeDown');
    }
  }

  /// Space on the keyboard: play/pause the music or start/pause the timer,
  /// whichever is on screen (the first panel wins). False when neither is.
  bool playPauseShown() {
    final shown = [
      settings.leftWidget,
      if (settings.layoutMode == StandbyLayoutMode.duo) settings.rightWidget,
    ];
    for (final t in shown) {
      if (t == StandbyWidgetType.summary) {
        // the Summary holds a music tile and/or a timer tile
        final tiles = SummaryLayout.parse(settings.summaryLayout).tiles;
        if (tiles.contains(SummaryTile.music)) {
          keyMedia('playPause');
          return true;
        }
        if (tiles.contains(SummaryTile.timer)) {
          timerRunning ? timerPause() : timerStart();
          return true;
        }
      }
      if (t == StandbyWidgetType.music) {
        keyMedia('playPause');
        return true;
      }
      if (t == StandbyWidgetType.timer) {
        timerRunning ? timerPause() : timerStart();
        return true;
      }
    }
    return false;
  }

  void cycleClockStyle([int step = 1]) {
    const styles = ClockStyle.values;
    final next = styles[(settings.clockStyle.index + step) % styles.length];
    unawaited(updateSettings(settings.copyWith(clockStyle: next)));
  }

  /// Frame, Flip, Analog for the two time tiles on the Summary panel. The
  /// second city has its own look once it is changed on its own tile.
  void cycleSummaryClockStyle([int step = 1, bool second = false]) {
    const styles = TileClockStyle.values;
    final from = second ? settings.thereStyle : settings.summaryClockStyle;
    final next = styles[(from.index + step) % styles.length];
    unawaited(
      updateSettings(
        second
            ? settings.copyWith(summaryThereStyle: next.index)
            : settings.copyWith(summaryClockStyle: next),
      ),
    );
  }

  /// Today -> Month -> Meetings -> Today
  void toggleCalendarStyle() {
    const all = CalendarStyle.values;
    final next = all[(settings.calendarStyle.index + 1) % all.length];
    unawaited(updateSettings(settings.copyWith(calendarStyle: next)));
  }

  // ---- the Calendar's Meetings tab ----------------------------------------
  // Read-only, from the system calendar, kept in memory only (see
  // CalendarService). Fetched only while that tab is on screen.
  CalendarAccess calendarAccess = CalendarAccess.unknown;
  List<Meeting> meetings = const [];
  Timer? _meetingTimer;

  bool get _meetingsOnScreen =>
      settings.calendarStyle == CalendarStyle.agenda &&
      (_showing(StandbyWidgetType.calendar) ||
          _showing(StandbyWidgetType.summary));

  Future<void> refreshMeetings() async {
    if (!_meetingsOnScreen) return;
    calendarAccess = await _calendar.status();
    meetings = calendarAccess == CalendarAccess.granted
        ? await _calendar.meetings(titles: settings.calendarTitles)
        : const [];
    notifyListeners();
  }

  /// The system asks once; the Meetings tab fills in when it is allowed.
  Future<void> connectCalendar() async {
    calendarAccess = await _calendar.request();
    notifyListeners();
    await refreshMeetings();
  }

  // ---- the photo slideshow -------------------------------------------------
  // The pictures are read one at a time from the album or folder you chose;
  // see PhotoService. The feed is only opened while a Photos card is on screen.
  PhotoFeed? photoFeed;
  PhotoAccess photoAccess = PhotoAccess.unknown;
  String? photoProblem;
  int _photoGeneration = 0;

  /// (direction, count): a key moved the slideshow one picture on or back
  final photoStep = ValueNotifier<(int, int)>((0, 0));

  void stepPhoto(int dir) => photoStep.value = (dir, photoStep.value.$2 + 1);

  bool get _photosOnScreen =>
      _showing(StandbyWidgetType.photos) ||
      (_showing(StandbyWidgetType.summary) &&
          SummaryLayout.parse(
            settings.summaryLayout,
          ).tiles.contains(SummaryTile.photos));

  Future<void> rebuildPhotoFeed() async {
    final generation = ++_photoGeneration;
    if (!_photosOnScreen || settings.photoSource == PhotoSource.none) {
      photoFeed = null;
      photoProblem = null;
      notifyListeners();
      return;
    }
    PhotoFeed? feed;
    String? problem;
    if (settings.photoSource == PhotoSource.library) {
      photoAccess = await _photos.libraryAccess();
      if (photoAccess == PhotoAccess.granted) {
        feed = settings.photoAlbumId.isEmpty
            ? null
            : await _photos.libraryFeed(settings.photoAlbumId);
        if (feed == null && settings.photoAlbumId.isNotEmpty) {
          problem = 'That album cannot be read';
        }
      } else if (photoAccess == PhotoAccess.denied) {
        problem =
            'Photos access is off. Allow it in System Settings > '
            'Privacy & Security > Photos.';
      }
    } else {
      feed = await _photos.folderFeed(
        settings.photoFolder,
        bookmark: settings.photoFolderBookmark,
      );
      if (feed == null) problem = 'That folder cannot be read';
    }
    if (generation != _photoGeneration) return; // a newer choice came in
    photoFeed = feed;
    photoProblem = problem;
    notifyListeners();
  }

  /// Photos album: the system asks once; the album's pictures then play.
  Future<bool> choosePhotoAlbum(PhotoAlbum album) async {
    photoAccess = await _photos.requestLibrary();
    if (photoAccess != PhotoAccess.granted) {
      notifyListeners();
      return false;
    }
    await updateSettings(
      settings.copyWith(
        photoSource: PhotoSource.library,
        photoAlbumId: album.id,
        photoAlbumName: album.name,
      ),
    );
    return true;
  }

  Future<List<PhotoAlbum>> photoAlbums() async {
    photoAccess = await _photos.requestLibrary();
    notifyListeners();
    return photoAccess == PhotoAccess.granted
        ? _photos.albums()
        : const <PhotoAlbum>[];
  }

  /// A folder: the system's own folder picker (a Mac keeps only the right to
  /// read that one folder).
  Future<bool> choosePhotoFolder() async {
    final picked = await _photos.pickFolder();
    if (picked == null) return false;
    await updateSettings(
      settings.copyWith(
        photoSource: PhotoSource.folder,
        photoFolder: picked.path,
        photoFolderBookmark: picked.bookmark,
      ),
    );
    return true;
  }

  /// Swipe a panel sideways to flip it to the next/previous widget.
  /// Skips the widget already shown in the other panel.
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
  bool get spotifyOwnClientId => _spotify.usingSavedClientId;
  String get spotifyClientIdMasked => _spotify.maskedClientId;
  Future<bool> saveSpotifyClientId(String raw) async {
    final ok = await _spotify.saveClientId(raw);
    notifyListeners();
    return ok;
  }

  Future<void> removeSpotifyClientId() async {
    await _spotify.removeClientId();
    notifyListeners();
  }

  Future<List<SpotifyPlaylist>> spotifyPlaylists() => _spotify.playlists();

  /// The last device list Spotify gave us, so the volume bar can show at once.
  List<SpotifyDevice> lastSpotifyDevices = const [];
  Future<List<SpotifyDevice>> spotifyDevices() async {
    final list = await _spotify.devices();
    lastSpotifyDevices = list;
    return list;
  }

  Future<bool> playSpotifyPlaylist(String uri, {String? deviceId}) async {
    // Liked Songs / Recently played are song lists: play the songs themselves
    final ok = uri.startsWith('hushdock:')
        ? await _spotify.playSongs([
            for (final h in await _spotify.playlistTracks(uri)) h.uri,
          ])
        : await _spotify.playPlaylist(uri, deviceId: deviceId);
    musicError = ok ? null : _spotify.lastError;
    if (ok) _refreshSoon();
    return ok;
  }

  Future<List<SpotifyHit>> spotifyPlaylistTracks(String uri) async {
    final tracks = await _spotify.playlistTracks(uri);
    musicError = _spotify.lastError;
    return tracks;
  }

  Future<bool> playPlaylistTrack(String playlist, String track) async {
    final ok = playlist.startsWith('hushdock:')
        ? await _spotify.playSongs([
            for (final h in await _spotify.playlistTracks(playlist)) h.uri,
          ], from: track)
        : await _spotify.playInPlaylist(playlist, track);
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
    // still the order you chose, until it has been played
    final next = _pendingNext;
    if (q != null && next != null && q.now?.title == _pendingNow?.title) {
      return SpotifyQueue(q.now, next);
    }
    return q;
  }

  // ---- Timer ----
  // Runs on this phone, in the app: [timerEndsAt] while counting down,
  // [_timerLeftMs] while paused or not started. When it reaches zero it rings
  // until you stop it.
  DateTime? timerEndsAt;
  int _timerLeftMs = -1; // -1: not started, use settings.timerSeconds
  bool timerDone = false;
  int _rings = 0;

  bool get timerRunning => timerEndsAt != null;
  // the length of this run, and every minute added to it since: the runner on
  // the track measures its progress against this
  int _runTotalMs = 0;
  int get timerTotalMs => timerStarted && _runTotalMs > 0
      ? _runTotalMs
      : settings.timerSeconds * 1000;

  int get timerLeftMs {
    if (timerDone) return 0;
    final end = timerEndsAt;
    if (end != null) {
      return math.max(0, end.difference(DateTime.now()).inMilliseconds);
    }
    return _timerLeftMs < 0 ? timerTotalMs : _timerLeftMs;
  }

  /// It was started and has not been reset (running, paused or ringing).
  bool get timerStarted => timerRunning || timerDone || _timerLeftMs >= 0;

  void timerStart() {
    if (timerDone) return timerReset();
    final left = timerLeftMs;
    if (left <= 0) return;
    if (_timerLeftMs < 0) _runTotalMs = left; // a fresh run, not a resume
    timerEndsAt = DateTime.now().add(Duration(milliseconds: left));
    _scheduleNextTick();
    notifyListeners();
  }

  void timerPause() {
    if (timerEndsAt == null) return;
    _timerLeftMs = timerLeftMs;
    timerEndsAt = null;
    notifyListeners();
  }

  void timerReset() {
    timerEndsAt = null;
    _timerLeftMs = -1;
    _runTotalMs = 0;
    timerDone = false;
    _rings = 0;
    notifyListeners();
  }

  /// More time: onto the clock that is counting, or onto the starting length.
  void timerAdd(Duration d) {
    if (timerDone) {
      timerDone = false;
      _rings = 0;
      _runTotalMs = d.inMilliseconds;
      timerEndsAt = DateTime.now().add(d);
    } else if (timerEndsAt != null) {
      timerEndsAt = timerEndsAt!.add(d);
      _runTotalMs += d.inMilliseconds;
    } else if (_timerLeftMs >= 0) {
      _timerLeftMs += d.inMilliseconds;
      _runTotalMs += d.inMilliseconds;
    } else {
      unawaited(
        updateSettings(
          settings.copyWith(timerSeconds: settings.timerSeconds + d.inSeconds),
        ),
      );
      return;
    }
    _scheduleNextTick();
    notifyListeners();
  }

  /// Sets the starting length (only before it is started).
  void timerSet(int seconds) {
    if (timerStarted) return;
    unawaited(updateSettings(settings.copyWith(timerSeconds: seconds)));
  }

  /// Plays the end sound (also for the Test button in the settings).
  void testTimerAlert() => unawaited(
    _systemService.timerAlert(
      sound: settings.timerSound,
      vibrate: settings.timerVibrate,
    ),
  );

  void toggleTimerStyle() => unawaited(
    updateSettings(
      settings.copyWith(
        timerStyle: settings.timerStyle == TimerStyle.digital
            ? TimerStyle.flip
            : TimerStyle.digital,
      ),
    ),
  );

  // called every tick: ring when the time is up
  void _checkTimer() {
    final end = timerEndsAt;
    if (end != null && !DateTime.now().isBefore(end)) {
      timerEndsAt = null;
      timerDone = true;
      _timerLeftMs = 0;
    }
    // the sound and buzz, now and every three seconds, until it is stopped
    if (timerDone) {
      if (_rings % 3 == 0) testTimerAlert();
      _rings++;
    }
  }

  // A new queue order waits here until the song ends: Spotify's Web API can
  // only change the queue by starting playback again, and doing that mid-song
  // is an audible stop. See _applyPendingQueue.
  SpotifyHit? _pendingNow;
  List<SpotifyHit>? _pendingNext;
  bool _applyingQueue = false;
  int _applyMs = 700; // how long starting playback took last time
  // Start the new order this much BEFORE the old song ends (its last moments
  // are cut), so the old next song can never begin: starting late means that
  // song plays for a moment, which is what you hear as "another song".
  static const _queueCutMs = 300;
  static const _resyncMs = 6000; // read the song fresh this long before the end

  bool get hasPendingQueue => _pendingNext != null;

  /// Remembers the order you chose; it takes effect at the end of this song.
  void reorderSpotifyQueue(SpotifyHit now, List<SpotifyHit> next) {
    _pendingNow = now;
    _pendingNext = next;
    _resynced = false;
    unawaited(_applyPendingQueue(snapshots.nowPlaying));
  }

  Timer? _queueTimer;
  bool _resynced = false; // the fresh read before the hand-over, once per order

  // How long the song has left, counting the time since it was read.
  int _msLeft(NowPlayingSnapshot n) {
    final age = n.fetchedAt == null
        ? 0
        : DateTime.now().difference(n.fetchedAt!).inMilliseconds;
    return n.durationMs - (n.positionMs + (n.isPlaying ? age : 0));
  }

  Future<bool> _timedApply(List<SpotifyHit> next) async {
    final t = Stopwatch()..start();
    final ok = await _spotify.reorderQueue(next.first, next.sublist(1), 0);
    // the new song starts about when the call is answered; aim to be there
    // as the old one ends, whatever this phone's connection is like
    if (ok) {
      final took = (_applyMs + t.elapsedMilliseconds) ~/ 2;
      _applyMs = took.clamp(200, 3000);
    }
    return ok;
  }

  /// Plays the new order without a stop in the middle of a song: when the song
  /// is about to end (or was skipped, or is paused) it starts from the new next
  /// song instead of the old one.
  Future<void> _applyPendingQueue(
    NowPlayingSnapshot n, {
    bool fresh = false,
  }) async {
    final next = _pendingNext;
    final was = _pendingNow;
    if (next == null || was == null || _applyingQueue || !n.viaSpotifyApi) {
      return;
    }
    final sameSong = n.title == was.title && n.artist == was.subtitle;
    // Starting playback takes a moment, so start it a little before the end;
    // a timer, not the 1 s poll, so the end is not missed and the old next
    // song never gets to start.
    // measured from the last time, so it lands as the song ends
    final lead = _applyMs + _queueCutMs;
    final left = _msLeft(n);
    // the last stretch: the song's position as we know it may be a second old,
    // so read it fresh once, then time the hand-over from that
    if (!fresh &&
        !_resynced &&
        sameSong &&
        n.isPlaying &&
        n.durationMs > 0 &&
        left > lead &&
        left <= lead + _resyncMs) {
      _resynced = true;
      final now = await _spotify.nowPlaying();
      if (now != null) return _applyPendingQueue(now, fresh: true);
    }
    if (sameSong && n.isPlaying && n.durationMs > 0 && left > lead) {
      _queueTimer?.cancel();
      _queueTimer = Timer(
        Duration(milliseconds: left - lead),
        () => _applyPendingQueue(snapshots.nowPlaying),
      );
      return;
    }
    _queueTimer?.cancel();
    _applyingQueue = true;
    try {
      _pendingNext = null;
      _pendingNow = null;
      if (next.isEmpty) return;
      final ok = sameSong && !n.isPlaying
          // paused: nothing to interrupt; keep the song and where it was
          ? await _spotify.reorderQueue(was, next, n.positionMs) &&
                await _spotify.command('playPause', isPlaying: true)
          : await _timedApply(next);
      musicError = ok ? null : _spotify.lastError;
      if (ok) _refreshSoon();
    } finally {
      _applyingQueue = false;
    }
  }

  /// Jump straight to the song [index] places down the queue (0 = the next
  /// one), without playing the ones between: start from that song, followed by
  /// the rest of [queue].
  Future<bool> skipInQueue(int index, List<SpotifyHit> queue) async {
    _queueTimer?.cancel();
    _pendingNext = null;
    _pendingNow = null;
    final ok = await _spotify.reorderQueue(
      queue[index],
      queue.sublist(index + 1),
      0,
    );
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

  // a device we asked to play on, but that was not awake yet (see below)
  String? _pendingDevice;

  /// Plays on [deviceId], carrying on with whatever was playing. If that is
  /// this device and Spotify is not awake here (it has to be running to be
  /// available), the Spotify app is opened and the transfer is tried again.
  /// If you come back to Hushdock before it worked, it tries once more.
  Future<bool> playOnSpotifyDevice(String deviceId, {bool wake = true}) async {
    var ok = await _spotify.transferTo(deviceId);
    var woke = false;
    // [wake] is off for the retry on coming back, so Spotify is not opened twice
    if (!ok && wake && await _isThisDevice(deviceId)) {
      _pendingDevice = deviceId;
      if (await _openSpotifyHere()) {
        woke = true;
        for (var i = 0; i < 4 && !ok; i++) {
          await Future<void>.delayed(_spotifyRetryDelay);
          // the device may come back under a new id once its app has woken up
          final id = await _thisDeviceId() ?? deviceId;
          ok = await _spotify.transferTo(id);
        }
      }
    }
    if (ok) _pendingDevice = null;
    if (ok && woke) unawaited(_backToHushdock());
    musicError = ok ? null : _spotify.lastError;
    if (ok) _refreshSoon();
    return ok;
  }

  /// Play with nothing playing: start on this device, not on whichever one
  /// (an Echo, say) Spotify played on last. Opens Spotify here if it is asleep.
  Future<bool> playOnThisDevice() async {
    var id = await _thisDeviceId();
    if (id == null) {
      if (!await _openSpotifyHere()) {
        musicError = _spotify.lastError;
        return false;
      }
      for (var i = 0; i < 4 && id == null; i++) {
        await Future<void>.delayed(_spotifyRetryDelay);
        id = await _thisDeviceId();
      }
      if (id == null) {
        _pendingPhonePlay = true;
        musicError = 'Spotify is not open on $hereName yet. Try again';
        return false;
      }
    }
    final ok = await playOnSpotifyDevice(id, wake: false);
    if (ok && defaultTargetPlatform == TargetPlatform.iOS) {
      musicNotice =
          'Playing on this iPhone. Tap the banner at the top to come back.';
    }
    if (ok) unawaited(_backToHushdock());
    return ok;
  }

  static bool get _onComputer => const {
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  }.contains(defaultTargetPlatform);

  /// What this device is called in messages: "this PC", "this phone".
  static String get hereName => switch (defaultTargetPlatform) {
    TargetPlatform.windows || TargetPlatform.linux => 'this PC',
    TargetPlatform.macOS => 'this Mac',
    _ => 'this phone',
  };

  /// Spotify could not be opened because it is not installed here (a PC):
  /// the music card then offers the download.
  bool spotifyMissing = false;

  /// Where to get Spotify for this device.
  static String get spotifyDownload =>
      defaultTargetPlatform == TargetPlatform.macOS
      ? 'https://www.spotify.com/download/mac/'
      : 'https://www.spotify.com/download/windows/';

  Future<bool> getSpotify() => _systemService.openUrl(spotifyDownload);

  /// Opens a web link in the browser (the Spotify dashboard in the setup guide).
  Future<bool> openLink(String url) => _systemService.openUrl(url);

  /// Opens the Spotify app here; when that fails, says why.
  Future<bool> _openSpotifyHere() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Spotify takes the screen: keep Hushdock alive (about 30 s) to start the
      // music from here, and let go on its own if that never happens
      await _systemService.beginBackgroundWork();
      Timer(const Duration(seconds: 28), _systemService.endBackgroundWork);
    }
    final ok = await _systemService.openSpotify();
    spotifyMissing = !ok && _onComputer;
    if (!ok) {
      _spotify.lastError = _onComputer
          ? 'Spotify is not installed on $hereName'
          : 'Spotify is not installed on this phone';
    }
    return ok;
  }

  /// After waking Spotify, bring Hushdock back: on Android by opening it
  /// again (it may refuse unless Hushdock may display over other apps), on a
  /// PC by raising its window over Spotify's. iOS does not let an app open
  /// itself from the background, so it posts a "tap to return" notification.
  Future<void> _backToHushdock() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _systemService.launchApp('com.ytchannel.standbypro');
    } else if (_onComputer) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _systemService.bringToFront();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS has no way to bring an app forward by itself: a notification that
      // opens Hushdock with one tap is the nearest thing
      await _systemService.returnPrompt();
      await _systemService.endBackgroundWork();
    }
  }

  bool _pendingPhonePlay = false;

  /// A short, friendly line to show once after a command (the iPhone hand-off
  /// to the Spotify app); the card shows it and clears it.
  String? musicNotice;

  Future<String?> _thisDeviceId() async => thisSpotifyDevice(
    await spotifyDevices(),
    name: _spotify.phoneName,
    computer: _onComputer,
  )?.id;

  Future<bool> _isThisDevice(String deviceId) async {
    if (deviceId == await _thisDeviceId()) return true;
    final known = lastSpotifyDevices.where((d) => d.id == deviceId).toList();
    return thisSpotifyDevice(
          known,
          name: _spotify.phoneName,
          computer: _onComputer,
        ) !=
        null;
  }

  Future<List<({String package, String app})>> mediaPlayers() =>
      _systemService.mediaPlayers();

  Future<bool> openSpotifyApp() => _openSpotifyHere();
  Future<bool> hasNotificationAccess() =>
      _systemService.hasNotificationAccess();
  Future<bool> openNotificationAccess() =>
      _systemService.openNotificationAccessSettings();

  Future<bool> connectSpotify() async {
    // A full-screen window hides the sign-in window behind it (a separate
    // space on a Mac, behind the borderless window on Windows): step out of
    // full screen for the sign-in, then come back and raise Hushdock.
    final computer = const {
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);
    final wasFull = computer && settings.fullscreen;
    if (wasFull) {
      await _systemService.setFullscreen(false);
      // the Mac animates out of full screen; the sign-in must not start mid-way
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    final ok = await _spotify.connect();
    if (wasFull) await _systemService.setFullscreen(true);
    if (computer) await _systemService.bringToFront();
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
          _notifyBackground();
          unawaited(_applyPendingQueue(playing));
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

  /// The volume of the Spotify device that is playing, up or down by [delta]
  /// percent (only a device Spotify lets us control).
  Future<bool> nudgeVolume(int delta) async {
    if (!_spotify.isConnected) return false;
    final active = (await spotifyDevices()).where(
      (d) => d.isActive && d.volume != null,
    );
    if (active.isEmpty) return false;
    final d = active.first;
    return setSpotifyVolume(d.id, (d.volume! + delta).clamp(0, 100));
  }

  /// Commands: playPause, next, previous, back10, forward10.
  Future<bool> sendMediaCommand(String command) async {
    final now = snapshots.nowPlaying;
    final bool ok;
    if (command == 'playPause' &&
        !now.isPlaying &&
        _spotify.isConnected &&
        _spotify.playerIdle) {
      ok = await playOnThisDevice();
    } else if (command == 'playPause' &&
        !now.isPlaying &&
        !_spotify.isConnected &&
        defaultTargetPlatform == TargetPlatform.iOS) {
      // not signed in on an iPhone: the Spotify app is the only player, so
      // open it (an iPhone cannot see or control it from here)
      ok = await _openSpotifyHere();
      musicError = ok ? null : 'Spotify is not installed on this phone';
      if (ok)
        musicNotice = 'Spotify is open. Switch back here when you are done.';
    } else if (now.viaSpotifyApi) {
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
  bool _fullscreenSent = false;

  Future<void> _applySystemSettings() async {
    // first, so F11 answers at once; only on a change: the window starts as a
    // window, so a saved full screen is applied once at start-up
    if ((defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS) &&
        settings.fullscreen != _fullscreenSent) {
      _fullscreenSent = settings.fullscreen;
      await _systemService.setFullscreen(settings.fullscreen);
    }
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
    var delay = ClockCadence.nextDelay(now, settings, appVisible: appVisible);
    // a running or ringing timer needs the seconds, even if the clock does not
    if ((timerRunning || timerDone) && appVisible) {
      final toSecond = Duration(
        milliseconds: 1000 - DateTime.now().millisecond,
      );
      if (toSecond < delay) delay = toSecond;
    }
    _timer = Timer(delay, () {
      now = DateTime.now();
      _checkTimer();
      // the burn-in shift moves once a minute, even if the clock ticks
      // every second (otherwise the whole screen jumps each second)
      if (BurnInProtection.shouldAdvance(_lastShift, now)) {
        burnInTick += 1;
        _lastShift = now;
      }
      _notifyBackground();
      _scheduleNextTick();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appVisible =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _scheduleNextTick();
    final pending = _pendingDevice;
    if (state == AppLifecycleState.resumed && pending != null) {
      // back from opening Spotify: try the transfer again now it is awake
      _pendingDevice = null;
      unawaited(
        _thisDeviceId().then(
          (id) => playOnSpotifyDevice(id ?? pending, wake: false).then((ok) {
            if (!ok) notifyListeners();
          }),
        ),
      );
    }
    if (state == AppLifecycleState.resumed && _pendingPhonePlay) {
      _pendingPhonePlay = false;
      unawaited(
        _thisDeviceId().then((id) {
          if (id != null) playOnSpotifyDevice(id, wake: false);
        }),
      );
    }
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
    _queueTimer?.cancel();
    _weatherTimer?.cancel();
    _lightTimer?.cancel();
    _meetingTimer?.cancel();
    photoStep.dispose();
    mediaKey.dispose();
    super.dispose();
  }
}
