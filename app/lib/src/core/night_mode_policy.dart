import 'package:flutter/painting.dart' show ColorFilter;

import '../domain/standby_models.dart';

class NightModePolicy {
  const NightModePolicy._();

  static bool shouldTint(DateTime now, StandbySettings settings) {
    if (!settings.nightModeEnabled) return false;
    final m = now.hour * 60 + now.minute;
    final start = settings.nightStartMin, end = settings.nightEndMin;
    if (start == end) return false;
    // the window can run past midnight (8 pm to 7 am)
    return start < end ? m >= start && m < end : m >= start || m < end;
  }

  /// Night look: colors fade toward a dim warm red with no blue light (easy on
  /// the eyes in a dark room). [strength] 0 = a little, 1 = fully red.
  static ColorFilter filter(StandbySettings settings) {
    final strength = settings.nightTintIntensity;
    // how much of each pixel's brightness goes to r, g, b
    final toColor = switch (settings.nightTint) {
      'amber' => const [0.95, 0.45, 0.0],
      'theme' => [
        settings.theme.clockColor.r,
        settings.theme.clockColor.g,
        settings.theme.clockColor.b,
      ],
      _ => const [0.85, 0.14, 0.0],
    };
    final s = (0.5 + 0.5 * strength).clamp(
      0.0,
      1.0,
    ); // even the default is mostly red
    const lum = [
      0.30,
      0.59,
      0.11,
    ]; // brightness of a pixel = these x its r, g, b
    double cell(int out, int inp) =>
        (1 - s) * (out == inp ? 1 : 0) + s * toColor[out] * lum[inp];
    return ColorFilter.matrix([
      for (var out = 0; out < 3; out++) ...[
        cell(out, 0), cell(out, 1), cell(out, 2), 0, 0, //
      ],
      0,
      0,
      0,
      1,
      0,
    ]);
  }
}
