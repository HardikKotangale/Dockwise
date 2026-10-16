import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/apple.dart';
import '../../../domain/standby_models.dart';
import '../../../services/spotify_service.dart' show SpotifyDevice;
import 'music_controls.dart';

/// Now-playing card: album art fills the card, text and controls sit on a
/// dark gradient, and everything scales with the card's size.
class MusicCard extends StatefulWidget {
  const MusicCard({
    super.key,
    required this.snapshot,
    required this.settings,
    required this.onCommand,
    this.onSeek,
    this.volumeBar,
    this.onSearch,
    this.queueView,
    this.currentSource = 'auto',
    this.onSource,
    this.loadDevices,
    this.onDevice,
    this.nextUp,
    this.onLink,
  });

  /// Shown as a button when nothing can be played yet because Spotify is not
  /// linked (an iPhone before sign-in): opens the way to link it.
  final VoidCallback? onLink;

  /// Asked for when the Next button is held: the name of the song after this
  /// one, shown in a glass label; null when it cannot be known.
  final Future<String?> Function()? nextUp;

  /// The Spotify devices you can play on (a MacBook, a speaker...), asked for
  /// when the source menu opens; null when Spotify is not connected.
  final Future<List<SpotifyDevice>> Function()? loadDevices;

  /// Play on the device with this id.
  final ValueChanged<String>? onDevice;

  /// Where the song comes from: 'auto' follows whatever Spotify is playing
  /// or this phone; the source menu lists the Spotify devices to pick from.
  final String currentSource;
  final ValueChanged<String>? onSource;

  final NowPlayingSnapshot snapshot;
  final StandbySettings settings;
  final Future<bool> Function(String command) onCommand;

  /// Press-and-hold on the progress bar, drag, release: jump to that point.
  final Future<bool> Function(int positionMs)? onSeek;

  /// A volume bar to show over the card (built with a callback that keeps it
  /// open while touched); null = this source has no volume control here.
  final Widget Function(VoidCallback keepOpen)? volumeBar;

  /// Opens Spotify search; null when Spotify is not connected.
  final VoidCallback? onSearch;

  /// The play queue shown inside the card (built with callbacks to close it and
  /// to keep it open while touched); null when Spotify is not connected.
  final Widget Function(VoidCallback close, VoidCallback keepOpen)? queueView;

  @override
  State<MusicCard> createState() => _MusicCardState();
}

class _MusicCardState extends State<MusicCard> {
  Timer? _tick;
  double? _scrub; // 0..1 while the bar is held; null otherwise
  bool _showVolume = false;
  Timer? _hideVolume;
  bool _showQueue = false;
  Timer? _hideQueue;

