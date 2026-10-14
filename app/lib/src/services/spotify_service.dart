import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../domain/standby_models.dart';
import 'token_store.dart';

class SpotifyDevice {
  const SpotifyDevice(
    this.id,
    this.name,
    this.type,
    this.isActive, {
    this.volume,
  });
  final int? volume; // 0-100; null = this device cannot be controlled remotely
  final String id;
  final String name;
  final String type; // Computer, Smartphone, Speaker...
  final bool isActive;
}

/// One search result: a song, an album or a playlist.
class SpotifyHit {
  const SpotifyHit(
    this.uri,
    this.title,
    this.subtitle,
    this.kind,
    this.imageUrl,
  );
  final String uri;
  final String title;
  final String subtitle; // artists, or the playlist owner
  final String kind; // 'track', 'album' or 'playlist'
  final String? imageUrl;
}

/// The play queue: the current song and what comes next.
class SpotifyQueue {
  const SpotifyQueue(this.now, this.next);
  final SpotifyHit? now;
  final List<SpotifyHit> next;
}

class SpotifyPlaylist {
  const SpotifyPlaylist(
    this.uri,
    this.name,
    this.imageUrl, {
    this.canBrowse = true,
  });

  /// Your library's two song lists, shown beside the playlists.
  static const liked = SpotifyPlaylist('hushdock:liked', 'Liked Songs', null);
  static const recent = SpotifyPlaylist(
    'hushdock:recent',
    'Recently played',
    null,
  );

  final String uri;
  final String name;
  final String? imageUrl;

  /// Spotify only shows the songs of playlists you own or share; any other
  /// playlist can be played, but not listed.
  final bool canBrowse;

  /// Liked Songs and Recently played: a list of songs, not a Spotify playlist.
  bool get isSongList => uri == liked.uri || uri == recent.uri;
}

/// Spotify Web API (Spotify Connect) client. Controls whichever device is
/// active, including a Mac. Playback control needs Premium.
class SpotifyService {
  SpotifyService({http.Client? client, AssetBundle? assets, TokenStore? tokens})
    : _http = client ?? http.Client(),
      _assets = assets ?? rootBundle,
      _tokens = tokens ?? TokenStore();

  /// Your Spotify app's Client ID (not a secret, but kept out of Git). From
  /// `--dart-define=SPOTIFY_CLIENT_ID=...`, else from the optional, git-ignored
  /// `assets/local/spotify.json`, else empty (Spotify then shows "not set up").
  String clientId = const String.fromEnvironment('SPOTIFY_CLIENT_ID');
  static const _scheme = 'hushdock';
  // The same on every platform. On Windows the sign-in runs in its own webview
  // window, which catches this link itself, so no link scheme needs
  // registering on the PC (and the webview matches the scheme only, so an
  // http://127.0.0.1 callback would never be caught there).
  static const _redirect = '$_scheme://spotify-callback';
  static const _scopes =
      'user-read-playback-state user-modify-playback-state '
      'user-read-currently-playing playlist-read-private '
      'user-library-read user-read-recently-played';
  static const _api = 'https://api.spotify.com/v1';

  final http.Client _http;
  final AssetBundle _assets;
  final TokenStore _tokens;
  String? _access;
  String? _refresh;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  /// Human-readable reason the last command failed (null if it worked).
  String? lastError;

  /// This phone's model name; its Spotify device is preferred when picking one.
  String phoneName = '';

  bool get isConfigured => clientId.isNotEmpty;

