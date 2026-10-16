import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../../core/apple.dart';
import '../../../core/motion/dissolve.dart';
import '../../../core/palette.dart';
import '../../../domain/standby_models.dart';
import '../../../domain/summary_layout.dart';
import 'calendar_card.dart';
import 'clock/dial_painter.dart';
import 'clock_faces.dart';

/// One panel that answers what you look at a bedside clock for: the time here
/// and in a second city, today's date, the weather, and what is playing with
/// its controls. It lays itself out from the panel's shape: three columns when
/// it is wide, stacked rows when it is narrow or tall.
///
/// Like the iOS home screen: hold a tile and they all start to jiggle; drag
/// one onto another to swap them (drag the music tile to a column to move
/// it), then tap Done. Tapping the second city opens the city search.
class SummaryCard extends StatefulWidget {
  const SummaryCard({
    super.key,
    required this.now,
    required this.settings,
    required this.weather,
    required this.music,
    this.timer = const SizedBox.shrink(),
    this.onWeatherSwipe,
    this.onDateSwipe,
    this.onClockSwipe,
    this.onTileHover,
    this.onClockTap,
    this.onOpenCalendar,
    this.onLayout,
    this.onCityTap,
    this.onOpenMusic,
    this.onAddTile,
    this.onOpenWeather,
    this.onEditing,
  });

  final DateTime now;
  final StandbySettings settings;

  /// The weather card itself (the one the Weather panel shows), so the tile
  /// swipes through the same four pages: now, Fahrenheit, forecast, second city.
  final Widget weather;

  /// Swiped up (+1) or down (-1) on the weather tile.
  final ValueChanged<int>? onWeatherSwipe;

  /// Swiped up or down on the date tile: Today and Month, as on the card.
  final VoidCallback? onDateSwipe;

  /// A swipe up or down on a time tile: the next or previous look (1 or -1).
  /// step (1 / -1) and whether it was the second city's tile
  final void Function(int step, bool second)? onClockSwipe;

  /// the pointer entered (true) or left (false) a tile
  final void Function(SummaryTile tile, bool over)? onTileHover;

  /// a tap on a time tile: its settings
  /// a tap on the calendar tile
  final VoidCallback? onOpenCalendar;

  /// a tap on one of the two clock tiles (which one)
  final void Function(SummaryTile tile)? onClockTap;

  /// A tap on the music or weather tile opens that card's settings.
  final VoidCallback? onOpenMusic;
  final VoidCallback? onOpenWeather;

  /// The now-playing card itself (the one the Music panel shows), so Summary
  /// has all of its controls: seek, devices, volume, queue and search.
  final Widget music;

  /// The timer tile (time left, a mini track and three buttons).
  final Widget timer;

  /// The "+" tile was tapped: choose a widget to add.
  final VoidCallback? onAddTile;

  /// Called with the new arrangement (as [SummaryLayout.encode]) after a drop.
  final ValueChanged<String>? onLayout;

  /// The second city was tapped: go and choose another.
  final VoidCallback? onCityTap;

  /// Editing started or ended (so the screen can stop swipes while dragging).
  final ValueChanged<bool>? onEditing;

  @override
  State<SummaryCard> createState() => _SummaryCardState();
}

const _musicId = 'music';

