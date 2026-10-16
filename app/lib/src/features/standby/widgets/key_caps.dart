import 'package:flutter/material.dart';

/// A keyboard key drawn as a small key cap.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, this.lit = false});

  final String label;

  /// the key is the one that will be used right now
  final bool lit;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 28),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: lit ? 0.18 : 0.08),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        height: 1.1,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: lit ? 0.95 : 0.7),
        decoration: TextDecoration.none,
      ),
    ),
  );
}

/// Keys and what they do, as one quiet line: [0] - [9] type the time.
class KeyHint extends StatelessWidget {
  const KeyHint({
    super.key,
    required this.keys,
    required this.label,
    this.range = false,
  });

  final List<String> keys;
  final String label;
  final bool range; // two keys shown as 0 - 9

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      KeyCap(keys.first),
      if (range) ...[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '-',
            style: TextStyle(
              color: Colors.white38,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        KeyCap(keys.last),
      ] else
        for (final k in keys.skip(1)) ...[const SizedBox(width: 4), KeyCap(k)],
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          color: Colors.white54,
          decoration: TextDecoration.none,
        ),
      ),
    ],
  );
}
