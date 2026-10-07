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