class _SummaryCardState extends State<SummaryCard>
    with TickerProviderStateMixin {
  static const _gap = 10.0;

  bool _editing = false;

  // Where the "+" has been dragged to while rearranging: the place (in the
  // list of widgets) a new widget will take when it is added.
  int? _plusPref;

  // drives the jiggle; only runs while editing
  late final AnimationController _jiggle = AnimationController(
    vsync: this,
    duration: Motion.quick,
  );

  // The tiles deal in one after another when Summary appears, like little
  // cards being laid down: each rises, grows and fades in, a beat apart.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void didUpdateWidget(SummaryCard old) {
    super.didUpdateWidget(old);
    final was = SummaryLayout.parse(old.settings.summaryLayout).tiles;
    final now = _layout.tiles;
    final at = _plusPref;
    if (!_editing || at == null || now.length != was.length + 1) return;
    // the one that just arrived: it is added at the end (or where it fits);
    // move it to where the "+" was put
    final fresh = now.firstWhere((t) => !was.contains(t));
    final list = [...now]
      ..remove(fresh)
      ..insert(at.clamp(0, now.length - 1), fresh);
    final next = SummaryLayout(list);
    if (next.fits && next != _layout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLayout?.call(next.encode());
      });
    }
  }

  // The "+" dropped on a tile: it takes that tile's place, and the tile
  // moves one place on. Ignored when the panel would not fit.
  void _movePlus(String target) {
    final real = [for (final t in _layout.tiles) t.name];
    final at = real.indexOf(target);
    if (at < 0) return;
    final tryIds = [...real]..insert(at, _plusId);
    if (SummaryLayout.pack(tryIds, (id) => id == _musicId).length >
        SummaryLayout.maxColumns) {
      return;
    }
    tick();
    setState(() => _plusPref = at);
  }

  SummaryLayout get _layout =>
      SummaryLayout.parse(widget.settings.summaryLayout);

  @override
  void dispose() {
    // leaving while editing must not leave the screen thinking a tile is still
    // being dragged (that would stop every swipe)
    if (_editing) widget.onEditing?.call(false);
    _enter.dispose();
    _jiggle.dispose();
    super.dispose();
  }

  void _setEditing(bool on) {
    if (_editing == on) return;
    setState(() {
      _editing = on;
      if (!on) _plusPref = null;
    });
    widget.onEditing?.call(on);
    if (on) {
      tick();
      if (!MediaQuery.disableAnimationsOf(context)) {
        _jiggle.repeat(reverse: true);
      }
    } else {
      _jiggle.stop();
    }
  }

  void _drop(String dragged, String target) {
    final layout = _layout;
    final a = SummaryTile.values.where((t) => t.name == dragged);
    final b = SummaryTile.values.where((t) => t.name == target);
    if (a.isEmpty || b.isEmpty) return;
    final next = layout.swap(a.first, b.first);
    if (next != layout) {
      tick();
      widget.onLayout?.call(next.encode());
    }
  }

  // tiles on their way out (the "-" was tapped): they shrink and fade, then go
  final _removing = <String>{};
  // tiles already on screen: a new one pops in, the first ones deal in
  final _seen = <String>{};

  // A tile dropped on the empty place ("+"): it moves there, and its old place
  // is the empty one now.
  void _moveToEmpty(String dragged, int plusAt, List<String> ids) {
    final tile = SummaryTile.values.where((t) => t.name == dragged);
    if (tile.isEmpty || plusAt < 0) return;
    final layout = _layout;
    final at = ids.take(plusAt).where((id) => id != dragged).length;
    final list = [...layout.tiles]
      ..remove(tile.first)
      ..insert(at, tile.first);
    final next = SummaryLayout(list);
    if (next.fits && next != layout) {
      tick();
      widget.onLayout?.call(next.encode());
    }
  }

  void _remove(String id) {
    tick();
    if (MediaQuery.disableAnimationsOf(context)) {
      _commitRemove(id);
    } else {
      setState(() => _removing.add(id));
    }
  }

  void _commitRemove(String id) {
    _removing.remove(id);
    final tile = SummaryTile.values.where((t) => t.name == id);
    if (tile.isEmpty) return;
    widget.onLayout?.call(_layout.without(tile.first).encode());
  }

  // swipe up = the next look, down = the one before (as on the Clock)
  void _clockSwipe(DragEndDetails d, {bool second = false}) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() > 300) widget.onClockSwipe?.call(v < 0 ? 1 : -1, second);
  }

  // the pointer over a tile makes the keys and the wheel work that tile
  Widget _tile(SummaryTile t) => MouseRegion(
    onEnter: (_) => widget.onTileHover?.call(t, true),
    onExit: (_) => widget.onTileHover?.call(t, false),
    child: _tileBody(t),
  );

  Widget _tileBody(SummaryTile t) => switch (t) {
    SummaryTile.here => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _editing ? null : () => widget.onClockTap?.call(SummaryTile.here),
      onVerticalDragEnd: _editing ? null : _clockSwipe,
      child: _HereTile(now: widget.now, settings: widget.settings),
    ),
    SummaryTile.there => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _editing
          ? null
          : (widget.onClockTap == null
                ? widget.onCityTap
                : () => widget.onClockTap!(SummaryTile.there)),
      onVerticalDragEnd: _editing ? null : (d) => _clockSwipe(d, second: true),
      child: _ThereTile(now: widget.now, settings: widget.settings),
    ),
    SummaryTile.date => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _editing ? null : widget.onOpenCalendar,
      onVerticalDragEnd: _editing
          ? null
          : (d) {
              if ((d.primaryVelocity ?? 0).abs() > 300) {
                widget.onDateSwipe?.call();
              }
            },
      child: _DateTile(now: widget.now, settings: widget.settings),
    ),
    SummaryTile.timer => ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: widget.timer,
    ),
    SummaryTile.music => ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: GestureDetector(
        onTap: _editing ? null : widget.onOpenMusic,
        child: widget.music,
      ),
    ),
    SummaryTile.weather => ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _editing ? null : widget.onOpenWeather,
        onVerticalDragEnd: _editing
            ? null
            : (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() > 300) widget.onWeatherSwipe?.call(v < 0 ? 1 : -1);
              },
        child: widget.weather,
      ),
    ),
  };

  // One tile in its slot: normally just the tile (hold to start editing); in
  // edit mode it jiggles, can be picked up, and is a place to drop onto.
  // What a screen reader can do with a tile instead of holding and dragging.
  Map<CustomSemanticsAction, VoidCallback> _tileActions(String id) {
    final tile = SummaryTile.values.where((t) => t.name == id);
    if (tile.isEmpty) return const {};
    final layout = _layout;
    final at = layout.tiles.indexOf(tile.first);
    void swapWith(int other) {
      final next = layout.swap(tile.first, layout.tiles[other]);
      if (next != layout) widget.onLayout?.call(next.encode());
    }

    return {
      if (at > 0)
        const CustomSemanticsAction(label: 'Move earlier'): () =>
            swapWith(at - 1),
      if (at >= 0 && at < layout.tiles.length - 1)
        const CustomSemanticsAction(label: 'Move later'): () =>
            swapWith(at + 1),
      const CustomSemanticsAction(label: 'Remove from Summary'): () =>
          _commitRemove(id),
    };
  }

  Widget _slot(String id, Widget content) {
    if (!_editing) {
      return Semantics(
        container: false,
        customSemanticsActions: _tileActions(id),
        child: GestureDetector(
          onLongPress: () => _setEditing(true),
          child: content,
        ),
      );
    }
    final phase = (id.hashCode % 7) / 7;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != id,
      onAcceptWithDetails: (d) =>
          d.data == _plusId ? _movePlus(id) : _drop(d.data, id),
      builder: (context, candidates, rejected) {
        final hot = candidates.isNotEmpty;
        return LayoutBuilder(
          builder: (context, c) {
            final shown = AnimatedBuilder(
              animation: _jiggle,
              builder: (context, child) {
                final t = (_jiggle.value + phase) % 1;
                final angle = (t - 0.5) * 0.018; // about a degree each way
                return Transform.rotate(angle: angle, child: child);
              },
              child: AnimatedScale(
                scale: hot ? 0.94 : 1,
                duration: Motion.quick,
                curve: easeOutStrong,
                child: Stack(
                  fit: StackFit.passthrough,
                  clipBehavior: Clip.none,
                  children: [
                    AbsorbPointer(child: content),
                    // the tile you are about to swap with: a soft white wash
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: hot ? 1 : 0,
                          duration: Motion.quick,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
            final drag = LongPressDraggable<String>(
              data: id,
              delay: const Duration(milliseconds: 120),
              onDragStarted: tick,
              // The tile itself, lifted: a little larger with a soft shadow.
              // (Material + a text style so its text looks exactly as it does
              // in place, outside the screen's own widgets.)
              feedback: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: c.maxWidth,
                  height: c.maxHeight,
                  child: Transform.scale(
                    scale: 1.05,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 26,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: DefaultTextStyle(
                          style: DefaultTextStyle.of(
                            context,
                          ).style.copyWith(decoration: TextDecoration.none),
                          child: IgnorePointer(child: content),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.25, child: shown),
              child: shown,
            );
            // The "-" sits beside the draggable, not inside it: a press that
            // lingers a moment would otherwise start a drag and swallow the tap.
            return Stack(
              fit: StackFit.passthrough,
              clipBehavior: Clip.none,
              children: [
                drag,
                Positioned(
                  top: -8,
                  left: -8,
                  width: 64,
                  height: 64,
                  child: Semantics(
                    button: true,
                    label: 'Remove this widget',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _remove(id),
                      child: const Align(
                        alignment: Alignment.topLeft,
                        child: _Badge(
                          icon: Icons.remove_rounded,
                          color: Palette.red,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Where each tile goes in a box of [size]: columns when it is wide, rows
  // when it is not. The music tile takes a whole column (a double-height row);
  // a tile alone in its column fills it.
  Map<String, Rect> _rects(Size size, List<List<String>> cols) {
    final out = <String, Rect>{};
    if (cols.isEmpty) return out;
    final wide = size.width > size.height * 1.25;
    double weight(List<String> col) => col.contains(_musicId) ? 1.1 : 1.0;
    final total = cols.fold(0.0, (sum, c) => sum + weight(c));
    if (wide) {
      final room = size.width - (cols.length - 1) * _gap;
      var x = 0.0;
      for (final col in cols) {
        final w = room * weight(col) / total;
        final h = (size.height - _gap) / 2;
        if (col.length == 1) {
          out[col[0]] = Rect.fromLTWH(x, 0, w, size.height);
        } else {
          out[col[0]] = Rect.fromLTWH(x, 0, w, h);
          out[col[1]] = Rect.fromLTWH(x, h + _gap, w, h);
        }
        x += w + _gap;
      }
    } else {
      // rows: music is twice as tall as a pair of small tiles
      double rowWeight(List<String> col) => col.contains(_musicId) ? 2.0 : 1.0;
      final sum = cols.fold(0.0, (s, c) => s + rowWeight(c));
      final room = size.height - (cols.length - 1) * _gap;
      var y = 0.0;
      for (final col in cols) {
        final h = room * rowWeight(col) / sum;
        final w = (size.width - _gap) / 2;
        if (col.length == 1) {
          out[col[0]] = Rect.fromLTWH(0, y, size.width, h);
        } else {
          out[col[0]] = Rect.fromLTWH(0, y, w, h);
          out[col[1]] = Rect.fromLTWH(w + _gap, y, w, h);
        }
        y += h + _gap;
      }
    }
    return out;
  }

  // [child] arriving as card number [order]: later ones start a little later.
  Widget _arrive(int order, Widget child) {
    final curve = Interval(
      (order * 0.09).clamp(0.0, 0.5),
      (order * 0.09 + 0.5).clamp(0.5, 1.0),
      curve: easeOutStrong,
    );
    return AnimatedBuilder(
      animation: _enter,
      builder: (context, child) {
        final t = curve.transform(_enter.value);
        if (t >= 1) return child!;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 22),
            child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
          ),
        );
      },
      child: child,
    );
  }

  static const _plusId = 'plus';

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    final still = MediaQuery.disableAnimationsOf(context);
    final content = <String, Widget>{
      for (final t in layout.tiles) t.name: _tile(t),
    };
    // while editing, a "+" takes the next free place, if there is room for it
    final ids = [for (final t in layout.tiles) t.name];
    if (_editing && layout.missing.isNotEmpty) {
      // the "+" goes where it was dragged to, else where a new widget would
      // fit (the end, else the first place from the end that still fits in
      // three columns)
      final first = _plusPref?.clamp(0, ids.length) ?? ids.length;
      for (var at = first; at >= 0; at--) {
        final tryIds = [...ids]..insert(at, _plusId);
        if (SummaryLayout.pack(tryIds, (id) => id == _musicId).length <=
            SummaryLayout.maxColumns) {
          ids
            ..clear()
            ..addAll(tryIds);
          break;
        }
      }
    }
    final cols = SummaryLayout.pack(ids, (id) => id == _musicId);
    final settled = _enter.isCompleted;
    // While editing, a strip at the top is kept for the Done button, so it
    // never sits on a tile's "-". Taps on the panel while editing stay here
    // (they must not fall through and open All settings).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _editing ? () {} : null,
      child: Stack(
        children: [
          AnimatedPadding(
            duration: still ? Duration.zero : Motion.fast,
            curve: easeOutStrong,
            padding: EdgeInsets.fromLTRB(
              _gap,
              _editing ? 76 : _gap,
              _gap,
              _gap,
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final rects = _rects(Size(c.maxWidth, c.maxHeight), cols);
                // the order the tiles arrive in: left to right, top to bottom
                final arrival = rects.keys.toList()
                  ..sort((a, b) {
                    final byX = rects[a]!.left.compareTo(rects[b]!.left);
                    return byX != 0
                        ? byX
                        : rects[a]!.top.compareTo(rects[b]!.top);
                  });
                // Each tile is placed by its own rectangle, so when the order
                // changes the tiles glide to their new places instead of jumping.
                final children = <Widget>[];
                for (final id in ids) {
                  final fresh = settled && !_seen.contains(id);
                  final removing = _removing.contains(id);
                  final Widget body = id == _plusId
                      ? LongPressDraggable<String>(
                          data: _plusId,
                          delay: const Duration(milliseconds: 120),
                          onDragStarted: tick,
                          // the "+" lifted, as a tile is
                          feedback: Material(
                            type: MaterialType.transparency,
                            child: SizedBox(
                              width: rects[id]!.width,
                              height: rects[id]!.height,
                              child: Transform.scale(
                                scale: 1.05,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black54,
                                        blurRadius: 26,
                                        offset: Offset(0, 14),
                                      ),
                                    ],
                                  ),
                                  child: const _PlusTile(),
                                ),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.25,
                            child: _PlusTile(onTap: widget.onAddTile),
                          ),
                          child: _PlusTile(
                            onTap: widget.onAddTile,
                            onDrop: (dragged) => dragged == _plusId
                                ? null
                                : _moveToEmpty(
                                    dragged,
                                    ids.indexOf(_plusId),
                                    ids,
                                  ),
                          ),
                        )
                      : _slot(id, content[id]!);
                  children.add(
                    AnimatedPositioned(
                      key: ValueKey(id),
                      duration: still ? Duration.zero : Motion.slow,
                      curve: easeOutStrong,
                      left: rects[id]!.left,
                      top: rects[id]!.top,
                      width: rects[id]!.width,
                      height: rects[id]!.height,
                      child: _arrive(
                        arrival.indexOf(id),
                        _Pop(
                          fresh: fresh && !still,
                          child: AnimatedScale(
                            scale: removing ? 0.85 : 1,
                            duration: still ? Duration.zero : Motion.fast,
                            curve: easeOutStrong,
                            child: AnimatedOpacity(
                              opacity: removing ? 0 : 1,
                              duration: still ? Duration.zero : Motion.fast,
                              onEnd: removing ? () => _commitRemove(id) : null,
                              child: body,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                _seen.addAll(ids);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ...children,
                    if (ids.isEmpty)
                      Center(
                        child: GestureDetector(
                          onTap: widget.onAddTile,
                          onLongPress: () => _setEditing(true),
                          child: Text(
                            'Hold to add widgets',
                            style: _caption(16),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (_editing)
            Positioned(
              top: 4,
              left: 0,
              right: 0,
              child: Center(
                child: Pressable(
                  scale: 0.95,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _setEditing(false),
                    // a roomy target: much bigger than the pill you see
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: const Glass(
                        radius: 99,
                        blur: 18,
                        opacity: 0.7,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 11,
                          ),
                          child: Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A rounded, slightly lighter block, sized to its content by its parent. With
/// a [tint] it takes on that colour: a soft wash from one corner and a fine
/// edge of the same colour, so a picked colour reads as light, not paint.
class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.tint});

  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final t = tint;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: t == null ? Colors.white.withValues(alpha: 0.07) : null,
        gradient: t == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.withValues(alpha: 0.34), t.withValues(alpha: 0.10)],
              ),
        border: Border.all(
          color: (t ?? Colors.white).withValues(alpha: t == null ? 0.05 : 0.32),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    );
  }
}

TextStyle _caption(double size, [Color color = Colors.white60]) => TextStyle(
  color: color,
  fontSize: size,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.1,
);

class _HereTile extends StatelessWidget {
  const _HereTile({required this.now, required this.settings});

  final DateTime now;
  final StandbySettings settings;

  @override
  Widget build(BuildContext context) {
    final city = settings.localCity.isNotEmpty ? settings.localCity : 'Here';
    return _ClockTile(
      label: city,
      when: now,
      settings: settings,
      daytime: _isDay(now),
      ink: settings.hereColor == 0 ? null : Color(settings.hereColor),
    );
  }
}

bool _isDay(DateTime t) => t.hour >= 6 && t.hour < 18;

/// A picked colour lifted so the time stays readable on the dark tile: dark
/// picks (navy, brown) are lightened, bright ones are kept.
Color _bright(Color c) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness(hsl.lightness.clamp(0.62, 0.9)).toColor();
}

/// One Summary clock tile in a given look, for the settings pictures.
class SummaryClockPreview extends StatelessWidget {
  const SummaryClockPreview({
    super.key,
    required this.settings,
    required this.style,
    this.second = false,
  });

  final StandbySettings settings;
  final TileClockStyle style;

  /// draw the second city's tile (its colour) instead of the first
  final bool second;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(6),
    child: _ClockTile(
      label: 'Tokyo',
      when: DateTime(2026, 1, 1, 10, 9, 30),
      settings: settings.copyWith(summaryClockStyle: style),
      ink: (second ? settings.thereColor : settings.hereColor) == 0
          ? null
          : Color(second ? settings.thereColor : settings.hereColor),
    ),
  );
}

/// A city name over its time, the way iOS shows a world clock: as the Frame
/// look, as flip cards, or as a dial (Settings > Summary clocks). Swipe up or
/// down on it to change the look: the new one rises into place, and a small
/// glass label names it for a moment, as on the weather card.
class _ClockTile extends StatefulWidget {
  const _ClockTile({
    required this.label,
    required this.when,
    required this.settings,
    this.note,
    this.daytime,
    this.ink,
  });

  final String label;

  /// the time in that city, for the faces
  final DateTime when;
  final StandbySettings settings;
  final String? note;

  /// true: a sun beside the city, false: a moon (what it is like there now)
  final bool? daytime;

  /// the picked colour: tints the tile and colours the time; null = plain
  final Color? ink;

  @override
  State<_ClockTile> createState() => _ClockTileState();
}

class _ClockTileState extends State<_ClockTile> {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];
  static const _names = ['Frame', 'Flip', 'Analog'];

  int _from = 0; // the look we came from, for the direction it rises from

  @override
  void didUpdateWidget(_ClockTile old) {
    super.didUpdateWidget(old);
    if (old.settings.summaryClockStyle != widget.settings.summaryClockStyle) {
      _from = old.settings.summaryClockStyle.index;
    }
  }

  Color get _time {
    final s = widget.settings;
    if (s.summaryTimeColor != 0) return Color(s.summaryTimeColor);
    return widget.ink == null ? Colors.white : _bright(widget.ink!);
  }

  Color get _detail {
    final s = widget.settings;
    if (s.summaryDetailColor != 0) return Color(s.summaryDetailColor);
    return widget.ink == null ? const Color(0xFFB4B4BC) : _bright(widget.ink!);
  }

  // The faces are the Clock's own widgets (or the dial below), so they take
  // the tile's colours the way the Clock takes its colours.
  StandbySettings _tileSettings(ClockStyle style) => widget.settings.copyWith(
    // 12 or 24 hours on these tiles, or whatever the Clock uses
    use24HourTime: switch (widget.settings.summaryHours) {
      1 => false,
      2 => true,
      _ => widget.settings.use24HourTime,
    },
    clockStyle: style,
    showSeconds: false,
    hoursColor: _time.toARGB32(),
    minutesColor: _time.toARGB32(),
    colonColor: _detail.toARGB32(),
    detailColor: _detail.toARGB32(), // the AM / PM tag
    labelColor: _detail.toARGB32(), // the Frame's ticks
  );

  Widget _face(TileClockStyle style, double w, double h) {
    switch (style) {
      case TileClockStyle.digital:
        // the Frame look: a heavy time inside a ring of ticks
        return KeyedSubtree(
          key: const ValueKey('frame'),
          child: FrameClockFace(
            time: widget.when,
            snug: true,
            settings: _tileSettings(ClockStyle.frame),
          ),
        );
      case TileClockStyle.flip:
        return KeyedSubtree(
          key: const ValueKey('flip'),
          child: Center(
            child: FittedBox(
              // grows to fill the tile, as well as shrinking to fit it
              fit: BoxFit.contain,
              child: FlipClockFace(
                time: widget.when,
                settings: _tileSettings(ClockStyle.flip),
                // a tall tile stacks the hour over the minute
                stacked: h > w * 1.1,
              ),
            ),
          ),
        );
      case TileClockStyle.analog:
        return KeyedSubtree(
          key: const ValueKey('analog'),
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: DialPainter(
                    widget.when,
                    tint: widget.ink,
                    hourInk: _time,
                    minuteInk: _time,
                    markInk: _time,
                    accentInk: _detail,
                    numeralInk: _time,
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.settings.summaryClockStyle;
    final still = MediaQuery.disableAnimationsOf(context);
    final forward = style.index > _from || (_from == 2 && style.index == 0);
    final when = widget.when;
    return _Tile(
      tint: widget.ink,
      child: LayoutBuilder(
        builder: (context, c) {
          final u = math.min(c.maxWidth, c.maxHeight);
          final cap = (u * 0.13).clamp(12.0, 17.0);
          // a narrow tile (a phone, a small window): the pill is short and
          // stays top right, and the date gets the whole width under both
          final phonePill = c.maxWidth < 300 && c.maxWidth <= c.maxHeight * 1.7;
          // very narrow: the sun / moon goes, so the city name keeps its room
          final icon =
              widget.daytime != null && !(phonePill && c.maxWidth < 230);
          // the date there, under the city: 17 Oct · Thu
          final dateLine = Padding(
            padding: EdgeInsets.only(left: icon ? cap + 8 : 0, top: 1),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${when.day} ${_months[when.month - 1]} · '
                '${_days[when.weekday - 1]}',
                maxLines: 1,
                style: _caption(phonePill ? cap : cap - 2, Colors.white54),
              ),
            ),
          );
          Widget pill() => ConstrainedBox(
            // never more than half the tile: a narrow one cuts it short
            constraints: BoxConstraints(maxWidth: c.maxWidth * 0.6),
            child: Container(
              margin: EdgeInsets.only(left: phonePill ? 4 : 8),
              padding: EdgeInsets.symmetric(
                horizontal: phonePill ? 7 : 9,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(99),
              ),
              // shrinks to fit, so it is never cut short
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  phonePill ? widget.note!.split(' · ').first : widget.note!,
                  maxLines: 1,
                  style: _caption(
                    phonePill
                        ? (u * 0.06).clamp(10.5, 13.0)
                        : (u * 0.11).clamp(11.0, 15.0),
                    Colors.white70,
                  ),
                ),
              ),
            ),
          );
          // a wide, short tile (a small window): the time takes the right half
          final wideShort = c.maxWidth > c.maxHeight * 1.7;
          final cityRow = Row(
            children: [
              if (icon) ...[
                Icon(
                  widget.daytime!
                      ? Icons.wb_sunny_rounded
                      : Icons.nightlight_round,
                  size: cap + 2,
                  color: widget.ink == null
                      ? Colors.white54
                      : _bright(widget.ink!).withValues(alpha: 0.9),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _caption(cap, Colors.white70),
                ),
              ),
            ],
          );
          final faceSwitcher = AnimatedSwitcher(
            duration: still ? Duration.zero : Motion.medium,
            switchInCurve: easeOutStrong,
            switchOutCurve: easeOutStrong,
            layoutBuilder: (current, previous) =>
                Stack(fit: StackFit.expand, children: [...previous, ?current]),
            // the next look rises into place from below (swiping
            // up); going back it settles from above
            transitionBuilder: (child, anim) {
              final incoming =
                  child.key != null &&
                  child.key == _face(style, c.maxWidth, c.maxHeight).key;
              final dir = forward ? 1.0 : -1.0;
              return AnimatedBuilder(
                animation: anim,
                builder: (context, ch) {
                  final gone = 1 - anim.value;
                  return FractionalTranslation(
                    translation: Offset(
                      0,
                      (incoming ? dir : -dir) * 0.12 * gone,
                    ),
                    child: Opacity(
                      opacity: anim.value.clamp(0.0, 1.0),
                      child: ch,
                    ),
                  );
                },
                child: child,
              );
            },
            child: _face(style, c.maxWidth, c.maxHeight),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              if (wideShort)
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cityRow,
                          dateLine,
                          if (widget.note != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: pill(),
                            ),
                        ],
                      ),
                    ),
                    Expanded(flex: 6, child: faceSwitcher),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [cityRow, if (!phonePill) dateLine],
                              ),
                            ),
                            // how far ahead or behind, up here so the time can be large
                            if (widget.note != null) pill(),
                          ],
                        ),
                        if (phonePill) dateLine,
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: faceSwitcher,
                      ),
                    ),
                  ],
                ),
              // the dots and the look's name, for a moment after each swipe
              SwipeRail(index: style.index, labels: _names),
            ],
          );
        },
      ),
    );
  }
}

class _ThereTile extends StatelessWidget {
  const _ThereTile({required this.now, required this.settings});

  final DateTime now;
  final StandbySettings settings;

  // Removing the city breaks the tile into particles (see DissolveSwitcher);
  // adding one fades it in.
  @override
  Widget build(BuildContext context) {
    final zone = settings.worldZone;
    // no cross-fade of its own: the particles are a picture of the new tile
    // alone (a fade would put the old "Tap to add" text into that picture)
    return DissolveSwitcher(
      present: zone.isNotEmpty,
      fadeIn: false,
      child: _content(zone),
    );
  }

  Widget _content(String zone) {
    if (zone.isEmpty) {
      return _Tile(
        child: Center(
          child: Text(
            'Tap to add a second city',
            textAlign: TextAlign.center,
            style: _caption(14),
          ),
        ),
      );
    }
    final other = timeInZone(now, zone);
    final city = settings.worldCity.isNotEmpty
        ? settings.worldCity
        : zoneLabel(zone);
    final dayDiff = DateTime(
      other.year,
      other.month,
      other.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    final hours = (other.timeZoneOffset - now.timeZoneOffset).inMinutes / 60;
    final away = hours == 0
        ? 'Same time'
        : '${hours > 0 ? '+' : '−'}${hours.abs().toStringAsFixed(hours % 1 == 0 ? 0 : 1)} h';
    final when = dayDiff == 0
        ? away
        : '$away · ${dayDiff > 0 ? 'Tmrw' : 'Yday'}';
    return _ClockTile(
      label: city,
      when: other,
      // the second city may have a look of its own
      settings: settings.copyWith(summaryClockStyle: settings.thereStyle),
      note: when,
      daytime: _isDay(other),
      ink: settings.thereColor == 0 ? null : Color(settings.thereColor),
    );
  }
}

/// The date tile is the Calendar card itself, small: it follows the
/// Calendar's Today / Month choice and its one-number design (the date is the
/// only number on Today, the grid the only numbers on Month), instead of a
/// second, different way of drawing the date.
class _DateTile extends StatelessWidget {
  const _DateTile({required this.now, required this.settings});

  final DateTime now;
  final StandbySettings settings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        // the tile deals in with the others: no second entrance inside it
        child: CalendarCard(
          settings: settings,
          now: now,
          entrance: false,
          compact: true,
        ),
      ),
    );
  }
}

/// A small round badge on a tile's corner ("-" to remove it).
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
      ),
      child: SizedBox(
        width: 26,
        height: 26,
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

/// The "+" that takes a free place while editing: tap it to choose a widget.
class _PlusTile extends StatelessWidget {
  const _PlusTile({this.onTap, this.onDrop});

  final VoidCallback? onTap;

  /// a tile was dropped on this empty place
  final ValueChanged<String>? onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => onDrop != null,
      onAcceptWithDetails: (d) => onDrop?.call(d.data),
      builder: (context, candidates, rejected) =>
          _plus(context, hot: candidates.isNotEmpty),
    );
  }

  Widget _plus(BuildContext context, {required bool hot}) {
    return Semantics(
      button: true,
      label: 'Add a widget',
      excludeSemantics: true,
      child: Pressable(
        scale: 0.96,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            tick();
            onTap?.call();
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              // lights up while a tile is held over it
              color: Colors.white.withValues(alpha: hot ? 0.16 : 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: hot ? 0.6 : 0.22),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                    child: const Icon(Icons.add_rounded, size: 30),
                  ),
                  const SizedBox(height: 8),
                  Text('Add a widget', style: _caption(13, Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tile that has just been added: it grows and fades in. (Tiles that were
/// already there, or that deal in with the panel, are left alone.)
class _Pop extends StatelessWidget {
  const _Pop({required this.fresh, required this.child});

  final bool fresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: fresh ? 0 : 1, end: 1),
      duration: Motion.fast,
      curve: easeOutStrong,
      builder: (context, v, child) => v >= 1
          ? child!
          : Opacity(
              opacity: v.clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.9 + 0.1 * v, child: child),
            ),
      child: child,
    );
  }
}
