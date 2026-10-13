import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// A spring described like Apple does: damping ratio (1 = no bounce) and
/// response in seconds (lower = snappier).
SpringDescription appleSpring({double damping = 1, double response = 0.4}) {
  final stiffness = _sq(2 * 3.141592653589793 / response);
  return SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: stiffness,
    ratio: damping,
  );
}

double _sq(double x) => x * x;

/// Where a flick that lets go at [velocity] (px/s) would come to rest, using
/// scroll-style exponential deceleration.
double projectMomentum(double velocity, {double decelerationRate = 0.998}) =>
    (velocity / 1000) * decelerationRate / (1 - decelerationRate);

/// Resistance past an edge: the further you pull, the less it follows.
double rubberBand(double overshoot, double dimension, {double c = 0.55}) =>
    (overshoot * dimension * c) / (dimension + c * overshoot.abs());

/// A quiet tick for a meaningful moment (a snap, a switch), never for chatter.
void tick() => HapticFeedback.selectionClick();

/// A strong ease-out for things arriving or answering a touch: it starts fast,
/// so it feels responsive, then settles. (Built-in Curves.easeOut is too weak.)
const easeOutStrong = Cubic(0.23, 1, 0.32, 1);

/// One small bounce, for things that spring back (the skill's --ease-bounce).
const easeBounce = Cubic(0.34, 1.36, 0.64, 1);

/// The motion scale every transition picks from (transitions.dev tokens).
class Motion {
  const Motion._();
  static const quick = Duration(milliseconds: 150); // presses, closes
  static const fast = Duration(milliseconds: 250); // most opens and swaps
  static const medium = Duration(milliseconds: 350); // panels, morph fades
  static const slow = Duration(milliseconds: 400); // panels opening
  static const verySlow = Duration(milliseconds: 500); // emphasis, morph moves
}

/// [d], or no time at all when the person turned animations off.
Duration calm(BuildContext context, Duration d) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
