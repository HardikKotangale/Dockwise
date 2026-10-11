import 'package:flutter/material.dart';

import '../../../core/apple.dart';

const dockPadding = EdgeInsets.fromLTRB(20, 4, 20, 24);

class Dock extends StatelessWidget {
  const Dock({
    super.key,
    required this.title,
    required this.handle,
    required this.horizontal,
    required this.child,
    this.solid = false,
  });

  final String title;
  final SpringDockHandle handle;
  final bool horizontal; // landscape: slides sideways
  final Widget child;

  /// A sheet that covers the window: an opaque surface with rounded top
  /// corners, nothing showing through.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    // The header is what you grab to move the panel: dragging the content
    // itself would fight with scrolling.
    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: horizontal
          ? (d) => handle.dragUpdate(d.delta.dx)
          : null,
      onHorizontalDragEnd: horizontal
          ? (d) => handle.dragEnd(d.primaryVelocity ?? 0)
          : null,
      onVerticalDragUpdate: horizontal
          ? null
          : (d) => handle.dragUpdate(d.delta.dy),
      onVerticalDragEnd: horizontal
          ? null
          : (d) => handle.dragEnd(d.primaryVelocity ?? 0),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      height: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Done',
                  onPressed: handle.dismiss,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    foregroundColor: Colors.white70,
                  ),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // Material (not a decorated box) so list tiles can paint ink inside.
    if (solid) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF0B0B0D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              header,
              Expanded(child: child),
            ],
          ),
        ),
      );
    }
    return Glass(
      radius: 28,
      opacity: 0.94,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            header,
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
