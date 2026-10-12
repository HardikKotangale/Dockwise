import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:spotify_sdk/spotify_sdk.dart';

import 'spotify_service.dart';

/// Prototype: Spotify's iOS App Remote. It talks straight to the Spotify app
/// on this phone, so a command skips the trip through Spotify's servers.
/// iOS only; it needs the Spotify app installed. Timings go to the debug log.
class SpotifyRemote {
  bool connected = false;

  Future<bool> connect() async {
    if (!Platform.isIOS) return false;
    try {
      final sw = Stopwatch()..start();
      connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: SpotifyService.clientId,
        redirectUrl: 'hushdock://spotify-callback',
      );
      debugPrint('REMOTE connect=$connected in ${sw.elapsedMilliseconds} ms');
    } catch (e) {
      debugPrint('REMOTE connect failed: $e');
      connected = false;
    }
    return connected;
  }

  /// Plays [uri]; null when the remote is not connected (use the web API).
  Future<bool?> play(String uri) async {
    if (!connected) return null;
    try {
      final sw = Stopwatch()..start();
      await SpotifySdk.play(spotifyUri: uri);
      debugPrint('REMOTE play ack in ${sw.elapsedMilliseconds} ms');
      return true;
    } catch (e) {
      debugPrint('REMOTE play failed: $e');
      connected = false;
      return null;
    }
  }
}
