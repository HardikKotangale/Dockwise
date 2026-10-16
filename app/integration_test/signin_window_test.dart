// Opens the Spotify sign-in the way the app does on a Mac, with a made-up
// Client ID, so the window can be looked at (it shows Spotify's own "invalid
// client" page). Run like card_switch_perf_test.dart.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:standby_pro/src/services/spotify_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the sign-in opens in a window of the app', (t) async {
    final spotify = SpotifyService()..clientId = 'a' * 32;
    unawaited(spotify.connect());
    debugPrint('SIGNIN_OPEN');
    await Future<void>.delayed(const Duration(seconds: 25));
  });
}
