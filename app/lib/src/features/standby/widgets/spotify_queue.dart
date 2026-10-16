import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/palette.dart';
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
    this.onSearch,
  });

  final StandbyController controller;
  final VoidCallback onClose;

  /// Called on every touch so the card keeps the view open while it is used.
  final VoidCallback? onTouch;

  /// Opens Spotify search (to find a song to add); the header shows a search
  /// button when this is set.
  final VoidCallback? onSearch;

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
    _commit?.cancel();
    _stopAuto();
    _scroll.dispose();
    super.dispose();
  }

  Timer? _commit;
  bool _dirty = false; // a new order not yet sent: do not overwrite it

  void _reorder(int from, int to) {
    final q = _queue;
    if (q == null) return;
    if (to == from) return;
    final next = [...q.next];
    next.insert(to, next.removeAt(from));
    widget.onTouch?.call();
    setState(() {
      _queue = SpotifyQueue(q.now, next);
      _dirty = true;
    });
    // several moves in a row become one call
    _commit?.cancel();
    _commit = Timer(const Duration(milliseconds: 500), _send);
  }

  void _send() {
    final q = _queue;
    if (q == null || q.now == null) return;
    c.reorderSpotifyQueue(q.now!, q.next); // takes effect when the song ends
    _dirty = false;
  }

  Future<void> _load() async {
    if (_dirty) return;
    final q = await c.spotifyQueue();
    if (!mounted || _dirty) return;
    setState(() {
      _queue = q ?? _queue; // keep the old list on screen if a refresh fails
      _loading = false;
      _error = q == null ? c.musicError : null;
    });
  }

  Future<void> _skipTo(int index, SpotifyHit hit) async {
    widget.onTouch?.call();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await c.skipInQueue(index, _queue!.next);
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
    if (mounted) unawaited(_load());
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
        // a 300 px picture shrunk to a thumbnail: mipmaps keep it smooth
        filterQuality: FilterQuality.medium,
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
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    ),
  );

  Widget _row(
    SpotifyHit hit, {
    required VoidCallback? onTap,
    bool playing = false,
    Widget? handle,
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
                      color: playing ? Palette.green : Colors.white,
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
                child: Icon(Icons.graphic_eq, size: 18, color: Palette.green),
              ),
            ?handle,
          ],
        ),
      ),
    );
  }

  final _listKey = GlobalKey();
  final _scroll = ScrollController();
  Timer? _auto;
  Offset? _dragAt;

  // while a song is held near the top or bottom edge, the list scrolls
  void _startAuto() {
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final at = _dragAt;
      final box = _listKey.currentContext?.findRenderObject();
      if (at == null || box is! RenderBox || !_scroll.hasClients) return;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      final edge = (bottom - top) * 0.18;
      var step = 0.0;
      if (at.dy < top + edge) step = -12;
      if (at.dy > bottom - edge) step = 12;
      if (step == 0) return;
      final p = _scroll.position;
      _scroll.jumpTo(
        (p.pixels + step).clamp(p.minScrollExtent, p.maxScrollExtent),
      );
    });
  }

  void _stopAuto() {
    _auto?.cancel();
    _auto = null;
    _dragAt = null;
  }

  Widget _draggableRow(int i, SpotifyHit hit) {
    const handle = Padding(
      padding: EdgeInsets.all(8),
      child: Icon(Icons.drag_handle_rounded, size: 22, color: Colors.white38),
    );
    final row = _row(hit, onTap: () => _skipTo(i, hit), handle: handle);
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != i,
      onAcceptWithDetails: (d) => _reorder(d.data, i),
      builder: (context, over, _) => LayoutBuilder(
        builder: (context, box) => LongPressDraggable<int>(
          data: i,
          delay: const Duration(milliseconds: 150),
          onDragStarted: () {
            widget.onTouch?.call();
            _startAuto();
          },
          onDragUpdate: (d) => _dragAt = d.globalPosition,
          onDragEnd: (_) => _stopAuto(),
          feedback: Material(
            color: const Color(0xFF1C1C1F),
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: box.maxWidth,
              child: _row(hit, onTap: null, handle: handle),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: row),
          child: DecoratedBox(
            // the song you are over: a line where the dragged one will go
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: over.isEmpty ? Colors.transparent : Palette.green,
                  width: 2,
                ),
              ),
            ),
            child: row,
          ),
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                if (widget.onSearch != null)
                  IconButton(
                    tooltip: 'Search Spotify',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onSearch,
                    icon: const Icon(Icons.search_rounded, size: 22),
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
                      // Songs are reordered by drag and drop (not Flutter's
                      // reorderable list): that one floats the dragged row at
                      // the wrong place once the whole app is scaled to a big
                      // screen (see ScreenFit).
                      child: ListView.builder(
                        key: _listKey,
                        controller: _scroll,
                        padding: const EdgeInsets.only(right: 8),
                        itemCount: q.next.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                      style: TextStyle(color: Colors.white60),
                                    ),
                                  ),
                              ],
                            );
                          }
                          return _draggableRow(i - 1, q.next[i - 1]);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
