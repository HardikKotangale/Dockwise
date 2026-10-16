import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../domain/standby_models.dart';
import '../../../services/photo_service.dart';

/// The photo slideshow card: one picture at a time, each fading into the next
/// while it drifts slowly, like a frame on a shelf. [feed] is null until a
/// source is chosen; tapping the empty card goes to the settings.
class PhotosCard extends StatefulWidget {
  const PhotosCard({
    super.key,
    required this.feed,
    required this.settings,
    this.onSetup,
    this.steps,
    this.compact = false,
    this.problem,
  });

  final PhotoFeed? feed;
  final StandbySettings settings;

  /// the empty card was tapped: choose where the pictures come from
  final VoidCallback? onSetup;

  /// (direction, count): a key moved the slideshow one picture on or back
  final ValueListenable<(int, int)>? steps;

  /// a small tile (Summary): the picture only, no hint text
  final bool compact;

  /// why there is no picture (permission off, folder gone), shown on the card
  final String? problem;

  @override
  State<PhotosCard> createState() => _PhotosCardState();
}

class _Shot {
  _Shot(this.index, this.bytes);
  final int index;
  final Uint8List bytes;
}

class _PhotosCardState extends State<PhotosCard> {
  Timer? _timer;
  _Shot? _shot;
  int _next = 0;
  bool _loading = false;
  Size _size = const Size(800, 600);
  double _dpr = 1;

  @override
  void initState() {
    super.initState();
    widget.steps?.addListener(_stepped);
    _restart();
  }

  @override
  void didUpdateWidget(PhotosCard old) {
    super.didUpdateWidget(old);
    if (old.steps != widget.steps) {
      old.steps?.removeListener(_stepped);
      widget.steps?.addListener(_stepped);
    }
    if (!identical(old.feed, widget.feed)) {
      _shot = null;
      _next = 0;
      _restart();
    } else if (old.settings.photoSeconds != widget.settings.photoSeconds) {
      _arm();
    }
  }

  @override
  void dispose() {
    widget.steps?.removeListener(_stepped);
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if ((widget.feed?.length ?? 0) == 0) return;
    unawaited(_show(0));
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    final seconds = widget.settings.photoSeconds.clamp(3, 600);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => _advance(1));
  }

  void _stepped() {
    _advance(widget.steps!.value.$1);
    _arm(); // a picture you moved to stays its full time
  }

  void _advance(int dir) {
    final n = widget.feed?.length ?? 0;
    if (n == 0 || !mounted) return;
    unawaited(_show((((_next + dir) % n) + n) % n, dir));
  }

  // shows picture [i]; one that cannot be read is skipped, going on the way
  // [dir] says
  Future<void> _show(int i, [int dir = 1]) async {
    final feed = widget.feed;
    if (feed == null || feed.length == 0 || _loading) return;
    _loading = true;
    try {
      final n = feed.length;
      final px = (math.max(_size.width, _size.height) * _dpr).round().clamp(
        400,
        2400,
      );
      for (var tries = 0; tries < math.min(n, 5); tries++) {
        final at = ((i + tries * dir) % n + n) % n;
        final bytes = await feed.bytes(at, px);
        if (!mounted || !identical(feed, widget.feed)) return;
        if (bytes != null) {
          setState(() {
            _shot = _Shot(at, bytes);
            _next = at;
          });
          return;
        }
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _dpr = MediaQuery.devicePixelRatioOf(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final shot = _shot;
    return LayoutBuilder(
      builder: (context, c) {
        _size = Size(c.maxWidth, c.maxHeight);
        return ClipRect(
          child: ColoredBox(
            color: Colors.black,
            child: shot == null ? _empty() : _picture(shot, still),
          ),
        );
      },
    );
  }

  Widget _picture(_Shot shot, bool still) => AnimatedSwitcher(
    duration: still ? Duration.zero : const Duration(milliseconds: 1400),
    switchInCurve: Curves.easeInOut,
    switchOutCurve: Curves.easeInOut,
    layoutBuilder: (current, previous) =>
        Stack(fit: StackFit.expand, children: [...previous, ?current]),
    child: _Drift(
      key: ValueKey(shot),
      seconds: widget.settings.photoSeconds,
      still: still,
      child: Image.memory(
        shot.bytes,
        fit: widget.settings.photoFill ? BoxFit.cover : BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    ),
  );

  Widget _empty() {
    final size = widget.compact ? 13.0 : 18.0;
    final text =
        widget.problem ??
        (widget.feed == null
            ? 'Choose the pictures to show'
            : 'No pictures found there');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSetup,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  color: Colors.white54,
                  size: size * 2.4,
                ),
                SizedBox(height: size * 0.6),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: size),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A slow zoom while a picture shows, so the card is never still.
class _Drift extends StatefulWidget {
  const _Drift({
    super.key,
    required this.child,
    required this.seconds,
    required this.still,
  });

  final Widget child;
  final int seconds;
  final bool still;

  @override
  State<_Drift> createState() => _DriftState();
}

class _DriftState extends State<_Drift> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.seconds.clamp(3, 600) + 2),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.still) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) => Transform.scale(
      scale: 1 + 0.06 * Curves.easeOut.transform(_c.value),
      child: child,
    ),
    child: widget.child,
  );
}
