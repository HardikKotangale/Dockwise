import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';

/// What the screen needs to know about the battery.
typedef BatteryReading = ({int level, bool charging, bool full});

Future<BatteryReading?> readBattery() async {
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
/// prompt. The level moves slowly, so a read every 20 s is plenty (plugging in
/// shows within seconds).
class BatteryMonitor extends ChangeNotifier {
  BatteryMonitor({Future<BatteryReading?> Function()? read, Duration? every})
    : _read = read ?? readBattery {
    refresh();
    _poll = Timer.periodic(every ?? const Duration(seconds: 20), (_) {
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

const _red = Color(0xFFFF453A);
const _green = Color(0xFF30D158);

/// Extremely quiet battery readout for the corner: a hairline battery and a
/// small number. It only appears when there is something to tell: on battery,
/// or charging but not yet full. Green = charging, red = low.
class BatteryBadge extends StatelessWidget {
  const BatteryBadge({super.key, required this.monitor, this.lowAt = 20});

  final BatteryMonitor monitor;

  /// At or below this (and not charging) the badge turns red.
  final int lowAt;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: monitor,
    builder: (context, _) {
      final r = monitor.value;
      if (r == null) return const SizedBox.shrink();
      if (r.full || (r.charging && r.level >= 100)) {
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
          duration: const Duration(milliseconds: 350),
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
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Charge your phone',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Plug it in to keep using Dockwise.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
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
