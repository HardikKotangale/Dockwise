import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/key_capture.dart';
import '../../../services/spotify_service.dart';
import '../../../state/standby_controller.dart';
import 'key_caps.dart';
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
  bool _keyboard = !onComputer;
  int _sel = 0; // computer: the row Enter plays
  bool _help = false; // computer: F1 (or ? in an empty box) shows the keys
  final _rowKeys = <int, GlobalKey>{};
  late final _fieldFocus = FocusNode(onKeyEvent: (_, e) => _computerKey(e));
  String? _error;
  int _seq = 0; // ignore answers that arrive after a newer search started

  StandbyController get c => widget.controller;

  // Esc goes back to the music card, with or without our keyboard showing
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onEsc);
    _fieldFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  bool _onEsc(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    Navigator.of(context).pop();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onEsc);
    _fieldFocus.dispose();
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
      _sel = 0;
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        const Text(
          'Search Spotify',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
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
                    color: empty ? Colors.white60 : Colors.white,
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

  // ---- a computer: one centred column, like Spotlight ----

  KeyEventResult _computerKey(KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    // ? is a letter you may want to search for, so it only asks for the keys
    // while the box is still empty; F1 always does
    if (e is KeyDownEvent &&
        (k == LogicalKeyboardKey.f1 ||
            (_text.text.isEmpty &&
                (k == LogicalKeyboardKey.question ||
                    k == LogicalKeyboardKey.slash)))) {
      setState(() => _help = !_help);
      return KeyEventResult.handled;
    }
    if (_hits.isEmpty) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _sel = (_sel + (k == LogicalKeyboardKey.arrowDown ? 1 : -1))
            .clamp(0, _hits.length - 1),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _rowKeys[_sel]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 120),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent &&
        (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter)) {
      final hit = _hits[_sel.clamp(0, _hits.length - 1)];
      if (HardwareKeyboard.instance.isShiftPressed && hit.kind == 'track') {
        _queue(hit);
      } else {
        _play(hit);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _computerField() => Focus(
    canRequestFocus: false,
    child: Builder(
      builder: (context) {
        final focused = _fieldFocus.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: focused ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused
                  ? Colors.white.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.06),
                      blurRadius: 28,
                    ),
                  ]
                : const [],
          ),
          child: TextField(
            key: const ValueKey('search-field'),
            controller: _text,
            focusNode: _fieldFocus,
            autofocus: true,
            cursorColor: const Color(0xFF1DB954),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.3,
            ),
            onChanged: (_) {
              setState(() {});
              _changed();
            },
            decoration: InputDecoration(
              hintText: 'Songs, albums, playlists',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.search_rounded,
                  size: 26,
                  color: Colors.white54,
                ),
              ),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _text.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.cancel_rounded, size: 22),
                      color: Colors.white38,
                      onPressed: () {
                        _clear();
                        setState(() {});
                      },
                    ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        );
      },
    ),
  );

  Widget _computerRow(int i) {
    final hit = _hits[i];
    final sel = i == _sel;
    final sub = hit.kind == 'track'
        ? hit.subtitle
        : '${hit.kind == 'album' ? 'Album' : 'Playlist'}'
              '${hit.subtitle.isEmpty ? '' : ' · ${hit.subtitle}'}';
    return MouseRegion(
      onEnter: (_) {
        if (_sel != i) setState(() => _sel = i);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _play(hit),
        child: AnimatedContainer(
          key: _rowKeys.putIfAbsent(i, GlobalKey.new),
          duration: const Duration(milliseconds: 110),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: sel
                ? Colors.white.withValues(alpha: 0.09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _art(hit),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              // what Enter does for this row, only on the one it will act on
              AnimatedOpacity(
                duration: const Duration(milliseconds: 110),
                opacity: sel ? 1 : 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hit.kind == 'track') ...[
                      Tooltip(
                        message: 'Add to queue (Shift + Enter)',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _queue(hit),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.playlist_add_rounded,
                              size: 24,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const KeyCap('↵', lit: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _computerResults() {
    if (_error != null && _hits.isEmpty) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 16),
        ),
      );
    }
    if (_hits.isEmpty) {
      return Center(
        child: _loading
            ? const SizedBox.shrink()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _searched
                        ? Icons.search_off_rounded
                        : Icons.graphic_eq_rounded,
                    size: 44,
                    color: Colors.white24,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _searched ? 'No results' : 'Search Spotify',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _searched
                        ? 'Try another word or a different spelling.'
                        : 'Find a song, an album or a playlist and play it here.',
                    style: const TextStyle(fontSize: 15, color: Colors.white38),
                  ),
                ],
              ),
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 12),
        children: [
          for (var i = 0; i < _hits.length; i++) ...[
            if (i == 0 || _hits[i].kind != _hits[i - 1].kind)
              Padding(
                padding: EdgeInsets.fromLTRB(10, i == 0 ? 6 : 22, 10, 6),
                child: Text(
                  _kindLabel(_hits[i].kind),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            _computerRow(i),
          ],
        ],
      ),
    );
  }

  Widget _computerPage() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 18),
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Search Spotify',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _computerField(),
            const SizedBox(height: 8),
            Expanded(child: _computerResults()),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _help
                    ? const Padding(
                        key: ValueKey('help'),
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 22,
                          runSpacing: 8,
                          children: [
                            KeyHint(
                              keys: ['↑', '↓'],
                              label: 'choose',
                              range: true,
                            ),
                            KeyHint(keys: ['↵'], label: 'play'),
                            KeyHint(keys: ['⇧', '↵'], label: 'add to queue'),
                            KeyHint(keys: ['esc'], label: 'close'),
                          ],
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('none'),
                        height: 14,
                        width: 1,
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

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
        // a 300 px picture shrunk to a thumbnail: mipmaps keep it smooth
        filterQuality: FilterQuality.medium,
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
                style: const TextStyle(color: Colors.white60, fontSize: 16),
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
                    fontWeight: FontWeight.w600,
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
    if (onComputer) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _computerPage()),
      );
    }
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
                    child: _keys(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
