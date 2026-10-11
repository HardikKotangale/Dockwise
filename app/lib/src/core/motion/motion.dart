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
