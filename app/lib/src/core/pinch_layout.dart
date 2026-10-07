import '../domain/standby_models.dart';

/// Two-finger pinch switches the layout, like zooming: spread the fingers to
/// zoom into one panel, pinch them together to see two. (Two fingers never
/// clash with the one-finger swipes that change a card, or with Android's
/// swipe-up-for-home gesture.)
class PinchLayout {
  const PinchLayout._();

  /// The layout a pinch asks for, from the distance between the two fingers
  /// when the second one touched down and when the first one lifted; null if
  /// the fingers hardly moved apart or together.
  static StandbyLayoutMode? layoutFor(
    double startDistance,
    double endDistance,
  ) {
    if (startDistance < 30) return null; // too close to tell what happened
    final ratio = endDistance / startDistance;
    if (ratio >= 1.3) return StandbyLayoutMode.single; // spread
    if (ratio <= 0.77) return StandbyLayoutMode.duo; // pinch
    return null;
  }
}
