import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/spotify_service.dart';
import '../../../state/standby_controller.dart';
import 'mini_keyboard.dart';

/// Full-screen Spotify search, opened from the music card. Type on our own
/// keyboard (so the system keyboard never covers the screen), tap a result to
/// play it, or tap + on a song to add it to the queue.
class SpotifySearchPage extends StatefulWidget {
  const SpotifySearchPage({super.key, required this.controller});

  final StandbyController controller;

  @override
  State<SpotifySearchPage> createState() => _SpotifySearchPageState();
}

class _SpotifySearchPageState extends State<SpotifySearchPage> {
  final _text = TextEditingController();
  Timer? _debounce;
  List<SpotifyHit> _hits = const [];
  bool _loading = false;
  bool _searched = false; // a search finished, so "No results" is meaningful
  bool _keyboard = true;
  String? _error;
  int _seq = 0; // ignore answers that arrive after a newer search started

  StandbyController get c => widget.controller;
  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    final q = _text.text.trim();
    if (q.length < 2) {
      setState(() {
        _hits = const [];
        _loading = false;
        _searched = false;
        _error = null;
      });
      return;
    }
    setState(() {}); // show the typed text now
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q));
  }

  Future<void> _search(String q) async {
    final mine = ++_seq;
    setState(() => _loading = true);
    final hits = await c.searchSpotify(q);
    if (!mounted || mine != _seq) return;
    setState(() {
      _hits = hits;
      _loading = false;
      _searched = true;
      _error = hits.isEmpty ? c.musicError : null;
    });
  }

  void _type(String ch) {
    _text.text += ch;
    _changed();
  }

  void _backspace() {
    if (_text.text.isEmpty) return;
    _text.text = _text.text.substring(0, _text.text.length - 1);
    _changed();
  }

  void _clear() {
    _text.clear();
    _changed();
  }

  Future<void> _play(SpotifyHit hit) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ok = await c.playSpotifyUri(hit.uri);
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Playing ${hit.title}' : c.musicError ?? 'Could not play',
          ),
        ),
      );
    if (ok) nav.pop(); // back to the music card
  }

  Future<void> _queue(SpotifyHit hit) async {
    final ok = await c.queueSpotifyUri(hit.uri);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Added to queue' : c.musicError ?? 'Could not add',
          ),
        ),
      );
  }

  String _kindLabel(String kind) => switch (kind) {
    'track' => 'Songs',
    'album' => 'Albums',
    _ => 'Playlists',
  };

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const Text(
          'Search Spotify',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _field() {
    final empty = _text.text.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: GestureDetector(
        key: const ValueKey('search-field'),
        onTap: () => setState(() => _keyboard = true),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 22, color: Colors.white60),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  empty ? 'Songs, albums, playlists' : _text.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    color: empty ? Colors.white38 : Colors.white,
                  ),
                ),
              ),
              if (!empty)
                IconButton(
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  onPressed: _clear,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _art(SpotifyHit hit) {
    final fallback = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        hit.kind == 'track'
            ? Icons.music_note_rounded
            : Icons.library_music_rounded,
        size: 22,
        color: Colors.white54,
      ),
    );
    final url = hit.imageUrl;
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _results() {
    if (_error != null && _hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
        ),
      );
    }
    if (_hits.isEmpty) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator(strokeWidth: 2)
            : Text(
                _searched ? 'No results' : 'Type to search',
                style: const TextStyle(color: Colors.white38, fontSize: 16),
              ),
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          for (var i = 0; i < _hits.length; i++) ...[
            if (i == 0 || _hits[i].kind != _hits[i - 1].kind)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  _kindLabel(_hits[i].kind),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ListTile(
              dense: true,
              leading: _art(_hits[i]),
              title: Text(
                _hits[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _hits[i].kind == 'track'
                    ? _hits[i].subtitle
                    : '${_hits[i].kind == 'album' ? 'Album' : 'Playlist'}'
                          '${_hits[i].subtitle.isEmpty ? '' : ' · ${_hits[i].subtitle}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _hits[i].kind == 'track'
                  ? IconButton(
                      tooltip: 'Add to queue',
                      onPressed: () => _queue(_hits[i]),
                      icon: const Icon(Icons.playlist_add_rounded),
                    )
                  : null,
              onTap: () => _play(_hits[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _keys() => MiniKeyboard(
    onChar: _type,
    onBackspace: _backspace,
    onDone: () => setState(() => _keyboard = false),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= 700) {
              // landscape: keyboard on the left, results on the right
              return Row(
                children: [
                  SizedBox(
                    width: box.maxWidth * 0.46,
                    child: Column(
                      children: [
                        _header(),
                        _field(),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: _keyboard
                                ? _keys()
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _results()),
                ],
              );
            }
            return Column(
              children: [
                _header(),
                _field(),
                Expanded(child: _results()),
                if (_keyboard)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: SizedBox(
                      height: box.maxHeight * 0.34,
                      child: _keys(),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
