import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

import '../domain/standby_models.dart';

/// What the auto-start feature still needs from the user (system settings).
typedef AutoStartStatus = ({
  bool overlay, // "Display over other apps": lets it open from the background
  bool notifications,
  bool battery, // exempt from battery optimization: keeps the watcher alive
  bool running, // the background watcher is running
});

/// One live tilt reading: lean 0 = flat .. 90 = upright, roll 0 = portrait ..
/// 90 = landscape, and whether it meets the chosen posture right now.
typedef PostureNow = ({double lean, double roll, bool matches});

class StandbySystemService {
  StandbySystemService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('standby_pro/system');

  final MethodChannel _channel;

  Future<bool> setKeepAwake(bool enabled) async {
    return _invokeBool('setKeepAwake', {'enabled': enabled});
  }

  /// Windows: borderless over the whole monitor the window is on, or back to
  /// the window it was. False where there is no such thing (phones, tests).
  Future<bool> setFullscreen(bool enabled) =>
      _invokeBool('setFullscreen', {'enabled': enabled});

  /// Room light in lux, or null when this device has no light sensor we can
  /// read (iPhone does not let apps read it) or it has not reported yet.
  Future<double?> ambientLux() async {
    try {
      return (await _channel.invokeMethod<num>('ambientLux'))?.toDouble();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> setBrightness(double value) async {
    return _invokeBool('setBrightness', {'value': value.clamp(0.05, 1.0)});
  }

  Future<bool> mediaCommand(String command) async {
    return _invokeBool('mediaCommand', {'command': command});
  }

  Future<bool> seekBy(int deltaMs) =>
      _invokeBool('seekBy', {'deltaMs': deltaMs});

  /// Follow this Android package's media session ('' = automatic).
  Future<bool> setPreferredPlayer(String package) =>
      _invokeBool('setPreferredPlayer', {'package': package});

  /// Apps with an active media session right now: [{package, app}].
  Future<List<({String package, String app})>> mediaPlayers() async {
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'mediaPlayers',
      );
      return [
        for (final m in list ?? const <Map<Object?, Object?>>[])
          (package: m['package'] as String, app: m['app'] as String),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<bool> launchApp(String package) =>
      _invokeBool('launchApp', {'package': package});

  /// Opens the Spotify app here: by package on Android, by its link on iPhone
  /// and on a PC (the desktop app answers spotify:). False when it is not
  /// installed.
  Future<bool> openSpotify() => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => openUrl('spotify://'),
    TargetPlatform.windows => openUrl('spotify:'),
    _ => launchApp('com.spotify.music'),
  };

  /// Opens a link with whatever handles it here (an app's own link, or a web
  /// page in the browser). False when nothing does.
  Future<bool> openUrl(String url) => _invokeBool('launchApp', {'url': url});

  /// A PC: raises Hushdock's window over the others (after opening Spotify,
  /// whose window comes up on top).
  Future<bool> bringToFront() => _invokeBool('bringToFront', const {});

  /// Plays the timer's end sound ('alarm', 'chime', 'fanfare' or 'none') and
  /// vibrates. On Android, a phone on silent or vibrate gets only the buzz.
  /// iPhone cannot tell us about the silent switch: its sound is muted by the
  /// switch itself, so the buzz is what you feel there.
  Future<void> timerAlert({
    required String sound,
    required bool vibrate,
  }) async {
    final ok = await _invokeBool('timerAlert', {
      'sound': sound,
      'vibrate': vibrate,
    });
    if (ok) return;
    // no native side (tests, other platforms): the plain system ones
    if (sound != 'none') unawaited(SystemSound.play(SystemSoundType.alert));
    if (vibrate) unawaited(HapticFeedback.heavyImpact());
  }

  Future<String> deviceModel() async {
    try {
      return await _channel.invokeMethod<String>('deviceModel') ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  /// Jumps the active phone player to [positionMs].
  Future<bool> seekTo(int positionMs) =>
      _invokeBool('seekTo', {'positionMs': positionMs});

  /// Saves the auto-start settings natively and starts/stops the watcher.
  Future<bool> configureAutoStart({
    required bool enabled,
    required double leanDeg,
    required bool landscapeOnly,
    required bool exitOnUnplug,
  }) => _invokeBool('configureAutoStart', {
    'enabled': enabled,
    'leanDeg': leanDeg,
    'landscapeOnly': landscapeOnly,
    'exitOnUnplug': exitOnUnplug,
  });

  Future<AutoStartStatus> autoStartStatus() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>(
        'autoStartStatus',
      );
      return (
        overlay: m?['overlay'] == true,
        notifications: m?['notifications'] == true,
        battery: m?['battery'] == true,
        running: m?['running'] == true,
      );
    } on MissingPluginException {
      return (
        overlay: false,
        notifications: false,
        battery: false,
        running: false,
      );
    } on PlatformException {
      return (
        overlay: false,
        notifications: false,
        battery: false,
        running: false,
      );
    }
  }

  Future<bool> openOverlaySettings() =>
      _invokeBool('openOverlaySettings', const {});
  Future<bool> openBatterySettings() =>
      _invokeBool('openBatterySettings', const {});
  Future<bool> requestNotifications() =>
      _invokeBool('requestNotifications', const {});

  Future<bool> postureProbe(bool on) => _invokeBool('postureProbe', {'on': on});

  Future<PostureNow?> postureNow({
    required double leanDeg,
    required bool landscapeOnly,
  }) async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('postureNow', {
        'leanDeg': leanDeg,
        'landscapeOnly': landscapeOnly,
      });
      if (m == null) return null;
      return (
        lean: (m['lean'] as num).toDouble(),
        roll: (m['roll'] as num).toDouble(),
        matches: m['matches'] == true,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> hasNotificationAccess() =>
      _invokeBool('hasNotificationAccess', const {});

  Future<bool> openNotificationAccessSettings() =>
      _invokeBool('openNotificationAccessSettings', const {});

  /// Active Android media session (any player on this phone), or null.
  Future<NowPlayingSnapshot?> nowPlaying() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('nowPlaying');
      if (m == null) return null;
      final duration = (m['duration'] as num?) ?? 0;
      final position = (m['position'] as num?) ?? 0;
      return NowPlayingSnapshot(
        title: m['title'] as String? ?? '',
        artist: m['artist'] as String? ?? '',
        source: m['app'] as String? ?? 'Android media session',
        progress: duration <= 0
            ? 0
            : (position / duration).clamp(0, 1).toDouble(),
        isPlaying: m['playing'] as bool? ?? false,
        isControllable: true,
        artBytes: m['art'] as Uint8List?,
        positionMs: position.toInt(),
        durationMs: duration.toInt(),
        fetchedAt: DateTime.now(),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> _invokeBool(String method, Map<String, Object> arguments) async {
    try {
      final result = await _channel.invokeMethod<bool>(method, arguments);
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
