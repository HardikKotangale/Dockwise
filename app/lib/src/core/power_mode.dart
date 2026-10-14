import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

/// Whether the screen may spend a little more on looks right now: a PC on
/// mains power (or one with no battery at all). On battery, and on phones,
/// everything keeps its light, battery-friendly settings.
class RichGraphics extends InheritedWidget {
  const RichGraphics({super.key, required this.on, required super.child});

  final bool on;

  /// [onBattery]: running from the battery right now (false when plugged in,
  /// or when this machine reports no battery).
  static bool allowed({required bool onBattery}) =>
      !onBattery &&
      const {
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RichGraphics>()?.on ?? false;

  @override
  bool updateShouldNotify(RichGraphics oldWidget) => oldWidget.on != on;
}
