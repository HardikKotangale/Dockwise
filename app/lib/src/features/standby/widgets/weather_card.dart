import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../../core/apple.dart';
import '../../../core/motion/dissolve.dart';
import '../../../core/palette.dart';
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

  // The temperature, with a small degree sign at the top (Apple's way): the
  // number carries the card, and the sign no longer swells into a big ring that
  // sits over the sun.
  Widget _temp(int celsius, double size, double spacing) {
    final n = settings.fahrenheit ? (celsius * 9 / 5 + 32).round() : celsius;
    return Text.rich(
      key: ValueKey(settings.fahrenheit),
      TextSpan(
        children: [
          TextSpan(text: '$n'),
          WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: Padding(
              padding: EdgeInsets.only(top: size * 0.08),
              child: Text(
                '°',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.2,
                  height: 1,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ),
        ],
      ),
      style: TextStyle(
        color: Colors.white,
        fontSize: size,
        height: 0.95,
        fontWeight: FontWeight.w200,
        letterSpacing: spacing,
      ),
    );
  }

  String get _message => switch (problem) {
    WeatherProblem.permission =>
      'Allow location access to see the weather here',
    WeatherProblem.locationOff => 'Turn on location to see the weather here',
    WeatherProblem.offline => 'Weather unavailable. Check your connection',
    null => message ?? 'Loading weather…',
  };

  // The full card. Its parts have a place for a tall panel (the city on top,
  // the temperature, the condition and the high and low under it) and one for
  // a wide panel (the temperature on the left, the words on the right); when
  // the phone turns they glide from one to the other.
  Widget _morphing(
    BuildContext context,
    WeatherSnapshot w,
    ({List<Color> tint, IconData icon}) look,
  ) {
    final still = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final bw = box.maxWidth, bh = box.maxHeight;
        final wide = bw > bh * 1.25;
        final unit = math.min(bw, bh);
        Rect rect(String id) => _weatherRects(bw, bh, wide, unit)[id]!;
        Widget fit(Widget child, {Alignment at = Alignment.centerLeft}) =>
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: at,
                child: child,
              ),
            );
        TextStyle t(
          double size,
          FontWeight weight, {
          Color? color,
          double? ls,
        }) => TextStyle(
          color: color ?? Colors.white,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: ls,
        );
        final parts = <String, Widget>{
          'city': fit(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.near_me_rounded,
                  size: 56,
                  color: Colors.white,
                ),
                const SizedBox(width: 14),
                Text(
                  w.city,
                  maxLines: 1,
                  style: t(80, FontWeight.w600, ls: -1),
                ),
              ],
            ),
          ),
          'temp': fit(
            AnimatedSwitcher(
              // °C <-> °F: the number fades to the other unit
              duration: still ? Duration.zero : Motion.fast,
              child: _temp(w.temperatureCelsius, 400, -12),
            ),
            at: wide ? Alignment.centerLeft : Alignment.bottomLeft,
          ),
          'cond': fit(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(look.icon, size: 64, color: Colors.white),
                const SizedBox(width: 16),
                Text(
                  w.condition,
                  maxLines: 1,
                  style: t(70, FontWeight.w500, ls: -0.8),
                ),
              ],
            ),
          ),
          'hilo': fit(
            Text(
              'H:${_deg(w.highCelsius)}   L:${_deg(w.lowCelsius)}',
              maxLines: 1,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 60,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.6,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        };
        return Stack(
          // parts on the move stay inside the card
          clipBehavior: Clip.hardEdge,
          children: [
            for (final e in parts.entries)
              AnimatedPositioned(
                key: ValueKey(e.key),
                duration: still ? Duration.zero : Motion.verySlow,
                curve: easeOutStrong,
                left: rect(e.key).left,
                top: rect(e.key).top,
                width: rect(e.key).width,
                height: rect(e.key).height,
                child: e.value,
              ),
          ],
        );
      },
    );
  }

  static Map<String, Rect> _weatherRects(
    double w,
    double h,
    bool wide,
    double unit,
  ) {
    if (wide) {
      // sized by the height, so the words are big in landscape too
      final cityH = (h * 0.13).clamp(18.0, 40.0) * 1.3;
      final condH = (h * 0.11).clamp(16.0, 34.0) * 1.35;
      final hiloH = (h * 0.09).clamp(14.0, 28.0) * 1.3;
      final gap = h * 0.03;
      final stack = cityH + condH + hiloH + gap * 2;
      final top = (h - stack) / 2;
      final left = w * 0.5;
      final x = left + h * 0.06;
      final rw = math.max(0.0, w - x);
      return {
        'temp': Rect.fromLTWH(0, 0, left, h),
        'city': Rect.fromLTWH(x, top, rw, cityH),
        'cond': Rect.fromLTWH(x, top + cityH + gap, rw, condH),
        'hilo': Rect.fromLTWH(x, top + cityH + condH + gap * 2, rw, hiloH),
      };
    }
    final cityH = (unit / 12).clamp(16.0, 26.0) * 1.3;
    final condH = (unit / 13).clamp(15.0, 24.0) * 1.4;
    final hiloH = (unit / 15).clamp(14.0, 22.0) * 1.3;
    return {
      'city': Rect.fromLTWH(0, 0, w, cityH),
      'temp': Rect.fromLTWH(
        0,
        cityH,
        w,
        math.max(0.0, h - cityH - condH - hiloH - 8),
      ),
      'cond': Rect.fromLTWH(0, h - condH - hiloH - 2, w, condH),
      'hilo': Rect.fromLTWH(0, h - hiloH, w, hiloH),
    };
  }

  Widget _low(BuildContext context, WeatherSnapshot w, double h) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // as tall as the tile, but never wider than its share beside the
        // words: then it shrinks instead of pushing them off the tile
        Flexible(
          flex: 5,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              // °C <-> °F: the number fades to the other unit
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.fast,
              child: _temp(w.temperatureCelsius, 160, -3),
            ),
          ),
        ),
        SizedBox(width: h * 0.18),
        Expanded(
          flex: 6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(child: _lowLine(w.city, 30)),
              Flexible(
                child: _lowLine(
                  w.condition,
                  26,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              Flexible(
                child: _lowLine(
                  'H:${_deg(w.highCelsius)}  L:${_deg(w.lowCelsius)}',
                  24,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
              if (!compact)
                Padding(
                  padding: EdgeInsets.all(pad),
                  child: _morphing(context, w, look),
                )
              else if (c.maxWidth > c.maxHeight * 1.6)
                // a low, wide tile (Summary beside an open dock): the
                // temperature as tall as the tile, the words beside it, so
                // the number is never the thing squeezed out
                Padding(
                  padding: EdgeInsets.all(pad),
                  child: _low(context, w, c.maxHeight - pad * 2),
                )
              else
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
                          child: AnimatedSwitcher(
                            // °C <-> °F: the number fades to the other unit
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : Motion.fast,
                            child: _temp(
                              w.temperatureCelsius,
                              (unit * 0.42).clamp(56.0, 160.0),
                              -3,
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

/// The low tile: the temperature at full height on the left; the city, the
/// condition and the high and low beside it, each line shrinking to fit.
Widget _lowLine(String text, double size, {Color color = Colors.white}) =>
    FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
    );

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
    this.onRefresh,
    this.refreshing = false,
  });

  final WeatherSnapshot? snapshot;
  final StandbySettings settings;
  final WeatherProblem? problem;

  /// the small refresh button (shown unless turned off in settings)
  final VoidCallback? onRefresh;
  final bool refreshing;

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

  // The refresh button comes into view when the pointer is over the card or it
  // was touched a moment ago, and goes again, so it never sits on the text.
  bool _near = false;
  Timer? _hideRefresh;

  void _showRefresh({Duration? forAWhile}) {
    _hideRefresh?.cancel();
    if (!_near) setState(() => _near = true);
    if (forAWhile != null) {
      _hideRefresh = Timer(forAWhile, () {
        if (mounted) setState(() => _near = false);
      });
    }
  }

  void _leaveRefresh() {
    _hideRefresh?.cancel();
    if (_near) setState(() => _near = false);
  }

  @override
  void dispose() {
    _hideRefresh?.cancel();
    super.dispose();
  }

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
    return MouseRegion(
      onEnter: (_) => _showRefresh(),
      onHover: (_) => _showRefresh(),
      onExit: (_) => _leaveRefresh(),
      child: Listener(
        // a touch shows the button for a few seconds (and passes through)
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          if (e.kind == PointerDeviceKind.touch) {
            _showRefresh(forAWhile: const Duration(seconds: 3));
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // removing the second city while its page is shown: particles
            DissolveSwitcher(
              present: _hasSecondCity,
              enabled: widget.page == 3,
              fadeIn: false,
              child: AnimatedSwitcher(
                duration: still ? Duration.zero : Motion.medium,
                switchInCurve: easeOutStrong,
                switchOutCurve: easeOutStrong,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
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
                        translation: Offset(
                          0,
                          (incoming ? dir : -dir) * 0.12 * gone,
                        ),
                        child: Opacity(
                          opacity: anim.value.clamp(0.0, 1.0),
                          child: c,
                        ),
                      );
                    },
                    child: child,
                  );
                },
                child: _page(),
              ),
            ),
            if (widget.onRefresh != null && widget.settings.weatherRefresh > 0)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final shown =
                        widget.settings.weatherRefresh == 2 ||
                        _near ||
                        widget.refreshing;
                    return Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: IgnorePointer(
                          ignoring: !shown,
                          child: AnimatedOpacity(
                            opacity: shown ? 1 : 0,
                            duration: still ? Duration.zero : Motion.quick,
                            curve: easeOutStrong,
                            child: WeatherRefreshButton(
                              onPressed: () {
                                widget.onRefresh!();
                                _showRefresh(
                                  forAWhile: const Duration(seconds: 3),
                                );
                              },
                              refreshing: widget.refreshing,
                              updatedAt:
                                  (widget.page == 3
                                          ? widget.secondSnapshot
                                          : widget.snapshot)
                                      ?.updatedAt,
                              // smaller on a small tile
                              size: box.maxWidth < 220 || box.maxHeight < 160
                                  ? 28
                                  : 36,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
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
        ),
      ),
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
                      colors: [Color(0xFF64D2FF), Palette.yellow],
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

/// A small round button of soft glass that fetches the weather again: a faint
/// white disc over a light blur, one arrow, and "Updated 4 min ago" as its
/// tooltip. The arrow turns once when you press it and keeps turning while the
/// weather is on its way. (The card only shows it near the pointer or after a
/// touch, or always, as chosen in settings.)
class WeatherRefreshButton extends StatefulWidget {
  const WeatherRefreshButton({
    super.key,
    required this.onPressed,
    this.refreshing = false,
    this.updatedAt,
    this.size = 34,
  });

  final VoidCallback onPressed;
  final bool refreshing;
  final DateTime? updatedAt;
  final double size;

  /// "Updated just now", "Updated 4 min ago", "Updated 2 h ago".
  static String ageText(DateTime updatedAt, DateTime now) {
    final d = now.difference(updatedAt);
    if (d.inMinutes < 1) return 'Updated just now';
    if (d.inMinutes < 60) return 'Updated ${d.inMinutes} min ago';
    if (d.inHours < 24) return 'Updated ${d.inHours} h ago';
    return 'Updated ${d.inDays} d ago';
  }

  @override
  State<WeatherRefreshButton> createState() => _WeatherRefreshButtonState();
}

class _WeatherRefreshButtonState extends State<WeatherRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(WeatherRefreshButton old) {
    super.didUpdateWidget(old);
    // keep turning while the weather is on its way, then finish the turn
    if (widget.refreshing && !_turn.isAnimating && !_still) {
      _turn.repeat();
    } else if (!widget.refreshing && old.refreshing) {
      _turn.animateTo(1, curve: Curves.easeOutCubic).whenComplete(() {
        if (mounted) _turn.value = 0;
      });
    }
  }

  bool get _still => MediaQuery.disableAnimationsOf(context);

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _press() {
    tick();
    if (!_still && !_turn.isAnimating) _turn.forward(from: 0);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final at = widget.updatedAt;
    return Semantics(
      button: true,
      label: 'Refresh weather',
      child: Tooltip(
        message: at == null
            ? 'Refresh weather'
            : WeatherRefreshButton.ageText(at, DateTime.now()),
        waitDuration: const Duration(milliseconds: 600),
        child: Pressable(
          scale: 0.9,
          round: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _press,
            child: ClipOval(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: RotationTransition(
                    turns: _turn,
                    child: Icon(
                      Icons.refresh_rounded,
                      size: widget.size * 0.52,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
