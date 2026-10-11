import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/apple.dart';
import '../../../domain/standby_models.dart';
import '../../../services/weather_service.dart';
import 'clock/zones.dart' show zoneLabel;
import 'weather_scene.dart';

/// One look at the weather in a place: the city, the temperature and the
/// condition on a backdrop tinted by the conditions. Every size scales with
/// the card.
class WeatherNowView extends StatelessWidget {
  const WeatherNowView({
    super.key,
    required this.snapshot,
    required this.settings,
    this.problem,
    this.message,
  });

  final WeatherSnapshot? snapshot;
  final StandbySettings settings;
  final WeatherProblem? problem;

  /// text for when there is no [snapshot] and no [problem]
  final String? message;

  static IconData iconFor(int? code, bool isDay) => _look(code, isDay).icon;

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

  /// The card's two background colors for a weather code, for other cards
  /// (the Summary panel) that show the weather the same way.
  static List<Color> tintFor(int? code, bool isDay) => _look(code, isDay).tint;

  String _deg(int celsius) =>
      '${settings.fahrenheit ? (celsius * 9 / 5 + 32).round() : celsius}°';

  String get _message => switch (problem) {
    WeatherProblem.permission =>
      'Allow location access to see the weather here',
    WeatherProblem.locationOff => 'Turn on location to see the weather here',
    WeatherProblem.offline => 'Weather unavailable. Check your connection',
    null => message ?? 'Loading weather…',
  };

  @override
  Widget build(BuildContext context) {
    final w = snapshot;
    return LayoutBuilder(
      builder: (context, c) {
        final unit = math.min(c.maxWidth, c.maxHeight);
        // a small tile (the Summary panel) gets tighter margins and drops the
        // condition row; the condition then rides on the high/low line
        final compact = c.maxHeight < 170;
        final pad = (unit / 12).clamp(compact ? 11.0 : 16.0, 28.0);
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
                          Icons.near_me_rounded,
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
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // the temperature takes what is left and shrinks to fit, so a
                    // small tile (the Summary panel) never overflows
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          _deg(w.temperatureCelsius),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: (unit * 0.42).clamp(56.0, 160.0),
                            height: 0.95,
                            fontWeight: FontWeight.w200,
                            letterSpacing: -3,
                          ),
                        ),
                      ),
                    ),
                    if (!compact) ...[
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
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      compact
                          ? '${w.condition}  H:${_deg(w.highCelsius)} L:${_deg(w.lowCelsius)}'
                          : 'H:${_deg(w.highCelsius)}   L:${_deg(w.lowCelsius)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: (unit / 15).clamp(14.0, 22.0),
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
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

/// The weather card. Swipe up and down to move through its pages:
/// now, the forecast (next hours and days), and the weather in your second
/// city. The same card shows the same page whichever panel it is in.
class WeatherCard extends StatefulWidget {
  const WeatherCard({
    super.key,
    required this.snapshot,
    required this.settings,
    this.problem,
    this.page = 0,
    this.secondSnapshot,
    this.secondFailed = false,
    this.onCityTap,
  });

  final WeatherSnapshot? snapshot;
  final StandbySettings settings;
  final WeatherProblem? problem;

  /// 0 now, 1 the same in Fahrenheit, 2 forecast, 3 second city
  final int page;
  final WeatherSnapshot? secondSnapshot;
  final bool secondFailed;

  /// Choose (or change) the second city.
  final VoidCallback? onCityTap;

  /// The card's two background colors for a weather code, for other cards
  /// (the Summary panel) that show the weather the same way.
  static List<Color> tintFor(int? code, bool isDay) =>
      WeatherNowView.tintFor(code, isDay);

  static IconData iconFor(int? code, bool isDay) =>
      WeatherNowView.iconFor(code, isDay);

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  int _from = 0; // the page we came from, for the slide direction

  @override
  void didUpdateWidget(WeatherCard old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) {
      _from = old.page;
    }
  }

  bool get _hasSecondCity =>
      widget.settings.worldZone.isNotEmpty &&
      (widget.settings.worldLat != 0 || widget.settings.worldLon != 0);

  Widget _page() {
    switch (widget.page) {
      case 1:
        // the very same card as the first page, but in Fahrenheit
        return WeatherNowView(
          key: const ValueKey('fahrenheit'),
          snapshot: widget.snapshot,
          settings: widget.settings.copyWith(fahrenheit: true),
          problem: widget.problem,
        );
      case 2:
        return _ForecastView(
          key: const ValueKey('forecast'),
          snapshot: widget.snapshot,
          settings: widget.settings,
        );
      case 3:
        if (!_hasSecondCity) {
          return _AddCityView(
            key: const ValueKey('add-city'),
            hasCityWithoutPlace: widget.settings.worldZone.isNotEmpty,
            onTap: widget.onCityTap,
          );
        }
        return GestureDetector(
          key: const ValueKey('second'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onCityTap,
          child: WeatherNowView(
            snapshot: widget.secondSnapshot,
            settings: widget.settings,
            message: widget.secondFailed
                ? 'Weather unavailable. Check your connection'
                : 'Loading weather…',
          ),
        );
      default:
        return WeatherNowView(
          key: const ValueKey('now'),
          snapshot: widget.snapshot,
          settings: widget.settings,
          problem: widget.problem,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final forward = widget.page > _from || (_from == 3 && widget.page == 0);
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: still ? Duration.zero : const Duration(milliseconds: 380),
          switchInCurve: easeOutStrong,
          switchOutCurve: easeOutStrong,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          // the next page rises into place from below (swiping up); going
          // back it settles from above
          transitionBuilder: (child, anim) {
            final incoming = child.key == _page().key;
            final dir = forward ? 1.0 : -1.0;
            return AnimatedBuilder(
              animation: anim,
              builder: (context, c) {
                final gone = 1 - anim.value;
                return FractionalTranslation(
                  translation: Offset(0, (incoming ? dir : -dir) * 0.12 * gone),
                  child: Opacity(opacity: anim.value.clamp(0.0, 1.0), child: c),
                );
              },
              child: child,
            );
          },
          child: _page(),
        ),
        // dots and a name for the page, for a moment after each swipe
        SwipeRail(
          index: widget.page,
          labels: [
            'Now',
            'Fahrenheit',
            'Forecast',
            // the city's own name once one is chosen
            widget.settings.worldZone.isEmpty
                ? 'Second city'
                : (widget.settings.worldCity.isNotEmpty
                      ? widget.settings.worldCity
                      : zoneLabel(widget.settings.worldZone)),
          ],
        ),
      ],
    );
  }
}

