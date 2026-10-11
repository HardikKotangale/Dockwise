import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/apple.dart';
import '../../../domain/standby_models.dart';
import '../../../domain/summary_layout.dart';
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
    this.onWeatherSwipe,
    this.onLayout,
    this.onCityTap,
    this.onEditing,
  });

  final DateTime now;
  final StandbySettings settings;

  /// The weather card itself (the one the Weather panel shows), so the tile
  /// swipes through the same four pages: now, Fahrenheit, forecast, second city.
  final Widget weather;

  /// Swiped up (+1) or down (-1) on the weather tile.
  final ValueChanged<int>? onWeatherSwipe;

  /// The now-playing card itself (the one the Music panel shows), so Summary
  /// has all of its controls: seek, devices, volume, queue and search.
  final Widget music;

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

  // drives the jiggle; only runs while editing
  late final AnimationController _jiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
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

  SummaryLayout get _layout =>
      SummaryLayout.parse(widget.settings.summaryLayout);

  @override
  void dispose() {
    _enter.dispose();
    _jiggle.dispose();
    super.dispose();
  }

  void _setEditing(bool on) {
    if (_editing == on) return;
    setState(() => _editing = on);
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
    SummaryLayout? next;
    final dragTile = SummaryTile.values.where((t) => t.name == dragged);
    final targetTile = SummaryTile.values.where((t) => t.name == target);
    if (dragged == _musicId && targetTile.isNotEmpty) {
      next = layout.withMusicColumn(layout.columnOf(targetTile.first));
    } else if (dragTile.isNotEmpty && targetTile.isNotEmpty) {
      next = layout.swap(dragTile.first, targetTile.first);
    }
    if (next != null && next != layout) {
      tick();
      widget.onLayout?.call(next.encode());
    }
  }

  Widget _tile(SummaryTile t) => switch (t) {
    SummaryTile.here => _HereTile(now: widget.now, settings: widget.settings),
    SummaryTile.there => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _editing ? null : widget.onCityTap,
      child: _ThereTile(now: widget.now, settings: widget.settings),
    ),
    SummaryTile.date => _DateTile(now: widget.now, settings: widget.settings),
    SummaryTile.weather => ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
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
  Widget _slot(String id, Widget content) {
    if (!_editing) {
      return GestureDetector(
        onLongPress: () => _setEditing(true),
        child: content,
      );
    }
    final phase = (id.hashCode % 7) / 7;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data != id && !(d.data != _musicId && id == _musicId),
      onAcceptWithDetails: (d) => _drop(d.data, id),
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
                duration: const Duration(milliseconds: 160),
                curve: easeOutStrong,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    AbsorbPointer(child: content),
                    // the tile you are about to swap with: a soft white wash
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: hot ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
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
            return LongPressDraggable<String>(
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
          },
        );
      },
    );
  }

  // Where each tile goes in a box of [size]: three columns when it is wide,
  // three rows when it is not (the music tile takes a whole column or row).
  Map<String, Rect> _rects(Size size, SummaryLayout layout) {
    final cols = layout.columns;
    final out = <String, Rect>{};
    final wide = size.width > size.height * 1.25;
    if (wide) {
      final flex = [
        for (var i = 0; i < 3; i++)
          cols[i] == null ? 11.0 : (i == 0 ? 11.0 : 10.0),
      ];
      final room = size.width - 2 * _gap;
      var x = 0.0;
      for (var i = 0; i < 3; i++) {
        final w = room * flex[i] / (flex[0] + flex[1] + flex[2]);
        final pair = cols[i];
        if (pair == null) {
          out[_musicId] = Rect.fromLTWH(x, 0, w, size.height);
        } else {
          final h = (size.height - _gap) / 2;
          out[pair[0].name] = Rect.fromLTWH(x, 0, w, h);
          out[pair[1].name] = Rect.fromLTWH(x, h + _gap, w, h);
        }
        x += w + _gap;
      }
    } else {
      final room = size.height - 2 * _gap;
      var y = 0.0;
      for (var i = 0; i < 3; i++) {
        final h = room * (cols[i] == null ? 2 : 1) / 4;
        final pair = cols[i];
        if (pair == null) {
          out[_musicId] = Rect.fromLTWH(0, y, size.width, h);
        } else {
          final w = (size.width - _gap) / 2;
          out[pair[0].name] = Rect.fromLTWH(0, y, w, h);
          out[pair[1].name] = Rect.fromLTWH(w + _gap, y, w, h);
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

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    final still = MediaQuery.disableAnimationsOf(context);
    final content = <String, Widget>{
      _musicId: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: widget.music,
      ),
      for (final t in SummaryTile.values) t.name: _tile(t),
    };
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(_gap),
          child: LayoutBuilder(
            builder: (context, c) {
              final rects = _rects(Size(c.maxWidth, c.maxHeight), layout);
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
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final id in [
                    _musicId,
                    ...SummaryTile.values.map((t) => t.name),
                  ])
                    AnimatedPositioned(
                      key: ValueKey(id),
                      duration: still
                          ? Duration.zero
                          : const Duration(milliseconds: 420),
                      curve: easeOutStrong,
                      left: rects[id]!.left,
                      top: rects[id]!.top,
                      width: rects[id]!.width,
                      height: rects[id]!.height,
                      child: _arrive(
                        arrival.indexOf(id),
                        _slot(id, content[id]!),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (_editing)
          Positioned(
            top: 14,
            left: 0,
            right: 0,
            child: Center(
              child: Pressable(
                scale: 0.95,
                child: GestureDetector(
                  onTap: () => _setEditing(false),
                  child: const Glass(
                    radius: 99,
                    blur: 18,
                    opacity: 0.7,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 9,
                      ),
                      child: Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 15,
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
      ],
    );
  }
}

/// A rounded, slightly lighter block, sized to its content by its parent.
class _Tile extends StatelessWidget {
  const _Tile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
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
    return _ClockTile(label: city, time: timeOfDayText(now, settings));
  }
}

/// A city name over a large digital time, the way iOS shows a world clock.
class _ClockTile extends StatelessWidget {
  const _ClockTile({required this.label, required this.time, this.note});

  final String label;
  final ({String text, String? suffix}) time;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return _Tile(
      child: LayoutBuilder(
        builder: (context, c) {
          final u = math.min(c.maxWidth, c.maxHeight);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _caption((u * 0.13).clamp(12.0, 17.0), Colors.white70),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        time.text,
                        style: const TextStyle(
                          fontSize: 120,
                          fontWeight: FontWeight.w200,
                          letterSpacing: -5,
                          height: 1.05,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (time.suffix != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            time.suffix!,
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w500,
                              color: Colors.white60,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (note != null)
                Text(
                  note!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _caption((u * 0.11).clamp(11.0, 15.0)),
                ),
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

  @override
  Widget build(BuildContext context) {
    final zone = settings.worldZone;
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
        : '$away · ${dayDiff > 0 ? 'Tomorrow' : 'Yesterday'}';
    return _ClockTile(
      label: city,
      time: timeOfDayText(other, settings),
      note: when,
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.now, required this.settings});

  final DateTime now;
  final StandbySettings settings;

  @override
  Widget build(BuildContext context) {
    return _Tile(
      child: LayoutBuilder(
        builder: (context, c) {
          final u = math.min(c.maxWidth, c.maxHeight);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('EEEE').format(now).toUpperCase(),
                maxLines: 1,
                style: TextStyle(
                  color: settings.appAccentInk,
                  fontSize: (u * 0.13).clamp(11.0, 16.0),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${now.day}',
                    style: const TextStyle(
                      fontSize: 200,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -6,
                      height: 1,
                    ),
                  ),
                ),
              ),
              Text(
                DateFormat('MMMM yyyy').format(now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _caption((u * 0.13).clamp(11.0, 16.0)),
              ),
            ],
          );
        },
      ),
    );
  }
}
