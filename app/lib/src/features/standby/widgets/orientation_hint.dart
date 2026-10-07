import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// How the phone is physically held, from the gravity direction.
enum HeldOrientation { unknown, portrait, landscapeLeft, landscapeRight }

/// Gravity in m/s² along the phone's axes (x right, y up the screen, z out of
/// it; the same signs on Android and iOS) -> how the phone is held.
/// Lying flat, or held upside down, tells us nothing, so those are [unknown].
HeldOrientation classifyHeld(double x, double y, double z) {
  const g = 9.81;
  if (z.abs() > 0.8 * g) return HeldOrientation.unknown; // flat on a table
  if (y > x.abs() + 2) return HeldOrientation.portrait;
  if (x.abs() > y.abs() + 2) {
    // top of the phone turned to the left = Flutter's "landscapeLeft"
    return x > 0
        ? HeldOrientation.landscapeLeft
        : HeldOrientation.landscapeRight;
  }
  return HeldOrientation.unknown;
}

/// A small rotate symbol at the bottom edge. It appears only when the screen is
/// not turned the way the phone is held (typically rotation lock is on) and
/// turns the app that way when tapped. It uses the gravity sensor, so it works
/// even when the system refuses to rotate. Tap again to follow the phone back.
class OrientationHint extends StatefulWidget {
  const OrientationHint({super.key, this.readings, this.onRotate});

  /// Gravity readings (x, y, z); the real sensor unless a test passes its own.
  final Stream<(double, double, double)>? readings;

  /// Turns the app; the default sets Flutter's preferred orientation.
  final ValueChanged<DeviceOrientation>? onRotate;

  @override
  State<OrientationHint> createState() => _OrientationHintState();
}

class _OrientationHintState extends State<OrientationHint> {
  StreamSubscription<(double, double, double)>? _sub;
  Timer? _settle;
  HeldOrientation _candidate = HeldOrientation.unknown;
  HeldOrientation _held = HeldOrientation.unknown; // steady for a moment

  @override
  void initState() {
    super.initState();
    // the real sensor only exists on a phone (not in tests or on a desktop)
    final stream =
        widget.readings ??
        (Platform.isAndroid || Platform.isIOS
            ? accelerometerEventStream().map((e) => (e.x, e.y, e.z))
            : null);
    _sub = stream?.listen(_onReading, onError: (_) {}); // no sensor: no hint
  }

  void _onReading((double, double, double) r) {
    final now = classifyHeld(r.$1, r.$2, r.$3);
    if (now == _candidate) return;
    _candidate = now;
    _settle?.cancel();
    // only act once the phone has been held that way for a moment, so turning
    // it or picking it up does not flash the symbol
    _settle = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _held = _candidate);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _settle?.cancel();
    super.dispose();
  }

  void _rotate(DeviceOrientation to) {
    final f =
        widget.onRotate ?? (o) => SystemChrome.setPreferredOrientations([o]);
    f(to);
  }

  @override
  Widget build(BuildContext context) {
    final screenIsLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final DeviceOrientation? target = switch (_held) {
      HeldOrientation.portrait when screenIsLandscape =>
        DeviceOrientation.portraitUp,
      HeldOrientation.landscapeLeft when !screenIsLandscape =>
        DeviceOrientation.landscapeLeft,
      HeldOrientation.landscapeRight when !screenIsLandscape =>
        DeviceOrientation.landscapeRight,
      _ => null,
    };
    final toLandscape = target != DeviceOrientation.portraitUp;
    return IgnorePointer(
      ignoring: target == null,
      child: AnimatedOpacity(
        opacity: target == null ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: Semantics(
          button: true,
          label: toLandscape ? 'Rotate to landscape' : 'Rotate to portrait',
          child: Tooltip(
            message: toLandscape ? 'Rotate to landscape' : 'Rotate to portrait',
            child: GestureDetector(
              onTap: target == null ? null : () => _rotate(target),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.screen_rotation_alt_rounded,
                  size: 18,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
