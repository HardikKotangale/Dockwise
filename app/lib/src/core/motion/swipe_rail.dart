import 'dart:async';

import 'package:flutter/material.dart';

import 'glass.dart';
import 'motion.dart';

/// Tells you where a swipe up or down took you: a small column of dots at the
/// panel's edge (the current one is a long pill) and a glass label naming the
/// new page or style. It appears when [index] changes and fades away again, so
/// nothing stays lit. Put it over the panel; it ignores touches.
class SwipeRail extends StatefulWidget {
  const SwipeRail({super.key, required this.index, required this.labels});

  final int index;

  /// one name per page, in order
  final List<String> labels;

  @override
  State<SwipeRail> createState() => _SwipeRailState();
}

class _SwipeRailState extends State<SwipeRail> {
  bool _visible = false;
  bool _gone = true; // faded out: nothing is built at all
  Timer? _timer;

  @override
  void didUpdateWidget(SwipeRail old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    setState(() {
      _visible = true;
      _gone = false;
    });
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    Duration d(int ms) => still ? Duration.zero : Duration(milliseconds: ms);
    if (_gone) return const SizedBox.shrink();
    final i = widget.index.clamp(0, widget.labels.length - 1);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: d(_visible ? 120 : 400),
            curve: easeOutStrong,
            onEnd: () {
              if (!_visible && mounted) setState(() => _gone = true);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Glass(
                    radius: 99,
                    blur: 14,
                    opacity: 0.58,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: AnimatedSwitcher(
                        duration: d(180),
                        // a small panel shrinks the words to fit, never cuts them
                        child: FittedBox(
                          key: ValueKey(i),
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.labels[i],
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var k = 0; k < widget.labels.length; k++)
                      AnimatedContainer(
                        duration: d(200),
                        curve: easeOutStrong,
                        margin: const EdgeInsets.symmetric(vertical: 2.5),
                        width: 6,
                        height: k == i ? 14 : 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: Colors.white.withValues(
                            alpha: k == i ? 0.95 : 0.35,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
