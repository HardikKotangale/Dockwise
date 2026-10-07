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
        borderRadius: BorderRadius.circular(16),
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

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          // translucent so the panels behind the dock stay in view
          color: Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 20)
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: label.length > 1 ? 14 : 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