  /// The Client ID in assets/local/spotify.json, or '' when there is no such
  /// file (a fresh clone) or it cannot be read.
  Future<String> _localClientId() async {
    try {
      final json = jsonDecode(
        await _assets.loadString('assets/local/spotify.json'),
      );
      return ((json as Map)['SPOTIFY_CLIENT_ID'] as String? ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  bool get isConnected => _refresh != null;

  Future<void> load() async {
    if (clientId.isEmpty) clientId = await _localClientId();
    _refresh = await _tokens.read();
  }

  Future<bool> connect() async {
    if (!isConfigured) return false;
    final verifier = _randomString(64);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final authUrl = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': _redirect,
      'scope': _scopes,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'show_dialog':
          'true', // always offer the account chooser, so signing in again can switch account
    });
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: _scheme,
      );
      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) return false;
      return await _token({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': _redirect,
        'code_verifier': verifier,
      });
    } catch (_) {
      return false; // user cancelled or network error
    }
  }

  Future<void> disconnect() async {
    _access = _refresh = null;
    await _tokens.clear();
  }

  /// Null when nothing is playing on any device or the call failed.
  /// True when Spotify last said nothing is playing anywhere (as opposed to an
  /// error or a wait for the rate limit, where we know nothing new).
  bool playerIdle = false;

  Future<NowPlayingSnapshot?> nowPlaying() async {
    // additional_types: without it a podcast episode comes back as "nothing"
    final res = await _call('GET', '/me/player?additional_types=episode');
    playerIdle = res != null && res.statusCode == 204;
    if (res == null || res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final item = json['item'] as Map<String, dynamic>?;
    if (item == null) return null;
    final images =
        (item['album']?['images'] as List?) ??
        (item['images'] as List?) ?? // podcast episodes carry their own
        const [];
    final duration = (item['duration_ms'] as num?) ?? 0;
    final progress = (json['progress_ms'] as num?) ?? 0;
    final device = json['device']?['name'] as String? ?? 'Spotify';
    return NowPlayingSnapshot(
      title: item['name'] as String? ?? '',
      artist: _artistsOf(item),
      source: 'Spotify · $device',
      progress: duration == 0
          ? 0
          : (progress / duration).clamp(0, 1).toDouble(),
      isPlaying: json['is_playing'] as bool? ?? false,
      isControllable: true,
      artUrl: images.isEmpty ? null : images.first['url'] as String?,
      positionMs: progress.toInt(),
      durationMs: duration.toInt(),
      viaSpotifyApi: true,
      fetchedAt: DateTime.now(),
    );
  }

  Future<bool> command(
    String command, {
    required bool isPlaying,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    final res = switch (command) {
      'next' => await _call('POST', '/me/player/next'),
      'previous' => await _call('POST', '/me/player/previous'),
      'playPause' => await _playPause(isPlaying),
      'back10' || 'forward10' => await _call(
        'PUT',
        '/me/player/seek?position_ms=${(positionMs + (command == 'back10' ? -10000 : 10000)).clamp(0, durationMs > 0 ? durationMs : 1 << 31)}',
      ),
      _ => null,
    };
    return _ok(res);
  }

  Future<http.Response?> _playPause(bool isPlaying) async {
    if (isPlaying) return _call('PUT', '/me/player/pause');
    final res = await _call('PUT', '/me/player/play');
    if (res != null && res.statusCode == 404) {
      // no active device: wake whichever device Spotify lists
      final id = await _fallbackDevice();
      if (id != null) return _call('PUT', '/me/player/play?device_id=$id');
    }
    return res;
  }

  /// Jumps to [positionMs] in the current song (Spotify Premium).
  Future<bool> seekTo(int positionMs) async =>
      _ok(await _call('PUT', '/me/player/seek?position_ms=$positionMs'));

  bool _ok(http.Response? res) {
    if (res != null && res.statusCode < 300) {
      lastError = null;
      return true;
    }
    final reason = res == null ? 'no connection' : _reason(res);
    lastError = 'Spotify: $reason';
    debugPrint('Spotify call failed: ${res?.statusCode} ${res?.body}');
    return false;
  }

  static String _reason(http.Response res) {
    try {
      final err = jsonDecode(res.body)['error'] as Map<String, dynamic>?;
      final r = err?['reason'] as String?;
      if (r == 'PREMIUM_REQUIRED') return 'Premium is needed for this action';
      if (r == 'NO_ACTIVE_DEVICE') {
        return 'no device is playing. Open Spotify on a device, or pick one in Music settings';
      }
      final msg = err?['message'] as String?;
      if (res.statusCode == 404 ||
          r == 'DEVICE_NOT_FOUND' ||
          (msg ?? '').toLowerCase().contains('device not found')) {
        return 'Spotify is not open on that device. Open it there, then try again';
      }
      if (msg != null && msg.isNotEmpty) return msg;
    } catch (_) {}
    return 'error ${res.statusCode}';
  }

  /// Devices Spotify can play on right now (Mac, phone with Spotify open...).
  Future<List<SpotifyDevice>> devices() async {
    final res = await _call('GET', '/me/player/devices');
    if (res == null || res.statusCode != 200) return const [];
    final list = (jsonDecode(res.body)['devices'] as List?) ?? const [];
    return [
      for (final d in list.whereType<Map<String, dynamic>>())
        if (d['id'] != null && d['is_restricted'] != true)
          SpotifyDevice(
            d['id'] as String,
            d['name'] as String? ?? 'Device',
            d['type'] as String? ?? '',
            d['is_active'] as bool? ?? false,
            volume: (d['volume_percent'] as num?)?.toInt(),
          ),
    ];
  }

  /// Sets the volume (0-100) on [deviceId], e.g. a Mac or a speaker.
  Future<bool> setVolume(int percent, String deviceId) async => _ok(
    await _call(
      'PUT',
      '/me/player/volume?volume_percent=${percent.clamp(0, 100)}&device_id=$deviceId',
    ),
  );

  /// Moves playback to [deviceId] and starts it there.
  Future<bool> transferTo(String deviceId) async {
    final res = await _call(
      'PUT',
      '/me/player',
      body: jsonEncode({
        'device_ids': [deviceId],
        'play': true,
      }),
    );
    return _ok(res);
  }

  // Preference: this phone, then the active device, then any listed device.
  Future<String?> _fallbackDevice() async {
    final all = await devices();
    if (all.isEmpty) return null;
    // Something is playing somewhere: carry on there (a Mac, a speaker). Only
    // with nothing playing does this phone come first.
    if (!playerIdle) {
      for (final d in all) {
        if (d.isActive) return d.id;
      }
    }
    final phone = phoneName.toLowerCase();
    if (phone.isNotEmpty) {
      for (final d in all) {
        if (d.name.toLowerCase().contains(phone)) return d.id;
      }
    }
    return all.firstWhere((d) => d.isActive, orElse: () => all.first).id;
  }

  String? _userId;

  /// Playlists you can list first, then the play-only ones.
  Future<List<SpotifyPlaylist>> playlists() async {
    final res = await _call('GET', '/me/playlists?limit=50');
    if (res == null || res.statusCode != 200) return const [];
    _userId ??= await _me();
    final items = (jsonDecode(res.body)['items'] as List?) ?? const [];
    final all = [
      for (final p in items.whereType<Map<String, dynamic>>())
        SpotifyPlaylist(
          p['uri'] as String,
          p['name'] as String? ?? '',
          ((p['images'] as List?)?.firstOrNull as Map?)?['url'] as String?,
          // not sure who owns it (no id): assume yours, the list says if not
          canBrowse:
              _userId == null ||
              p['collaborative'] == true ||
              (p['owner'] as Map?)?['id'] == _userId ||
              p['owner'] == null,
        ),
    ];
    return [
      ...all.where((p) => p.canBrowse),
      ...all.where((p) => !p.canBrowse),
    ];
  }

  Future<String?> _me() async {
    final res = await _call('GET', '/me');
    if (res == null || res.statusCode != 200) return null;
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String?;
  }

  /// Starts a playlist on [deviceId], else the active device, else any device.
  Future<bool> playPlaylist(String uri, {String? deviceId}) =>
      playUri(uri, deviceId: deviceId);

  // lists already fetched, so opening one again is instant and costs no
  // request (Spotify rate-limits an app quickly)
  final _lists = <String, ({DateTime at, List<SpotifyHit> songs})>{};
  static const _listTtl = Duration(minutes: 5);

  /// The songs of a playlist you own or share, of Liked Songs, or of Recently
  /// played. Spotify answers 403 for any other playlist.
  Future<List<SpotifyHit>> playlistTracks(String uri) async {
    final hit = _lists[uri];
    if (hit != null && DateTime.now().difference(hit.at) < _listTtl) {
      lastError = null;
      return hit.songs;
    }
    final String path;
    if (uri == SpotifyPlaylist.liked.uri) {
      path = '/me/tracks?limit=50';
    } else if (uri == SpotifyPlaylist.recent.uri) {
      path = '/me/player/recently-played?limit=50';
    } else {
      path = '/playlists/${uri.split(':').last}/items?limit=100';
    }
    final res = await _call('GET', path);
    if (res?.statusCode == 403 || res?.statusCode == 401) {
      lastError = uri.startsWith('hushdock:')
          ? 'Sign out of Spotify in Music settings and sign in again, so '
                'Spotify can share this list.'
          : 'Spotify only lets apps list the songs of your own playlists. '
                'Tap Play to start this one.';
      return const [];
    }
    if (!_ok(res)) return const [];
    final seen = <String>{};
    final songs = [
      for (final i in (jsonDecode(res!.body)['items'] as List?) ?? const [])
        // "item" is the current name, "track" the one it replaced
        if (i is Map<String, dynamic> &&
            _queueItem(i['item'] ?? i['track']) != null &&
            seen.add(_queueItem(i['item'] ?? i['track'])!.uri))
          _queueItem(i['item'] ?? i['track'])!,
    ];
    _lists[uri] = (at: DateTime.now(), songs: songs);
    return songs;
  }

  /// Plays a list of songs (from Liked Songs or Recently played), starting at
  /// [from]; the rest follow in order.
  Future<bool> playSongs(List<String> uris, {String? from}) async {
    if (uris.isEmpty) return false; // lastError says why the list is empty
    final id = await _fallbackDevice();
    return _ok(
      await _call(
        'PUT',
        id == null ? '/me/player/play' : '/me/player/play?device_id=$id',
        body: jsonEncode({
          'uris': uris,
          if (from != null) 'offset': {'uri': from},
        }),
      ),
    );
  }

  /// Starts [trackUri] inside [playlistUri], so the rest of the playlist
  /// follows it.
  Future<bool> playInPlaylist(String playlistUri, String trackUri) async {
    final id = await _fallbackDevice();
    return _ok(
      await _call(
        'PUT',
        id == null ? '/me/player/play' : '/me/player/play?device_id=$id',
        body: jsonEncode({
          'context_uri': playlistUri,
          'offset': {'uri': trackUri},
        }),
      ),
    );
  }

  /// Plays a song, an album or a playlist. A song plays by itself; an album or
  /// playlist plays from its start.
  Future<bool> playUri(String uri, {String? deviceId}) async {
    final id = deviceId ?? await _fallbackDevice();
    final res = await _call(
      'PUT',
      id == null ? '/me/player/play' : '/me/player/play?device_id=$id',
      body: jsonEncode(
        uri.startsWith('spotify:track:')
            ? {
                'uris': [uri],
              }
            : {'context_uri': uri},
      ),
    );
    return _ok(res);
  }

  /// Adds a song to the end of the play queue.
  Future<bool> addToQueue(String uri) async {
    final id = await _fallbackDevice();
    final q =
        'uri=${Uri.encodeQueryComponent(uri)}${id == null ? '' : '&device_id=$id'}';
    return _ok(await _call('POST', '/me/player/queue?$q'));
  }

  // a small image is plenty for a list row
  static String? _imageOf(Object? images) {
    final list = (images as List?)?.whereType<Map<String, dynamic>>().toList();
    if (list == null || list.isEmpty) return null;
    return (list.length > 1 ? list[list.length - 2] : list.first)['url']
        as String?;
  }

  // artists of a song or album; a podcast episode has its show instead
  static String _artistsOf(Map<String, dynamic> m) {
    final names = ((m['artists'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((x) => x['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    return names.isNotEmpty
        ? names
        : (m['show'] as Map?)?['name'] as String? ?? '';
  }

  static SpotifyHit? _queueItem(Object? raw) {
    if (raw is! Map<String, dynamic> || raw['uri'] is! String) return null;
    return SpotifyHit(
      raw['uri'] as String,
      raw['name'] as String? ?? '',
      _artistsOf(raw),
      'track',
      _imageOf((raw['album'] as Map?)?['images'] ?? raw['images']),
    );
  }

  /// What is playing now and what is coming up (Spotify's "Queue" screen).
  Future<SpotifyQueue?> queue() async {
    final res = await _call('GET', '/me/player/queue');
    if (!_ok(res)) return null;
    final json = jsonDecode(res!.body) as Map<String, dynamic>;
    return SpotifyQueue(_queueItem(json['currently_playing']), [
      for (final q in (json['queue'] as List?) ?? const [])
        if (_queueItem(q) != null) _queueItem(q)!,
    ]);
  }

  /// Spotify's Web API cannot move a song in the queue, so this plays [now]
  /// again from [positionMs] followed by [next] in the new order. That replaces
  /// the album or playlist the queue came from with this list (at most 100).
  Future<bool> reorderQueue(
    SpotifyHit now,
    List<SpotifyHit> next,
    int positionMs,
  ) async => _ok(
    await _call(
      'PUT',
      '/me/player/play',
      body: jsonEncode({
        'uris': [
          for (final h in [now, ...next].take(100)) h.uri,
        ],
        'position_ms': positionMs,
      }),
    ),
  );

  /// Songs, albums and playlists matching [query]. Spotify allows at most 10
  /// results per type for apps in development mode, so we ask for 5 of each.
  Future<List<SpotifyHit>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final res = await _call(
      'GET',
      '/search?q=${Uri.encodeQueryComponent(q)}&type=track,album,playlist&limit=5',
    );
    if (!_ok(res)) return const [];
    final json = jsonDecode(res!.body) as Map<String, dynamic>;
    List<Map<String, dynamic>> items(
      String key,
    ) => (((json[key] as Map?)?['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>() // Spotify can return null entries
        .toList();
    return [
      for (final t in items('tracks'))
        SpotifyHit(
          t['uri'] as String,
          t['name'] as String? ?? '',
          _artistsOf(t),
          'track',
          _imageOf((t['album'] as Map?)?['images']),
        ),
      for (final a in items('albums'))
        SpotifyHit(
          a['uri'] as String,
          a['name'] as String? ?? '',
          _artistsOf(a),
          'album',
          _imageOf(a['images']),
        ),
      for (final p in items('playlists'))
        SpotifyHit(
          p['uri'] as String,
          p['name'] as String? ?? '',
          (p['owner'] as Map?)?['display_name'] as String? ?? '',
          'playlist',
          _imageOf(p['images']),
        ),
    ];
  }

  // Spotify answers 429 "too many requests" with how long to wait; until then
  // we send nothing, so polling faster never gets us blocked for long.
  DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// When Spotify last told us to slow down; the card then polls less often.
  DateTime lastRateLimitedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<http.Response?> _call(
    String method,
    String path, {
    String? body,
  }) async {
    if (!isConnected) return null;
    if (DateTime.now().isBefore(_blockedUntil)) return null;
    try {
      if (_access == null || DateTime.now().isAfter(_expires)) {
        if (!await _token({
          'grant_type': 'refresh_token',
          'refresh_token': _refresh!,
        })) {
          return null;
        }
      }
      final request = http.Request(method, Uri.parse('$_api$path'))
        ..headers['Authorization'] = 'Bearer $_access'
        ..headers['Content-Type'] = 'application/json';
      if (body != null) request.body = body;
      // a request that hangs must not freeze the card, so give up after a while
      final res = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 8)),
      );
      if (res.statusCode == 429) {
        final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? 5;
        _blockedUntil = DateTime.now().add(
          Duration(seconds: wait.clamp(1, 60)),
        );
        lastRateLimitedAt = DateTime.now();
      }
      return res;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _token(Map<String, String> form) async {
    final res = await _http.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      body: {...form, 'client_id': clientId},
    );
    if (res.statusCode != 200) {
      if (form['grant_type'] == 'refresh_token' && res.statusCode == 400) {
        await disconnect(); // refresh token revoked
      }
      return false;
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    _access = json['access_token'] as String;
    _expires = DateTime.now().add(
      Duration(seconds: (json['expires_in'] as num).toInt() - 30),
    );
    _refresh = json['refresh_token'] as String? ?? _refresh;
    await _tokens.write(_refresh!);
    return true;
  }

  static String _randomString(int n) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
