import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../core/motion/motion.dart';

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
  const OrientationHint({
    super.key,
    this.readings,
    this.onRotate,
    this.mirrorLandscape,
    this.screenSide,
    this.auto = false,
  });

  /// Turn the screen by itself to follow the phone (the symbol stays as a
  /// manual fallback). Off in tests unless asked for.
  final bool auto;

  /// Which landscape the screen is in right now (the side the TOP of the phone
  /// is turned to, like the sensor reports it), or null when unknown. Needed to
  /// notice the phone being flipped 180 degrees while rotation is locked.
  final Future<HeldOrientation?> Function()? screenSide;

  /// iOS names its landscapes after the HOME-BUTTON side (the opposite of
  /// Android and of how the sensor sees it), so on iPhone left and right must
  /// be swapped or the screen turns the wrong way round. Null = decide by
  /// platform; tests pass a value.
  final bool? mirrorLandscape;

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
  Timer? _recheck;
  HeldOrientation? _autoFor; // the holding we already turned the screen for
  HeldOrientation _candidate = HeldOrientation.unknown;
  HeldOrientation _held = HeldOrientation.unknown; // steady for a moment
  HeldOrientation? _side; // which landscape the screen is in (null: unknown)

  Future<HeldOrientation?> _readSide() async {
    final f = widget.screenSide ?? _nativeSide;
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  static Future<HeldOrientation?> _nativeSide() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return null;
    final s = await const MethodChannel(
      'standby_pro/system',
    ).invokeMethod<String>('screenSide');
    return switch (s) {
      'landscapeLeft' => HeldOrientation.landscapeLeft,
      'landscapeRight' => HeldOrientation.landscapeRight,
      'portrait' => HeldOrientation.portrait,
      _ => null,
    };
  }

  // iOS names its landscapes the other way round (see [mirrorLandscape])
  DeviceOrientation _landscapeFor(HeldOrientation h) {
    final mirror = widget.mirrorLandscape ?? Platform.isIOS;
    final left = (h == HeldOrientation.landscapeLeft) != mirror;
    return left
        ? DeviceOrientation.landscapeLeft
        : DeviceOrientation.landscapeRight;
  }

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
    GestureBinding.instance.pointerRouter.addGlobalRoute(_touched);
  }

  void _onReading((double, double, double) r) {
    final now = classifyHeld(r.$1, r.$2, r.$3);
    if (now == _candidate) return;
    _candidate = now;
    _settle?.cancel();
    // only act once the phone has been held that way for a moment, so turning
    // it or picking it up does not flash the symbol
    _arm();
  }

  // Swiping or tapping jostles the phone. While fingers are on the screen, or
  // just were, the readings say nothing about how it is really held, so the
  // wait starts over instead of turning the screen.
  bool _touching = false;
  Timer? _untouch;

  void _touched(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerMoveEvent) {
      _touching = true;
      _untouch?.cancel();
      _untouch = Timer(const Duration(milliseconds: 1500), () {
        _touching = false;
      });
    }
  }

  void _arm() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 1200), () async {
      if (_touching) {
        _arm();
        return;
      }
      final side = await _readSide();
      if (mounted) {
        setState(() {
          _held = _candidate;
          _side = side;
        });
        // Follow the phone by itself: turn it sideways and the screen goes
        // landscape, turn it back and it returns to portrait. Once per way of
        // holding it, so a wrong guess can never flip the screen back and forth.
        final landscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final target = _decide(landscape).target;
        if (widget.auto && target != null && _autoFor != _held) {
          _autoFor = _held;
          _rotate(target);
        }
      }
    });
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_touched);
    _sub?.cancel();
    _settle?.cancel();
    _recheck?.cancel();
    _untouch?.cancel();
    super.dispose();
  }

  void _rotate(DeviceOrientation to) {
    final f =
        widget.onRotate ?? (o) => SystemChrome.setPreferredOrientations([o]);
    f(to);
    // the screen turns a moment later; look again so the symbol goes away
    _recheck?.cancel();
    _recheck = Timer(const Duration(milliseconds: 900), () async {
      final side = await _readSide();
      if (mounted) setState(() => _side = side);
    });
  }

  // What would put the screen the way the phone is held, if anything.
  // [upsideDown]: the screen is landscape but turned the other way from how the
  // phone is held (flipped 180 degrees while rotation is locked).
  ({DeviceOrientation? target, bool upsideDown}) _decide(
    bool screenIsLandscape,
  ) {
    final heldSideways =
        _held == HeldOrientation.landscapeLeft ||
        _held == HeldOrientation.landscapeRight;
    final upsideDown =
        screenIsLandscape &&
        heldSideways &&
        (_side == HeldOrientation.landscapeLeft ||
            _side == HeldOrientation.landscapeRight) &&
        _side != _held;
    final target = upsideDown
        ? _landscapeFor(_held)
        : switch (_held) {
            HeldOrientation.portrait when screenIsLandscape =>
              DeviceOrientation.portraitUp,
            HeldOrientation.landscapeLeft || HeldOrientation.landscapeRight
                when !screenIsLandscape =>
              _landscapeFor(_held),
            _ => null,
          };
    return (target: target, upsideDown: upsideDown);
  }

  @override
  Widget build(BuildContext context) {
    final screenIsLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final (:target, :upsideDown) = _decide(screenIsLandscape);
    final toLandscape = target != DeviceOrientation.portraitUp;
    final label = upsideDown
        ? 'Flip the screen'
        : toLandscape
        ? 'Rotate to landscape'
        : 'Rotate to portrait';
    return IgnorePointer(
      ignoring: target == null,
      child: AnimatedOpacity(
        opacity: target == null ? 0 : 1,
        duration: calm(context, Motion.fast),
        child: Semantics(
          button: true,
          label: label,
          child: Tooltip(
            message: label,
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
