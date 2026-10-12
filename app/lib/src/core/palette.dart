import 'package:flutter/painting.dart';

/// The few colors the app uses for meaning, in one place (so they can be given
/// high-contrast variants later). They match iOS's dark-appearance system
/// colors; the "text" ones are a touch lighter where they carry a label, to
/// stay above 4.5:1 on their own tint.
class Palette {
  const Palette._();

  static const green = Color(0xFF30D158);
  static const red = Color(0xFFFF453A);
  static const redText = Color(0xFFFF6B63);
  static const orange = Color(0xFFFF9F0A);
  static const blue = Color(0xFF0A84FF);
  static const yellow = Color(0xFFFFD60A);
}
