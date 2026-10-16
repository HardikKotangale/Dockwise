import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Gives [child] room that grows or shrinks (a dock opening beside it) without
/// laying the child out again on every frame of the move.
///
/// The child is laid out at [finalExtent] along [axis] at once, which is the
/// size it will have when the move has landed. While the room is still moving,
/// a picture of how it looked is stretched into the moving room and fades away
/// as the real child fades in. Laying a big card out afresh at every size (and
/// drawing its large text again each time) is what made a dock opening beside
/// a card stutter.
class AsideGlide extends StatefulWidget {
  const AsideGlide({
    super.key,
    required this.axis,
    required this.finalExtent,
    required this.child,
  });

  /// the direction the room changes in (horizontal: its width)
  final Axis axis;

  /// the size along [axis] the room will settle at
  final double finalExtent;
  final Widget child;

  @override
  State<AsideGlide> createState() => _AsideGlideState();
}

class _AsideGlideState extends State<AsideGlide> {
  final _boundary = GlobalKey();
  ui.Image? _before;
  double _from = 0; // the room's size when the move began

  void _drop() {
    _before?.dispose();
    _before = null;
  }

  @override
  void didUpdateWidget(AsideGlide old) {
    super.didUpdateWidget(old);
    if ((old.finalExtent - widget.finalExtent).abs() < 1) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _drop();
      return;
    }
    // how the child looks right now, before the rebuild changes its size
    _drop();
    final box = _boundary.currentContext?.findRenderObject();
    if (box is RenderRepaintBoundary && box.hasSize && !box.size.isEmpty) {
      try {
        _before = box.toImageSync(
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        _from = widget.axis == Axis.horizontal
            ? box.size.width
            : box.size.height;
      } catch (_) {
        _before = null;
      }
    }
  }

  @override
  void dispose() {
    _before?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    return LayoutBuilder(
      builder: (context, c) {
        final room = horizontal ? c.maxWidth : c.maxHeight;
        final target = widget.finalExtent;
        final before = _before;
        // 0 at the start of the move, 1 when the room has reached its size
        final done = before == null || (target - _from).abs() < 1
            ? 1.0
            : ((room - _from) / (target - _from)).clamp(0.0, 1.0);
        if (before != null && (room - target).abs() < 0.5) {
          // landed: the picture is not needed any more
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (_before != null)) setState(_drop);
          });
        }
        final child = RepaintBoundary(key: _boundary, child: widget.child);
        // Clipped only while it glides. At rest the card must be free to sit
        // outside this box: the burn-in shift moves the whole display a few
        // points, and a clip here cut off the card's corners at the edges.
        return ClipRect(
          clipBehavior: before == null ? Clip.none : Clip.hardEdge,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: horizontal ? target : c.maxWidth,
                height: horizontal ? c.maxHeight : target,
                child: before == null
                    ? child
                    // never fully 0: a card at opacity 0 is not drawn at all, and
                    // the point is to have it drawn once before it is shown
                    : Opacity(
                        opacity: done < 0.004 ? 0.004 : done,
                        child: child,
                      ),
              ),
              if (before != null)
                Positioned(
                  left: 0,
                  top: 0,
                  width: horizontal ? room : c.maxWidth,
                  height: horizontal ? c.maxHeight : room,
                  child: IgnorePointer(
                    child: RawImage(
                      image: before,
                      fit: BoxFit.fill,
                      opacity: AlwaysStoppedAnimation(1 - done),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
