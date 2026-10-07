import 'dart:math' as math;

import '../domain/standby_models.dart';

class OffsetSnapshot {
  const OffsetSnapshot(this.dx, this.dy);

  static const zero = OffsetSnapshot(0, 0);

  final double dx;
  final double dy;

  @override
  bool operator ==(Object other) {
    return other is OffsetSnapshot && other.dx == dx && other.dy == dy;
  }

  @override
  int get hashCode => Object.hash(dx, dy);
}

class BurnInProtection {
  const BurnInProtection._();

  /// The pixel shift moves once a minute, never faster, however often the
  /// clock itself redraws (every second when seconds are shown).
  static bool shouldAdvance(DateTime? last, DateTime now) =>
      last == null ||
      last.year != now.year ||
      last.month != now.month ||
      last.day != now.day ||
      last.hour != now.hour ||
      last.minute != now.minute;

  /// Where the whole screen sits at this [tick] (one tick a minute): a slow
  /// orbit. Sine waves with irrational steps never repeat, so unlike a fixed
  /// grid of positions every edge and every glyph is spread across the whole
  /// safe area (10 x 8 points either way; the screen margin is 12) over the
  /// days, instead of sitting on the same few pixels.
  static OffsetSnapshot offsetForTick(int tick, StandbySettings settings) {
    if (!settings.burnInProtection) return OffsetSnapshot.zero;
    final t = tick.toDouble();
    return OffsetSnapshot(
      10 * math.sin(t * 0.7236),
      8 * math.sin(t * 1.1180 + 1.0),
    );
  }
}
