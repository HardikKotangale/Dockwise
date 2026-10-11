import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            for (var r = 0; r < _rows.length; r++)
              Expanded(
                child: Row(
                  children: [
                    if (r == 1) const Spacer(flex: 1),
                    for (final ch in _rows[r].split(''))
                      Expanded(
                        flex: 2,
                        child: _Key(label: ch, onTap: () => onChar(ch)),
                      ),
                    if (r == 1) const Spacer(flex: 1),
                    if (r == 2)
                      Expanded(
                        flex: 3,
                        child: _Key(
                          icon: Icons.backspace_outlined,
                          label: 'Backspace',
                          onTap: onBackspace,
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _Key(label: '-', onTap: () => onChar('-')),
                  ),
                  Expanded(
                    flex: 12,
                    child: _Key(label: 'space', onTap: () => onChar(' ')),
                  ),
                  Expanded(
                    flex: 5,
                    child: _Key(
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
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.label, required this.onTap, this.icon});

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
      padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 3),
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
                  ? Icon(widget.icon, size: 20)
                  : Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: widget.label.length > 1 ? 15 : 22,
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
