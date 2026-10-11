import 'dart:async';

import 'package:flutter/material.dart';

import 'glass.dart';
import 'motion.dart';

/// Hold a button and a small glass label names what it does (or what is next),
/// like the labels that float over controls in iOS. It goes when you let go.
class HoldLabel extends StatefulWidget {
  const HoldLabel({
    super.key,
    required this.label,
    required this.child,
    this.loadLabel,
  });

  /// shown at once
  final String label;

  /// asked for while holding; replaces [label] when it answers (e.g. the title
  /// of the next song)
  final Future<String?> Function()? loadLabel;
  final Widget child;

  @override
  State<HoldLabel> createState() => _HoldLabelState();
}

class _HoldLabelState extends State<HoldLabel> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  Timer? _hide;
  String _text = '';

  void _show() {
    _hide?.cancel();
    _text = widget.label;
    _entry?.remove();
    _entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -10),
          showWhenUnlinked: false,
          child: IgnorePointer(child: GlassLabel(text: _text)),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
    tick();
    widget.loadLabel?.call().then((value) {
      if (value != null && value.isNotEmpty && _entry != null) {
        _text = value;
        _entry!.markNeedsBuild();
      }
    });
  }

  void _release() {
    // linger a moment, so a quick hold can still be read
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 900), _remove);
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide?.cancel();
    _remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (_) => _show(),
        onLongPressEnd: (_) => _release(),
        onLongPressCancel: _release,
        child: widget.child,
      ),
    );
  }
}