String _hourLabel(DateTime t, StandbySettings s, bool first) {
  if (first) return 'Now';
  if (s.use24HourTime) return '${t.hour.toString().padLeft(2, '0')}:00';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h${t.hour < 12 ? ' AM' : ' PM'}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The next hours across the top, then the days ahead with a bar for each
/// day's range, like the iOS Weather app.
class _ForecastView extends StatelessWidget {
  const _ForecastView({
    super.key,
    required this.snapshot,
    required this.settings,
  });

  final WeatherSnapshot? snapshot;
  final StandbySettings settings;

  String _deg(int c) =>
      '${settings.fahrenheit ? (c * 9 / 5 + 32).round() : c}°';

  @override
  Widget build(BuildContext context) {
    final w = snapshot;
    final tint = w == null
        ? const [Color(0xFF2C2C2E), Color(0xFF1C1C1E)]
        : WeatherNowView.tintFor(w.code, w.isDay);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tint,
        ),
      ),
      child: w == null || (w.days.isEmpty && w.hours.isEmpty)
          ? const Center(
              child: Text(
                'No forecast yet',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final unit = math.min(c.maxWidth, c.maxHeight);
                final pad = (unit / 14).clamp(14.0, 24.0);
                final inner = c.maxHeight - 2 * pad;
                const header = 34.0;
                // hours only when there is room; days fill what is left
                final showHours = w.hours.isNotEmpty && inner > 250;
                final hoursHeight = showHours ? 86.0 : 0.0;
                final rows = ((inner - header - hoursHeight) / 34)
                    .floor()
                    .clamp(1, w.days.length);
                const perHour = 56.0;
                final hourCount = ((c.maxWidth - 2 * pad) / perHour)
                    .floor()
                    .clamp(1, w.hours.length);
                final lows = w.days.map((d) => d.lowCelsius);
                final highs = w.days.map((d) => d.highCelsius);
                final lo = lows.isEmpty ? 0 : lows.reduce(math.min);
                final hi = highs.isEmpty ? 1 : highs.reduce(math.max);
                final span = math.max(1, hi - lo);
                return Padding(
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: header,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_month_rounded,
                              size: 16,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${w.city} · forecast',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (showHours)
                        SizedBox(
                          height: hoursHeight,
                          child: Row(
                            children: [
                              for (var i = 0; i < hourCount; i++)
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Text(
                                        _hourLabel(
                                          w.hours[i].time,
                                          settings,
                                          i == 0,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Icon(
                                        WeatherNowView.iconFor(
                                          w.hours[i].code,
                                          w.hours[i].isDay,
                                        ),
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                      Text(
                                        _deg(w.hours[i].temperatureCelsius),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (showHours)
                        Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      for (var i = 0; i < rows; i++)
                        Expanded(
                          child: FittedBox(
                            // a very small tile shrinks the row instead of overflowing
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: math.max(150.0, c.maxWidth - 2 * pad),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 46,
                                    child: Text(
                                      i == 0
                                          ? 'Today'
                                          : _weekdays[w.days[i].date.weekday -
                                                1],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    WeatherNowView.iconFor(
                                      w.days[i].code,
                                      true,
                                    ),
                                    size: 19,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 34,
                                    child: Text(
                                      _deg(w.days[i].lowCelsius),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  // the range bar only when there is room for it
                                  if (c.maxWidth - 2 * pad < 200)
                                    const Spacer()
                                  else
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: _RangeBar(
                                          from:
                                              (w.days[i].lowCelsius - lo) /
                                              span,
                                          to:
                                              (w.days[i].highCelsius - lo) /
                                              span,
                                        ),
                                      ),
                                    ),
                                  SizedBox(
                                    width: 34,
                                    child: Text(
                                      _deg(w.days[i].highCelsius),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// A day's low-to-high range as a pill inside the week's range.
class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.from, required this.to});

  final double from;
  final double to;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 5,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Positioned(
                left: w * from.clamp(0.0, 1.0),
                width: math.max(6, w * (to - from).clamp(0.0, 1.0)),
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF64D2FF), Color(0xFFFFD60A)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The third page before a second city is chosen: a plain invitation to pick
/// one (the same search as the second clock).
class _AddCityView extends StatelessWidget {
  const _AddCityView({
    super.key,
    required this.hasCityWithoutPlace,
    this.onTap,
  });

  /// a city is set for the clock, but it was picked from the offline list so
  /// its position is not known
  final bool hasCityWithoutPlace;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2C2C2E), Color(0xFF1C1C1E)],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.travel_explore_rounded,
                  size: 44,
                  color: Colors.white54,
                ),
                const SizedBox(height: 14),
                Text(
                  hasCityWithoutPlace
                      ? 'Search for your second city again to see its weather'
                      : 'Add a second city',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap to search',
                  style: TextStyle(color: Colors.white54, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
