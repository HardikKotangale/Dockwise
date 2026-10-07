import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/spotify_service.dart';
import '../../../state/standby_controller.dart';

/// Spotify's queue shown inside the music card: what is playing and what comes
/// next. Tap a song to jump to it. It refreshes by itself while it is open.
class SpotifyQueueView extends StatefulWidget {
  const SpotifyQueueView({
    super.key,
    required this.controller,
    required this.onClose,
    this.onTouch,
  });

  final StandbyController controller;
  final VoidCallback onClose;

  /// Called on every touch so the card keeps the view open while it is used.
  final VoidCallback? onTouch;

  @override
  State<SpotifyQueueView> createState() => _SpotifyQueueViewState();
}

class _SpotifyQueueViewState extends State<SpotifyQueueView> {
  SpotifyQueue? _queue;
  bool _loading = true;
  String? _error;
  Timer? _poll;
  String? _lastSong; // detects a song change from any device

  StandbyController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _lastSong = _songKey();
    _load();
    c.addListener(_onController);
    // a safety net: the queue can also change without the song changing
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  String _songKey() {
    final n = c.snapshots.nowPlaying;
    return '${n.title}|${n.artist}';
  }

  // The card learns about song changes (even from another device) every second
  // or two. When the song changes, the queue moved too: reload it right away.
  void _onController() {
    final key = _songKey();
    if (key == _lastSong) return;
    _lastSong = key;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _load(); // Spotify updates its queue a beat after the song
    });
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final q = await c.spotifyQueue();
    if (!mounted) return;
    setState(() {
      _queue = q ?? _queue; // keep the old list on screen if a refresh fails
      _loading = false;
      _error = q == null ? c.musicError : null;
    });
  }

  Future<void> _skipTo(int index, SpotifyHit hit) async {
    widget.onTouch?.call();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await c.skipInQueue(index);
    if (!mounted) return;
    if (!ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(c.musicError ?? 'Could not skip')),
        );
      return;
    }
    await Future.delayed(
      const Duration(milliseconds: 800),
    ); // let Spotify catch up
    if (mounted) _load();
  }

  Widget _art(SpotifyHit hit) {
    final fallback = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        size: 20,
        color: Colors.white54,
      ),
    );
    final url = hit.imageUrl;
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Image.network(
        url,
        width: 42,
        height: 42,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ),
  );

  Widget _row(
    SpotifyHit hit, {
    required VoidCallback? onTap,
    bool playing = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          children: [
            _art(hit),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: playing ? const Color(0xFF30D158) : Colors.white,
                    ),
                  ),
                  if (hit.subtitle.isNotEmpty)
                    Text(
                      hit.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
            if (playing)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.graphic_eq,
                  size: 18,
                  color: Color(0xFF30D158),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _queue;
    return Material(
      color: const Color(
        0xFF0B0B0D,
      ), // opaque, so the card behind does not ghost through
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Queue',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh queue',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    widget.onTouch?.call();
                    _load();
                  },
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                IconButton(
                  tooltip: 'Close queue',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 22),
                ),
              ],
            ),
            Expanded(
              child: q == null
                  ? Center(
                      child: _loading
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                _error ?? 'Nothing in the queue',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white60),
                              ),
                            ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (_) {
                        widget.onTouch?.call(); // scrolling counts as using it
                        return false;
                      },
                      child: ListView(
                        padding: const EdgeInsets.only(right: 8),
                        children: [
                          if (q.now != null) ...[
                            _label('Now playing'),
                            _row(q.now!, onTap: null, playing: true),
                          ],
                          _label('Next in queue'),
                          if (q.next.isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
                              child: Text(
                                'Queue is empty',
                                style: TextStyle(color: Colors.white38),
                              ),
                            ),
                          for (var i = 0; i < q.next.length; i++)
                            _row(q.next[i], onTap: () => _skipTo(i, q.next[i])),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
