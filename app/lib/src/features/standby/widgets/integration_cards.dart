import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'weather_scene.dart';
import '../../../domain/standby_models.dart';
import '../../../services/weather_service.dart';

/// Weather for the phone's location. The card tints itself by condition and
/// time of day; every size scales with the card.
class WeatherCard extends StatelessWidget {
  const WeatherCard({
    super.key,
    required this.snapshot,
    required this.settings,
    this.problem,
  });

  final WeatherSnapshot? snapshot;
  final StandbySettings settings;
  final WeatherProblem? problem;

  static ({IconData icon, List<Color> tint}) _look(int? code, bool isDay) {
    if (code == null || code == 0) {
      return isDay
          ? (
              icon: Icons.wb_sunny,
              tint: const [Color(0xFF1E6FD9), Color(0xFF0B2A5B)],
            )
          : (
              icon: Icons.nightlight_round,
              tint: const [Color(0xFF1B1F4B), Color(0xFF05060F)],
            );
    }
    if (code <= 2) {
      return (
        icon: isDay ? Icons.wb_cloudy : Icons.nights_stay,
        tint: isDay
            ? const [Color(0xFF3B7DC4), Color(0xFF14283F)]
            : const [Color(0xFF232A55), Color(0xFF080A18)],
      );
    }
    if (code == 3) {
      return (
        icon: Icons.cloud,
        tint: const [Color(0xFF5B6B7A), Color(0xFF1F262E)],
      );
    }
    if (code == 45 || code == 48) {
      return (
        icon: Icons.foggy,
        tint: const [Color(0xFF6E7781), Color(0xFF272B30)],
      );
    }
    if (code >= 51 && code <= 57) {
      return (
        icon: Icons.grain,
        tint: const [Color(0xFF42607C), Color(0xFF121A24)],
      );
    }
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) {
      return (
        icon: Icons.water_drop,
        tint: const [Color(0xFF37526E), Color(0xFF10161E)],
      );
    }
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
      return (
        icon: Icons.ac_unit,
        tint: const [Color(0xFF8FB4CC), Color(0xFF2A3947)],
      );
    }
    return (
      icon: Icons.thunderstorm,
      tint: const [Color(0xFF4B3A6E), Color(0xFF140F22)],
    );
  }

  String _deg(int celsius) =>
      '${settings.fahrenheit ? (celsius * 9 / 5 + 32).round() : celsius}°';

  String get _message => switch (problem) {
    WeatherProblem.permission =>
      'Allow location access to see the weather here',
    WeatherProblem.locationOff => 'Turn on location to see the weather here',
    WeatherProblem.offline => 'Weather unavailable. Check your connection',
    null => 'Loading weather…',
  };

  @override
  Widget build(BuildContext context) {
    final w = snapshot;
    return LayoutBuilder(
      builder: (context, c) {
        final unit = math.min(c.maxWidth, c.maxHeight);
        final pad = (unit / 12).clamp(16.0, 28.0);
        if (w == null) {
          return Padding(
            padding: EdgeInsets.all(pad),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    problem == null ? Icons.cloud_queue : Icons.location_off,
                    size: unit / 5,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: (unit / 14).clamp(14.0, 20.0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final look = _look(w.code, w.isDay);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: look.tint,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // live backdrop: clouds drift, rain falls, snow floats...
              WeatherScene(spec: sceneFor(w.code, w.isDay)),
              Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.near_me,
                          size: (unit / 16).clamp(14.0, 20.0),
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            w.city,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: (unit / 12).clamp(16.0, 26.0),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _deg(w.temperatureCelsius),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: (unit * 0.42).clamp(56.0, 160.0),
                          height: 0.95,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          look.icon,
                          size: (unit / 12).clamp(18.0, 28.0),
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            w.condition,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: (unit / 13).clamp(15.0, 24.0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'H:${_deg(w.highCelsius)}   L:${_deg(w.lowCelsius)}',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: (unit / 15).clamp(14.0, 22.0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Calendar cells for [month], Sunday first: leading/trailing nulls pad the
/// first and last week so the list length is a multiple of 7.
List<int?> monthCells(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final days = DateTime(month.year, month.month + 1, 0).day;
  final leading = first.weekday % 7; // Sunday = 0
  final cells = <int?>[
    for (var i = 0; i < leading; i++) null,
    for (var d = 1; d <= days; d++) d,
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return cells;
}

/// Calendar card: today's date (day) or the whole month grid (month).
class CalendarCard extends StatelessWidget {
  const CalendarCard({super.key, required this.settings, required this.now});

  final StandbySettings settings;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = settings.theme;
    return LayoutBuilder(
      builder: (context, c) {
        final unit = math.min(c.maxWidth, c.maxHeight);
        final pad = (unit / 10).clamp(14.0, 32.0);
        return Padding(
          padding: EdgeInsets.all(pad),
          child: settings.calendarStyle == CalendarStyle.month
              ? _month(theme, unit)
              : _day(theme, unit),
        );
      },
    );
  }

  Widget _day(ThemePreset theme, double unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEEE').format(now).toUpperCase(),
          maxLines: 1,
          style: TextStyle(
            color: settings.appAccentInk,
            fontSize: (unit / 10).clamp(16.0, 30.0),
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${now.day}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 400,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Text(
          DateFormat('MMMM yyyy').format(now),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white70,
            fontSize: (unit / 11).clamp(16.0, 28.0),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _month(ThemePreset theme, double unit) {
    final cells = monthCells(now);
    final weeks = cells.length ~/ 7;
    final headerSize = (unit / 11).clamp(15.0, 26.0);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('MMMM').format(now).toUpperCase(),
                maxLines: 1,
                style: TextStyle(
                  color: settings.appAccentInk,
                  fontSize: headerSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Text(
              '${now.year}',
              style: TextStyle(
                color: Colors.white54,
                fontSize: headerSize * 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: (headerSize * 0.7).clamp(11.0, 18.0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Column(
            children: [
              for (var w = 0; w < weeks; w++)
                Expanded(
                  child: Row(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Expanded(child: _cell(cells[w * 7 + d], theme)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(int? day, ThemePreset theme) {
    if (day == null) return const SizedBox.shrink();
    final today = day == now.day;
    return LayoutBuilder(
      builder: (context, c) {
        final size = math.min(c.maxWidth, c.maxHeight);
        return Center(
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: today
                ? BoxDecoration(
                    color: settings.appAccentInk,
                    shape: BoxShape.circle,
                  )
                : null,
            child: Text(
              '$day',
              style: TextStyle(
                color: today ? Colors.black : Colors.white,
                fontSize: (size * 0.46).clamp(10.0, 24.0),
                fontWeight: today ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

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
  });

  final NowPlayingSnapshot snapshot;
  final StandbySettings settings;
  final Future<bool> Function(String command) onCommand;

  /// Press-and-hold on the progress bar, drag, release: jump to that point.
  final Future<bool> Function(int positionMs)? onSeek;

  /// A volume bar to show over the card (built with a callback that keeps it
  /// open while touched); null = this source has no volume control here.
  final Widget Function(VoidCallback keepOpen)? volumeBar;

  @override
  State<MusicCard> createState() => _MusicCardState();
}

class _MusicCardState extends State<MusicCard> {
  Timer? _tick;
  double? _scrub; // 0..1 while the bar is held; null otherwise
  bool _showVolume = false;
  Timer? _hideVolume;

  // The volume bar closes by itself a few seconds after the last touch.
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
    _tick?.cancel();
    super.dispose();
  }

  // Progress bar. Press and hold, drag to a point, release to jump there. A
  // long press (not a drag) so it never fights the swipe that changes widgets.
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
                            color: Colors.white,
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
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
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
                                fontWeight: FontWeight.w800,
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final position = snapshot.positionAt(now);
    final progress = snapshot.durationMs > 0
        ? (position / snapshot.durationMs).clamp(0.0, 1.0)
        : snapshot.progress;
    final art = _art(snapshot);
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
            DecoratedBox(
              decoration: BoxDecoration(
                image: art,
                gradient: art == null
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          settings.appAccentInk,
                          Color.lerp(settings.appAccentInk, Colors.black, 0.6)!,
                        ],
                      )
                    : null,
              ),
              child: art == null
                  ? Icon(
                      Icons.album,
                      size: unit * 0.4,
                      color: Colors.white.withValues(alpha: 0.18),
                    )
                  : null,
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
                        const Icon(
                          Icons.graphic_eq,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            snapshot.isControllable
                                ? snapshot.source
                                : 'Nothing playing',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
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
                            icon: const Icon(
                              Icons.volume_up_rounded,
                              size: 22,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  const Spacer(),
                  Text(
                    snapshot.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (unit / 12).clamp(18.0, 32.0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    snapshot.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: (unit / 18).clamp(13.0, 20.0),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: pad * 0.6),
                  _bar(progress, position),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (!compact)
                        _TransportButton(
                          icon: Icons.replay_10,
                          label: 'Back 10 seconds',
                          size: button,
                          onPressed: () => onCommand('back10'),
                        ),
                      _TransportButton(
                        icon: Icons.skip_previous,
                        label: 'Previous',
                        size: button,
                        onPressed: () => onCommand('previous'),
                      ),
                      _TransportButton(
                        icon: snapshot.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        label: snapshot.isPlaying ? 'Pause' : 'Play',
                        size: button * 1.2,
                        filled: true,
                        onPressed: () => onCommand('playPause'),
                      ),
                      _TransportButton(
                        icon: Icons.skip_next,
                        label: 'Next',
                        size: button,
                        onPressed: () => onCommand('next'),
                      ),
                      if (!compact)
                        _TransportButton(
                          icon: Icons.forward_10,
                          label: 'Forward 10 seconds',
                          size: button,
                          onPressed: () => onCommand('forward10'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.volumeBar != null)
              Positioned(
                left: pad,
                right: pad,
                top: pad - 6,
                child: IgnorePointer(
                  ignoring: !_showVolume,
                  child: AnimatedOpacity(
                    opacity: _showVolume ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
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

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.label,
    required this.size,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final double size;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: filled ? Colors.white : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              icon,
              size: size * 0.55,
              color: filled ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

DecorationImage? _art(NowPlayingSnapshot s) {
  final ImageProvider? image = s.artBytes != null
      ? MemoryImage(s.artBytes!)
      : s.artUrl != null
      ? NetworkImage(s.artUrl!)
      : null;
  return image == null
      ? null
      : DecorationImage(image: image, fit: BoxFit.cover);
}
