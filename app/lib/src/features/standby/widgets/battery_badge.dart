import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;

import '../../../core/motion/motion.dart';
import '../../../core/palette.dart';

/// What the screen needs to know about the battery.
typedef BatteryReading = ({int level, bool charging, bool full});

Future<BatteryReading?> readBattery() async {
  // Android: ask the system's own battery broadcast, which is fresh to the
  // percent. (The plugin reads a property that lags on some phones.)
  try {
    final m = await const MethodChannel(
      'standby_pro/system',
    ).invokeMapMethod<String, Object?>('batteryInfo');
    if (m != null) {
      return (
        level: m['level'] as int,
        charging: m['charging'] as bool,
        full: m['full'] as bool,
      );
    }
  } on MissingPluginException {
    // not Android: fall through to the plugin
  } on PlatformException {
    // fall through
  }
  try {
    final b = Battery();
    final level = await b.batteryLevel;
    final state = await b.batteryState;
    return (
      level: level,
      charging:
          state == BatteryState.charging ||
          state == BatteryState.connectedNotCharging,
      full: state == BatteryState.full,
    );
  } catch (e) {
    debugPrint('battery read failed: $e');
    return null; // no battery info here (desktop, tests): show nothing
  }
}

/// One shared, light poll of the battery for the badge and the low-battery
/// prompt. The level moves slowly, so a read every 10 s is plenty (plugging in
/// shows within seconds).
class BatteryMonitor extends ChangeNotifier {
  BatteryMonitor({Future<BatteryReading?> Function()? read, Duration? every})
    : _read = read ?? readBattery {
    refresh();
    _poll = Timer.periodic(every ?? const Duration(seconds: 10), (_) {
      refresh();
    });
  }

  final Future<BatteryReading?> Function() _read;
  Timer? _poll;
  bool _disposed = false;
  BatteryReading? value;

  Future<void> refresh() async {
    final r = await _read();
    if (_disposed || r == value) return;
    value = r;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}

const _red = Palette.red;
const _green = Palette.green;

/// Extremely quiet battery readout: a hairline battery and a small number.
/// It only shows when there is something to tell: on battery, or charging but
/// not yet full (unless [always]). Green = charging, red = low.
class BatteryBadge extends StatelessWidget {
  const BatteryBadge({
    super.key,
    required this.monitor,
    this.lowAt = 20,
    this.always = false,
  });

  final BatteryMonitor monitor;

  /// Show even when full on the charger (when asked for on purpose).
  final bool always;

  /// At or below this (and not charging) the badge turns red.
  final int lowAt;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor,
    builder: (context, _) {
      final r = monitor.value;
      if (r == null) return const SizedBox.shrink();
      if (!always && (r.full || (r.charging && r.level >= 100))) {
        return const SizedBox.shrink(); // full on the charger: nothing to say
      }
      final color = !r.charging && r.level <= lowAt
          ? _red
          : r.charging
          ? _green
          : Colors.white54;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${r.level}%',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 5),
          CustomPaint(
            size: const Size(17, 8),
            painter: BatteryGlyph(r.level / 100, color, hairline: true),
          ),
        ],
      );
    },
  );
}

/// The level as a number and a short line, for the free room around the
/// cards (beside the island, or in the side margin): it takes no room from
/// the cards and shows only when there is something to tell (on battery, or
/// charging but not yet full). Green = charging, red = low.
class BatteryLine extends StatelessWidget {
  const BatteryLine({
    super.key,
    required this.monitor,
    this.lowAt = 20,
    this.column = false,
  });

  final BatteryMonitor monitor;
  final int lowAt;

  /// number over the line (a narrow side margin), else side by side
  final bool column;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor,
    builder: (context, _) {
      final r = monitor.value;
      final show = r != null && !(r.full || (r.charging && r.level >= 100));
      final color = r == null
          ? Colors.white54
          : !r.charging && r.level <= lowAt
          ? _red
          : r.charging
          ? _green
          : Colors.white54;
      final number = Text(
        '${r?.level ?? 0}%',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      final line = SizedBox(
        width: 26,
        height: 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedFractionallySizedBox(
              duration: calm(context, Motion.slow),
              curve: easeOutStrong,
              widthFactor: ((r?.level ?? 0) / 100).clamp(0.04, 1.0),
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );
      return ExcludeSemantics(
        excluding: !show,
        child: Semantics(
          label: r == null ? null : 'Battery ${r.level} percent',
          excludeSemantics: true,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: calm(context, Motion.medium),
            child: column
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [number, const SizedBox(height: 4), line],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [number, const SizedBox(width: 6), line],
                  ),
          ),
        ),
      );
    },
  );
}

/// Full-screen "charge your phone" prompt: shown while the battery is at or
/// at or below [lowAt] percent and not charging; goes away by itself once the
/// charger is plugged in.
class LowBatteryAlert extends StatelessWidget {
  const LowBatteryAlert({
    super.key,
    required this.monitor,
    required this.enabled,
    this.lowAt = 20,
  });

  final BatteryMonitor monitor;
  final bool enabled;
  final int lowAt; // the percent the prompt shows at

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor,
    builder: (context, _) {
      final r = monitor.value;
      final show = enabled && r != null && !r.charging && r.level <= lowAt;
      return IgnorePointer(
        ignoring: !show, // while hidden, touches go to the app underneath
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: calm(context, Motion.medium),
          child: show
              ? _LowBatteryPage(level: r.level)
              : const SizedBox.expand(),
        ),
      );
    },
  );
}

class _LowBatteryPage extends StatelessWidget {
  const _LowBatteryPage({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size(150, 74),
                  painter: BatteryGlyph(math.max(level, 4) / 100, _red),
                ),
                const SizedBox(height: 28),
                Text(
                  '$level%',
                  style: const TextStyle(
                    color: _red,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  // a laptop is not a phone
                  defaultTargetPlatform == TargetPlatform.android ||
                          defaultTargetPlatform == TargetPlatform.iOS
                      ? 'Charge your phone'
                      : 'Charge your laptop',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.9,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Plug it in to keep using Hushdock.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A battery drawn as an outline with a fill for the level.
class BatteryGlyph extends CustomPainter {
  BatteryGlyph(this.fraction, this.color, {this.hairline = false});
  final double fraction;
  final Color color;
  final bool hairline;

  @override
  void paint(Canvas canvas, Size size) {
    final nub = size.height * 0.2;
    final body = Rect.fromLTWH(0, 0, size.width - nub, size.height);
    final radius = Radius.circular(size.height * (hairline ? 0.3 : 0.28));
    final stroke = hairline ? 0.9 : size.height * 0.055;
    canvas.drawRRect(
      RRect.fromRectAndRadius(body.deflate(stroke / 2), radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: hairline ? 0.55 : 0.8),
    );
    final gap = stroke + (hairline ? 0.9 : size.height * 0.07);
    final inner = body.deflate(gap);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          inner.left,
          inner.top,
          inner.width * fraction.clamp(0.0, 1.0),
          inner.height,
        ),
        Radius.circular(radius.x * 0.5),
      ),
      Paint()..color = color,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          body.width + nub * 0.25,
          size.height * 0.32,
          nub * 0.75,
          size.height * 0.36,
        ),
        Radius.circular(nub * 0.4),
      ),
      Paint()..color = color.withValues(alpha: hairline ? 0.55 : 0.8),
    );
  }

  @override
  bool shouldRepaint(BatteryGlyph old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.hairline != hairline;
}
