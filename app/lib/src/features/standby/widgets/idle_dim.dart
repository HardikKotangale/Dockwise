import 'package:flutter/material.dart';

/// Dims everything under it to about half when [idle]. It fades down slowly
/// (nobody notices) and snaps back quickly on a touch. Touches pass through.
class IdleDim extends StatelessWidget {
  const IdleDim({super.key, required this.idle});

  final bool idle;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: idle ? 0.45 : 0, // black at 45% = the screen at 55%
      duration: Duration(milliseconds: idle ? 3000 : 250),
      child: const ColoredBox(color: Colors.black, child: SizedBox.expand()),
    ),
  );
}
