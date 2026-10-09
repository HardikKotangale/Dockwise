import 'dart:math' as math;

/// Screen brightness (0..1) for a room with [lux] of light, never above
/// [maxBrightness] (the user's own brightness setting, used in bright light).
/// Human eyes judge light on a log scale, so this does too: a dark bedroom
/// (about 1 lux) gets about a fifth of the maximum, a lamp-lit room (about 50
/// lux) about two thirds, and daylight (1000 lux or more) the full amount.
double roomBrightness(double lux, double maxBrightness) {
  final f = (math.log(lux.clamp(0, 100000) + 1) / math.ln10 / 3).clamp(
    0.0,
    1.0,
  );
  return (maxBrightness * (0.10 + 0.90 * f)).clamp(0.05, 1.0);
}

/// Is the room dark enough for the night look? Two thresholds, so a lux value
/// hovering near the line does not flip the look back and forth.
bool isDarkRoom(double lux, {required bool wasDark}) =>
    wasDark ? lux < 20 : lux < 8;
