import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../core/apple.dart';
import '../../../domain/standby_models.dart';

/// The album cover: a rounded square with a soft shadow. Without a cover
/// (or while it loads) a quiet placeholder, never a blank or a circle.
class AlbumCover extends StatelessWidget {
  const AlbumCover({super.key, required this.art});

  final DecorationImage? art;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.10),
        image: art,
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 26,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: art == null
          ? const Center(
              child: Icon(
                Icons.music_note_rounded,
                size: 44,
                color: Colors.white38,
              ),
            )
          : null,
    );
  }
}

/// One transport control. Press feedback is a quick spring and a soft glow
/// behind it; Play/Pause is a real morph between the two shapes; Previous and
/// Next hop a little in their direction; holding names the button in a glass
/// label (Next can say which song is coming).
class TransportButton extends StatefulWidget {
  const TransportButton({
    super.key,
    required this.icon,
    required this.label,
    required this.size,
    required this.onPressed,
    this.filled = false,
    this.tint,
    this.nudge = 0,
    this.playing,
    this.holdLabel,
    this.loadHoldLabel,
    this.pulse,
  });

  final IconData icon;
  final String label;
  final double size;
  final bool filled;

  /// the filled button's colour (white when null); the arrow turns black or
  /// white to stay readable on it
  final Color? tint;
  final VoidCallback onPressed;

  /// -1 / +1: the icon hops that way when pressed (previous / next); 0: none
  final int nudge;

  /// non-null: this is the Play/Pause button, morphing as this changes
  final bool? playing;

  /// text for the hold label; defaults to [label]
  final String? holdLabel;
  final Future<String?> Function()? loadHoldLabel;

  /// bumped when this control's key is pressed: it plays its press animation
  final ValueListenable<int>? pulse;

  @override
  State<TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<TransportButton>
    with TickerProviderStateMixin {
  // one burst per press: a bloom of light that swells and fades, and for Previous / Next
  // the arrow leaving one side while a new one arrives from the other
  late final AnimationController _fx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: widget.playing == true ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    widget.pulse?.addListener(_keyPressed);
  }

  // its key was pressed: the same bloom and hop as a press
  void _keyPressed() {
    if (mounted && !MediaQuery.disableAnimationsOf(context)) {
      _fx.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(TransportButton old) {
    super.didUpdateWidget(old);
    if (old.pulse != widget.pulse) {
      old.pulse?.removeListener(_keyPressed);
      widget.pulse?.addListener(_keyPressed);
    }
    final p = widget.playing;
    if (p == null || p == old.playing) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _morph.value = p ? 1 : 0;
    } else {
      _morph.animateTo(p ? 1 : 0, curve: easeOutStrong);
    }
  }

  @override
  void dispose() {
    widget.pulse?.removeListener(_keyPressed);
    _fx.dispose();
    _morph.dispose();
    super.dispose();
  }

  void _pressed() {
    tick();
    if (!MediaQuery.disableAnimationsOf(context)) _fx.forward(from: 0);
    widget.onPressed();
  }

  Widget _glyph(Color color, double t) {
    final size = widget.size * 0.55;
    if (widget.playing != null) {
      // the shape morphs and the button swells a little while it does
      return Transform.scale(
        scale: 1 + 0.16 * math.sin(math.pi * _morph.value),
        child: AnimatedIcon(
          icon: AnimatedIcons.play_pause,
          progress: _morph,
          size: size,
          color: color,
        ),
      );
    }
    final icon = Icon(widget.icon, size: size, color: color);
    if (widget.nudge == 0 || t == 0 || t == 1) return icon;
    // skip: the arrow slides out the way it points, a fresh one slides in
    final e = Curves.easeOutCubic.transform(t);
    final dist = widget.size * 0.42 * widget.nudge;
    return ClipOval(
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: Offset(dist * e, 0),
              child: Opacity(opacity: (1 - e).clamp(0.0, 1.0), child: icon),
            ),
            Transform.translate(
              offset: Offset(-dist * (1 - e), 0),
              child: Opacity(opacity: e.clamp(0.0, 1.0), child: icon),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.tint ?? Colors.white;
    final color = widget.filled
        ? (ThemeData.estimateBrightnessForColor(fill) == Brightness.light
              ? Colors.black
              : Colors.white)
        : (widget.tint ?? Colors.white);
    final glow = widget.tint ?? Colors.white;
    return HoldLabel(
      label: widget.holdLabel ?? widget.label,
      loadLabel: widget.loadHoldLabel,
      child: Semantics(
        button: true,
        label: widget.label,
        child: Tooltip(
          message: widget.label,
          // the glass label does this job on a hold; the tooltip is for mice
          triggerMode: TooltipTriggerMode.manual,
          child: Pressable(
            scale: 0.92,
            highlight: !widget.filled,
            round: true,
            child: Material(
              color: widget.filled ? fill : Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                splashFactory: NoSplash.splashFactory,
                onTap: _pressed,
                child: SizedBox.square(
                  dimension: widget.size,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_fx, _morph]),
                    builder: (context, _) {
                      final t = _fx.value;
                      return Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // a soft bloom of the accent swells from the middle
                          // and melts away: light, not a ring
                          if (t > 0 && t < 1)
                            IgnorePointer(
                              child: Transform.scale(
                                scale:
                                    0.55 +
                                    0.85 * Curves.easeOutCubic.transform(t),
                                child: Container(
                                  width: widget.size,
                                  height: widget.size,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        glow.withValues(
                                          alpha: 0.55 * math.pow(1 - t, 1.6),
                                        ),
                                        glow.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          _glyph(color, t),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

DecorationImage? coverArt(NowPlayingSnapshot s) {
  final ImageProvider? image = s.artBytes != null
      ? MemoryImage(s.artBytes!)
      : s.artUrl != null
      ? NetworkImage(s.artUrl!)
      : null;
  return image == null
      ? null
      // high: the cover is drawn larger than Spotify's 640 px on a big
      // screen, and smooth (not pixelated) scaling matters there
      : DecorationImage(
          image: image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        );
}
