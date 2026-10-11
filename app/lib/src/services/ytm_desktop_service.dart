import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/standby_models.dart';

/// YouTube Music playing on a computer (e.g. your Mac), controlled from here.
///
/// YouTube Music has no remote-control service of its own. This talks to the
/// free YouTube Music desktop app ("Pear Desktop", formerly youtube-music) and
/// its optional "API Server" plugin, which exposes the player over Wi-Fi. Turn
/// that plugin on in the desktop app, then give Dockwise the Mac's address.
class YtmDesktopService {
  YtmDesktopService({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  static const _hostKey = 'ytm_host';
  static const _tokenKey = 'ytm_token';
  static const defaultPort = 26538;
  static const _clientId = 'dockwise';

  String _host = '';
  int _port = defaultPort;
  String? _token;

  /// What went wrong the last time, in words for the user.
  String? lastError;

  bool get isConfigured => _host.isNotEmpty;
  String get address =>
      _host.isEmpty ? '' : (_port == defaultPort ? _host : '$_host:$_port');

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _setAddress(p.getString(_hostKey) ?? '');
    _token = p.getString(_tokenKey);
  }

  /// "192.168.1.20", "my-mac.local" or "my-mac.local:26538"; empty forgets it.
  Future<void> setAddress(String value) async {
    _setAddress(value);
    _token = null;
    final p = await SharedPreferences.getInstance();
    await p.setString(_hostKey, address);
    await p.remove(_tokenKey);
  }

  void _setAddress(String value) {
    var v = value.trim().replaceFirst(RegExp(r'^https?://'), '');
    v = v.replaceAll(RegExp(r'/+$'), '');
    var port = defaultPort;
    final colon = v.lastIndexOf(':');
    if (colon > 0) {
      port = int.tryParse(v.substring(colon + 1)) ?? defaultPort;
      v = v.substring(0, colon);
    }
    _host = v;
    _port = port;
  }

  Uri _uri(String path) =>
      Uri(scheme: 'http', host: _host, port: _port, path: '/api/v1/$path');

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// One request, signing in first when the Mac asks for it. The desktop app
  /// shows an "allow this device?" prompt the first time.
  Future<http.Response?> _send(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!isConfigured) return null;
    Future<http.Response> once() async {
      final req = http.Request(method, _uri(path))
        ..headers.addAll(_headers)
        ..body = body == null ? '' : jsonEncode(body);
      return http.Response.fromStream(await _http.send(req).timeout(timeout));
    }

    try {
      var res = await once();
      if (res.statusCode == 401 || res.statusCode == 403) {
        if (!await _signIn()) return null;
        res = await once();
      }
      if (res.statusCode >= 400) {
        lastError = 'YouTube Music answered ${res.statusCode}';
      }
      return res;
    } on TimeoutException {
      lastError = 'No answer from $address. Is YouTube Music open on the Mac?';
    } catch (e) {
      lastError = 'Cannot reach $address. Same Wi-Fi? API Server plugin on?';
      debugPrint('ytm request failed: $e');
    }
    return null;
  }

  Future<bool> _signIn() async {
    try {
      final res = await _http
          .post(
            Uri(
              scheme: 'http',
              host: _host,
              port: _port,
              path: '/auth/$_clientId',
            ),
          )
          // the Mac waits for you to click "allow"
          .timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final token = (jsonDecode(res.body) as Map)['accessToken'] as String?;
        if (token != null) {
          _token = token;
          final p = await SharedPreferences.getInstance();
          await p.setString(_tokenKey, token);
          return true;
        }
      }
      lastError = res.statusCode == 403
          ? 'The Mac refused. Choose "Allow" on the YouTube Music prompt.'
          : 'Could not sign in to YouTube Music (${res.statusCode})';
    } on TimeoutException {
      lastError = 'Allow Dockwise on the YouTube Music prompt on your Mac.';
    } catch (e) {
      lastError = 'Cannot reach $address';
    }
    return false;
  }

  /// Is the Mac there, and did it let us in?
  Future<bool> check() async {
    lastError = null;
    final res = await _send('GET', 'song', timeout: const Duration(seconds: 8));
    return res != null && res.statusCode < 400;
  }

  /// What is playing, or null when nothing is (or the Mac is not reachable).
  Future<NowPlayingSnapshot?> nowPlaying() async {
    final res = await _send('GET', 'song');
    if (res == null || res.statusCode != 200 || res.body.isEmpty) return null;
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final title = j['title'] as String?;
      if (title == null || title.isEmpty) return null;
      final duration = ((j['songDuration'] as num?) ?? 0) * 1000;
      final elapsed = ((j['elapsedSeconds'] as num?) ?? 0) * 1000;
      return NowPlayingSnapshot(
        title: title,
        artist: j['artist'] as String? ?? '',
        source: 'YouTube Music · Mac',
        progress: duration == 0
            ? 0
            : (elapsed / duration).clamp(0, 1).toDouble(),
        isPlaying: !(j['isPaused'] as bool? ?? true),
        isControllable: true,
        artUrl: j['imageSrc'] as String?,
        positionMs: elapsed.toInt(),
        durationMs: duration.toInt(),
        viaYtm: true,
        fetchedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('ytm song not understood: $e');
      return null;
    }
  }

  /// playPause, next, previous, back10, forward10.
  Future<bool> command(String command) async {
    final res = switch (command) {
      'playPause' => await _send('POST', 'toggle-play'),
      'next' => await _send('POST', 'next'),
      'previous' => await _send('POST', 'previous'),
      'back10' => await _send('POST', 'go-back', body: {'seconds': 10}),
      'forward10' => await _send('POST', 'go-forward', body: {'seconds': 10}),
      _ => null,
    };
    return res != null && res.statusCode < 300;
  }

  Future<bool> seekTo(int ms) async {
    final res = await _send('POST', 'seek-to', body: {'seconds': ms / 1000});
    return res != null && res.statusCode < 300;
  }

  /// 0-100, or null when it cannot be read.
  Future<int?> volume() async {
    final res = await _send('GET', 'volume');
    if (res == null || res.statusCode != 200) return null;
    try {
      return ((jsonDecode(res.body) as Map)['state'] as num?)?.round();
    } catch (_) {
      return null;
    }
  }

  Future<bool> setVolume(int percent) async {
    final res = await _send(
      'POST',
      'volume',
      body: {'volume': percent.clamp(0, 100)},
    );
    return res != null && res.statusCode < 300;
  }
}
