/// Something on screen is taking the keyboard to type (the timer's number
/// pad). While it does, the screen's own shortcuts stand aside, all but Esc
/// and F11, so typing 1 or 2 enters a time instead of changing the panels.
class KeyCapture {
  KeyCapture._();

  static int _holders = 0;

  static bool get active => _holders > 0;

  /// Call [take] when it starts typing and [release] when it goes away.
  static void take() => _holders++;
  static void release() => _holders = _holders > 0 ? _holders - 1 : 0;
}
