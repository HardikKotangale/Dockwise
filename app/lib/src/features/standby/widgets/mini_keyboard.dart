import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/apple.dart';
import '../../../core/key_capture.dart';

/// Our own translucent letter keyboard for the city search. Lives inside the
/// settings dock, so the system (floating) keyboard never covers the screen.
class MiniKeyboard extends StatelessWidget {
  const MiniKeyboard({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onDone,
  });

  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onDone;

  static const _rows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  // Compact keys on a wide screen, bigger ones on a tall (portrait) one, where
  // there is room; the size glides when the phone is turned.
  static const _compactKey = 36.0;
  static const _roomyKey = 54.0;

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return _PhysicalKeys(
      onChar: onChar,
      onBackspace: onBackspace,
      onDone: onDone,
      child: TweenAnimationBuilder<double>(
      tween: Tween(end: portrait ? 1.0 : 0.0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Motion.medium,
      curve: easeOutStrong,
      builder: (context, t, _) => _build(t),
      ),
    );
  }

  // [t]: 0 = compact keys, 1 = roomy keys
  Widget _build(double t) {
    final keyHeight = _compactKey + (_roomyKey - _compactKey) * t;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < _rows.length; r++)
                  SizedBox(
                    height: keyHeight,
                    child: Row(
                      children: [
                        if (r == 1) const Spacer(flex: 1),
                        for (final ch in _rows[r].split(''))
                          Expanded(
                            flex: 2,
                            child: _Key(
                              label: ch,
                              scale: t,
                              onTap: () => onChar(ch),
                            ),
                          ),
                        if (r == 1) const Spacer(flex: 1),
                        if (r == 2)
                          Expanded(
                            flex: 3,
                            child: _Key(
                              scale: t,
                              icon: Icons.backspace_outlined,
                              label: 'Backspace',
                              onTap: onBackspace,
                            ),
                          ),
                      ],
                    ),
                  ),
                SizedBox(
                  height: keyHeight,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _Key(
                          label: '-',
                          scale: t,
                          onTap: () => onChar('-'),
                        ),
                      ),
                      Expanded(
                        flex: 12,
                        child: _Key(
                          label: 'space',
                          scale: t,
                          onTap: () => onChar(' '),
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: _Key(
                          scale: t,
                          icon: Icons.keyboard_hide_outlined,
                          label: 'Hide keyboard',
                          onTap: onDone,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The same keys as [MiniKeyboard], as a number pad (for the timer): 1-9,
/// 00, 0 and backspace. Keys type the moment the finger lands.
class MiniNumberPad extends StatelessWidget {
  const MiniNumberPad({
    super.key,
    required this.onDigits,
    required this.onBackspace,
    this.keyHeight,
  });

  /// a fixed key height, when there is more room than the default
  final double? keyHeight;
  final ValueChanged<String> onDigits;
  final VoidCallback onBackspace;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['00', '0', '<'],
  ];

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final h = keyHeight ?? (portrait ? 56.0 : 40.0);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in _rows)
                SizedBox(
                  height: h,
                  child: Row(
                    children: [
                      for (final k in row)
                        Expanded(
                          child: k == '<'
                              ? _Key(
                                  icon: Icons.backspace_outlined,
                                  label: 'Backspace',
                                  scale: portrait ? 1 : 0,
                                  onTap: onBackspace,
                                )
                              : _Key(
                                  label: k,
                                  scale: portrait ? 1 : 0,
                                  onTap: () => onDigits(k),
                                ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({
    required this.label,
    required this.onTap,
    this.icon,
    this.scale = 0,
  });

  /// 0 compact .. 1 roomy: the text grows a little with the key
  final double scale;

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    // Letters are lighter keys, space/backspace/hide are darker, like iOS. A
    // key lights up and types the moment the finger touches it, not on release.
    final letter = widget.icon == null && widget.label.length == 1;
    final base = Colors.white.withValues(alpha: letter ? 0.24 : 0.13);
    final lit = Colors.white.withValues(alpha: 0.42);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2.5),
      child: Semantics(
        button: true,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            setState(() => _down = true);
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _down ? lit : base,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: Color(0x59000000), offset: Offset(0, 1)),
              ],
            ),
            child: Center(
              child: widget.icon != null
                  ? Icon(widget.icon, size: 20 + 3 * widget.scale)
                  : Text(
                      widget.label,
                      style: TextStyle(
                        fontSize:
                            (widget.label.length > 1 ? 14 : 19) +
                            4 * widget.scale,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// While our keyboard is up, a real keyboard types into the same field: the
/// screen's one-key shortcuts (N, S, D, ...) stand aside (KeyCapture) and the
/// letters go to [onChar].
class _PhysicalKeys extends StatefulWidget {
  const _PhysicalKeys({
    required this.onChar,
    required this.onBackspace,
    required this.onDone,
    required this.child,
  });

  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_PhysicalKeys> createState() => _PhysicalKeysState();
}

class _PhysicalKeysState extends State<_PhysicalKeys> {
  static final _typable = RegExp(r"^[a-zA-Z0-9 '\-]$");

  @override
  void initState() {
    super.initState();
    KeyCapture.take();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    KeyCapture.release();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return false;
    }
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      widget.onBackspace();
      return true;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (e is KeyDownEvent) widget.onDone();
      return true;
    }
    final ch = e.character;
    if (ch != null && _typable.hasMatch(ch)) {
      widget.onChar(ch.toLowerCase());
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