  // The volume bar closes by itself a few seconds after the last touch.
  // The queue closes by itself after a while without a touch (it is an
  // ambient display, so it goes back to the now-playing view on its own).
  void _keepQueueOpen() {
    _hideQueue?.cancel();
    _hideQueue = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _showQueue = false);
    });
  }

  void _closeQueue() {
    _hideQueue?.cancel();
    setState(() => _showQueue = false);
  }

  void _keepVolumeOpen() {
    _hideVolume?.cancel();
    _hideVolume = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showVolume = false);
    });
  }

  NowPlayingSnapshot get snapshot => widget.snapshot;
  StandbySettings get settings => widget.settings;
  Future<bool> Function(String) get onCommand => widget.onCommand;

  // Battery: tick once a second, only while a song is playing.
  void _syncTick() {
    if (snapshot.isPlaying && snapshot.fetchedAt != null) {
      _tick ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncTick();
  }

  @override
  void didUpdateWidget(MusicCard old) {
    super.didUpdateWidget(old);
    _syncTick();
  }

  @override
  void dispose() {
    _hideVolume?.cancel();
    _hideQueue?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  // Progress bar. Press and hold, drag to a point, release to jump there. A
  // long press (not a drag) so it never fights the swipe that changes widgets.
  /// secondary icons: the accent when one is picked, else the usual soft white
  Color get _tone => widget.settings.musicColor == 0 ? Colors.white70 : _ink;

  // the card's own colour when one is picked (progress, buttons), else white
  Color get _ink => widget.settings.musicColor == 0
      ? Colors.white
      : Color(widget.settings.musicColor);

  Widget _bar(double progress, int position) {
    final canSeek = widget.onSeek != null && snapshot.durationMs > 0;
    final scrubbing = _scrub != null;
    final shown = _scrub ?? progress;
    final shownMs = scrubbing
        ? (_scrub! * snapshot.durationMs).round()
        : position;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double frac(Offset p) => (p.dx / w).clamp(0.0, 1.0);
        void update(Offset p) => setState(() => _scrub = frac(p));
        return Semantics(
          label: 'Song position. Press and hold, then drag to seek',
          // Hold for just 220 ms (Flutter's default is 500 ms) before scrubbing.
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(() => LongPressGestureRecognizer(duration: _holdToSeek), (
                    r,
                  ) {
                    r.onLongPressStart = canSeek
                        ? (d) {
                            HapticFeedback.mediumImpact();
                            update(d.localPosition);
                          }
                        : null;
                    r.onLongPressMoveUpdate = canSeek
                        ? (d) => update(d.localPosition)
                        : null;
                    r.onLongPressEnd = canSeek
                        ? (d) {
                            final f = frac(d.localPosition);
                            setState(() => _scrub = null);
                            widget.onSeek!((f * snapshot.durationMs).round());
                          }
                        : null;
                    r.onLongPressCancel = () => setState(() => _scrub = null);
                  }),
            },
            child: Column(
              children: [
                SizedBox(
                  height: 30,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        height: scrubbing ? 9 : 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: shown,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          height: scrubbing ? 9 : 4,
                          decoration: BoxDecoration(
                            color: _ink,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      if (scrubbing)
                        Positioned(
                          left: (shown * w - 11).clamp(-4.0, w - 18),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _ink,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (snapshot.durationMs > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _mmss(shownMs),
                        style: scrubbing
                            ? _timeStyle.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              )
                            : _timeStyle,
                      ),
                      Text(_mmss(snapshot.durationMs), style: _timeStyle),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static IconData _deviceIcon(String type) => switch (type.toLowerCase()) {
    'computer' => Icons.laptop_mac_rounded,
    'smartphone' => Icons.smartphone_rounded,
    'tablet' => Icons.tablet_mac_rounded,
    'speaker' => Icons.speaker_rounded,
    'tv' => Icons.tv_rounded,
    'castaudio' || 'castvideo' => Icons.cast_rounded,
    _ => Icons.devices_other_rounded,
  };

  // Tap the source: choose Auto, a Spotify device (your MacBook, a speaker...)
  // like AirPlay's device list.
  Future<void> _openSourceMenu(BuildContext anchor) async {
    _keepQueueOpen();
    var devices = const <SpotifyDevice>[];
    if (widget.loadDevices != null) {
      try {
        devices = await widget.loadDevices!().timeout(
          const Duration(seconds: 3),
          onTimeout: () => const <SpotifyDevice>[],
        );
      } catch (_) {}
    }
    if (!mounted || !anchor.mounted) return;
    final box = anchor.findRenderObject() as RenderBox;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    const label = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.2,
    );
    PopupMenuItem<String> item(
      String value,
      String text, {
      IconData? icon,
      bool checked = false,
    }) => PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: checked ? const Icon(Icons.check_rounded, size: 18) : null,
          ),
          if (icon != null) ...[
            Icon(icon, size: 20, color: Colors.white70),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              text,
              style: label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    final choice = await showMenu<String>(
      context: anchor,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      color: const Color(0xF22C2C2E),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      items: [
        item('auto', 'Auto', checked: widget.currentSource == 'auto'),
        if (devices.isNotEmpty) ...[
          const PopupMenuDivider(height: 8),
          const PopupMenuItem<String>(
            enabled: false,
            height: 28,
            child: Text(
              'Play on',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final d in devices)
            item(
              'dev:${d.id}',
              d.name,
              icon: _deviceIcon(d.type),
              checked: d.isActive,
            ),
        ],
      ],
    );
    if (choice == null) return;
    tick();
    if (choice.startsWith('dev:')) {
      widget.onDevice?.call(choice.substring(4));
    } else {
      widget.onSource?.call(choice);
    }
  }

  // The source label ("Spotify · MacBook Pro"). When there is something to
  // choose from it is a button that opens the device menu.
  Widget _sourceLabel() {
    final text = Text(
      snapshot.isControllable
          ? snapshot.source
          : widget.onLink != null
          ? 'Spotify not linked'
          : 'Nothing playing',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
    );
    final choosable = widget.onSource != null && widget.loadDevices != null;
    if (!choosable) return text;
    return Align(
      alignment: Alignment.centerLeft,
      child: Builder(
        builder: (anchor) => Pressable(
          scale: 0.95,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openSourceMenu(anchor),
            child: Semantics(
              button: true,
              label: 'Music source',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: text),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final position = snapshot.positionAt(now);
    final progress = snapshot.durationMs > 0
        ? (position / snapshot.durationMs).clamp(0.0, 1.0)
        : snapshot.progress;
    final art = coverArt(snapshot);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        final unit = math.min(w, h);
        final tall = h >= 300;
        // Buttons grow with the card but stay finger-sized.
        final pad = (unit / 18).clamp(14.0, 28.0);
        // Narrow card (e.g. settings dock open): drop the 10s buttons so
        // previous / play / next always fit.
        final compact = w < 300;
        final button = math
            .min((w - 2 * pad) / (compact ? 4.2 : 6.2), h / 4)
            .clamp(40.0, 88.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            // The cover as a soft, blurred backdrop (like Apple Music); the sharp
            // cover itself sits in the card when there is room for it.
            RepaintBoundary(
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: art == null
                      ? ImageFilter.blur()
                      : ImageFilter.blur(
                          sigmaX: 18,
                          sigmaY: 18,
                          tileMode: TileMode.mirror,
                        ),
                  child: Transform.scale(
                    scale: art == null ? 1 : 1.2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        image: art,
                        gradient: art == null
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  settings.appAccentInk,
                                  Color.lerp(
                                    settings.appAccentInk,
                                    Colors.black,
                                    0.6,
                                  )!,
                                ],
                              )
                            : null,
                      ),
                      child: null,
                    ),
                  ),
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.35, 1.0],
                  colors: [Colors.black26, Colors.black12, Colors.black87],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tall)
                    Row(
                      children: [
                        Icon(Icons.graphic_eq, size: 16, color: _tone),
                        const SizedBox(width: 6),
                        Expanded(child: _sourceLabel()),
                        if (widget.queueView != null)
                          IconButton(
                            tooltip: 'Up next',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 36,
                              height: 36,
                            ),
                            onPressed: () {
                              setState(() => _showQueue = true);
                              _keepQueueOpen();
                            },
                            icon: Icon(
                              Icons.queue_music_rounded,
                              size: 22,
                              color: _tone,
                            ),
                          ),
                        if (widget.onSearch != null)
                          IconButton(
                            tooltip: 'Search Spotify',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 36,
                              height: 36,
                            ),
                            onPressed: widget.onSearch,
                            icon: Icon(
                              Icons.search_rounded,
                              size: 22,
                              color: _tone,
                            ),
                          ),
                        if (widget.volumeBar != null)
                          IconButton(
                            tooltip: 'Volume',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 36,
                              height: 36,
                            ),
                            onPressed: () {
                              setState(() => _showVolume = !_showVolume);
                              _showVolume
                                  ? _keepVolumeOpen()
                                  : _hideVolume?.cancel();
                            },
                            icon: Icon(
                              Icons.volume_up_rounded,
                              size: 22,
                              color: _tone,
                            ),
                          ),
                      ],
                    ),
                  // The sharp cover, as large as the room left allows (and the same
                  // in the Summary panel, which shows this very card).
                  if (tall)
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, room) {
                          final side = math.min(
                            room.maxHeight - 16,
                            room.maxWidth,
                          );
                          if (side < 72) return const SizedBox.shrink();
                          return Center(
                            child: SizedBox.square(
                              dimension: side,
                              child: AlbumCover(art: art),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    const Spacer(),
                  // a new song slides its name in; the old one eases out
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : Motion.medium,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.bottomLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Column(
                      key: ValueKey('${snapshot.title}|${snapshot.artist}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snapshot.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: (unit / 12).clamp(18.0, 32.0),
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        // the "link Spotify" explanation is a sentence: on a narrow
                        // card (two panels, or one panel in portrait) it wraps
                        // to the next line instead of being cut off
                        LayoutBuilder(
                          builder: (context, box) => Text(
                            snapshot.artist,
                            maxLines:
                                widget.onLink != null &&
                                    !snapshot.isControllable &&
                                    box.maxWidth < 560
                                ? 3
                                : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: (unit / 18).clamp(13.0, 20.0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (widget.onLink != null && !snapshot.isControllable)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            // arrives a beat after the words, with a small overshoot
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: calm(
                                context,
                                const Duration(milliseconds: 900),
                              ),
                              curve: const Interval(
                                0.35,
                                1,
                                curve: Curves.easeOutBack,
                              ),
                              builder: (context, v, child) => Opacity(
                                opacity: v.clamp(0.0, 1.0),
                                child: Transform.scale(
                                  scale: 0.85 + 0.15 * v,
                                  alignment: Alignment.centerLeft,
                                  child: child,
                                ),
                              ),
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF1DB954),
                                  foregroundColor: Colors.black,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () {
                                  tick();
                                  widget.onLink!();
                                },
                                icon: const Icon(Icons.link_rounded, size: 18),
                                label: const Text('Link Spotify'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: pad * 0.6),
                  _bar(progress, position),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (!compact)
                        TransportButton(
                          icon: Icons.replay_10_rounded,
                          label: 'Back 10 seconds',
                          size: button,
                          tint: _ink,
                          onPressed: () => onCommand('back10'),
                        ),
                      TransportButton(
                        icon: Icons.skip_previous_rounded,
                        nudge: -1,
                        label: 'Previous',
                        size: button,
                        tint: _ink,
                        onPressed: () => onCommand('previous'),
                      ),
                      TransportButton(
                        icon: Icons.play_arrow_rounded,
                        playing: snapshot.isPlaying,
                        label: snapshot.isPlaying ? 'Pause' : 'Play',
                        size: button * 1.2,
                        filled: true,
                        tint: _ink,
                        onPressed: () => onCommand('playPause'),
                      ),
                      TransportButton(
                        icon: Icons.skip_next_rounded,
                        nudge: 1,
                        label: 'Next',
                        holdLabel: 'Next',
                        loadHoldLabel: widget.nextUp,
                        size: button,
                        tint: _ink,
                        onPressed: () => onCommand('next'),
                      ),
                      if (!compact)
                        TransportButton(
                          icon: Icons.forward_10_rounded,
                          label: 'Forward 10 seconds',
                          size: button,
                          tint: _ink,
                          onPressed: () => onCommand('forward10'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.queueView != null && _showQueue)
              Positioned.fill(
                child: widget.queueView!(_closeQueue, _keepQueueOpen),
              ),
            if (widget.volumeBar != null)
              Positioned(
                left: pad,
                right: pad,
                top: pad - 6,
                child: IgnorePointer(
                  ignoring: !_showVolume,
                  child: Materialize(
                    visible: _showVolume,
                    child: _showVolume
                        ? widget.volumeBar!(_keepVolumeOpen)
                        : const SizedBox(height: 48),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// How long to hold the progress bar before it starts scrubbing.
const _holdToSeek = Duration(milliseconds: 220);

const _timeStyle = TextStyle(fontSize: 12, color: Colors.white70);

String _mmss(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
