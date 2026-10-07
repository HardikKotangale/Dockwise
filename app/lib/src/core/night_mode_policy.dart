import 'package:flutter/painting.dart' show ColorFilter;

import '../domain/standby_models.dart';

class NightModePolicy {
  const NightModePolicy._();

  /// [dark]: the room is dark right now (from the light sensor, Android).
  static bool shouldTint(
    DateTime now,
    StandbySettings settings, {
    bool dark = false,
  }) {
    if (!settings.nightModeEnabled) return false;
    if (dark && settings.nightByLight) return true;
    final m = now.hour * 60 + now.minute;
    final start = settings.nightStartMin, end = settings.nightEndMin;
    if (start == end) return false;
    // the window can run past midnight (8 pm to 7 am)
    return start < end ? m >= start && m < end : m >= start || m < end;
  }

  /// Night look: colors fade toward a dim warm red with no blue light (easy on
  /// the eyes in a dark room). [strength] 0 = a little, 1 = fully red.
  /// How much of a pixel's brightness goes to red, green and blue for the
  /// chosen night tint. "Theme color" follows the accent color you pick in
  /// Settings > Theme, so changing that color changes the night look too.
  static List<double> tintOf(StandbySettings settings) =>
      switch (settings.nightTint) {
        'amber' => const [0.95, 0.45, 0.0],
        'theme' => [
          settings.appAccentInk.r,
          settings.appAccentInk.g,
          settings.appAccentInk.b,
        ],
        _ => const [0.85, 0.14, 0.0],
      };

  static ColorFilter filter(StandbySettings settings) {
    final strength = settings.nightTintIntensity;
    final toColor = tintOf(settings);
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
