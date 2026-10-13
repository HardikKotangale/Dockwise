import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/services/spotify_service.dart';

Map<String, dynamic> _track(String id) => {
  'uri': 'spotify:track:$id',
  'name': 'Song $id',
  'artists': [
    {'name': 'Artist'},
  ],
  'album': {'images': []},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <String>[];
  final bodies = <String>[];
  late SpotifyService spotify;

  Future<void> setUpSpotify(Map<String, http.Response> answers) async {
    SharedPreferences.setMockInitialValues({'spotify_refresh': 'r'});
    calls.clear();
    bodies.clear();
    spotify = SpotifyService(
      client: MockClient((req) async {
        if (req.url.host == 'accounts.spotify.com') {
          return http.Response(
            jsonEncode({'access_token': 'a', 'expires_in': 3600}),
            200,
          );
        }
        final key = '${req.method} ${req.url.path}';
        calls.add(key);
        bodies.add(req.body);
        return answers[key] ?? http.Response('{}', 404);
      }),
    );
    await spotify.load();
  }

  http.Response ok(Object body) => http.Response(jsonEncode(body), 200);

  test('playlists you cannot list are marked and come last', () async {
    await setUpSpotify({
      'GET /v1/me': ok({'id': 'me'}),
      'GET /v1/me/playlists': ok({
        'items': [
          {
            'uri': 'spotify:playlist:a',
            'name': 'Theirs',
            'owner': {'id': 'x'},
          },
          {
            'uri': 'spotify:playlist:b',
            'name': 'Mine',
            'owner': {'id': 'me'},
          },
          {
            'uri': 'spotify:playlist:c',
            'name': 'Shared',
            'owner': {'id': 'x'},
            'collaborative': true,
          },
        ],
      }),
    });
    final list = await spotify.playlists();
    expect(list.map((p) => p.name), ['Mine', 'Shared', 'Theirs']);
    expect(list.map((p) => p.canBrowse), [true, true, false]);
  });

  test(
    'Liked Songs lists the songs, and a second look costs no request',
    () async {
      await setUpSpotify({
        'GET /v1/me/tracks': ok({
          'items': [
            {'track': _track('1')},
            {'track': _track('2')},
            {'track': _track('1')}, // twice: shown once
          ],
        }),
      });
      final first = await spotify.playlistTracks(SpotifyPlaylist.liked.uri);
      expect(first.map((h) => h.uri), ['spotify:track:1', 'spotify:track:2']);
      await spotify.playlistTracks(SpotifyPlaylist.liked.uri);
      expect(calls.where((c) => c == 'GET /v1/me/tracks').length, 1);
    },
  );

  test(
    'a refused playlist explains itself; a refused list says to sign in',
    () async {
      await setUpSpotify({
        'GET /v1/playlists/zzz/items': http.Response('{}', 403),
        'GET /v1/me/player/recently-played': http.Response('{}', 403),
      });
      expect(await spotify.playlistTracks('spotify:playlist:zzz'), isEmpty);
      expect(spotify.lastError, contains('your own playlists'));
      expect(await spotify.playlistTracks(SpotifyPlaylist.recent.uri), isEmpty);
      expect(spotify.lastError, contains('sign in again'));
    },
  );

  test('a song from Liked Songs plays with the rest following it', () async {
    await setUpSpotify({
      'GET /v1/me/player/devices': ok({
        'devices': [
          {'id': 'd', 'name': 'Phone', 'type': 'Smartphone', 'is_active': true},
        ],
      }),
      'PUT /v1/me/player/play': http.Response('', 204),
    });
    final done = await spotify.playSongs([
      'spotify:track:1',
      'spotify:track:2',
    ], from: 'spotify:track:2');
    expect(done, isTrue);
    final sent = jsonDecode(bodies.last) as Map<String, dynamic>;
    expect(sent['uris'], ['spotify:track:1', 'spotify:track:2']);
    expect(sent['offset'], {'uri': 'spotify:track:2'});
  });
}
