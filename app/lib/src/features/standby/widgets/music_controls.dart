import 'dart:async';
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
    this.nudge = 0,
    this.playing,
    this.holdLabel,
    this.loadHoldLabel,
  });

  final IconData icon;
  final String label;
  final double size;
  final bool filled;
  final VoidCallback onPressed;

  /// -1 / +1: the icon hops that way when pressed (previous / next); 0: none
  final int nudge;

  /// non-null: this is the Play/Pause button, morphing as this changes
  final bool? playing;

  /// text for the hold label; defaults to [label]
  final String? holdLabel;
  final Future<String?> Function()? loadHoldLabel;

  @override
  State<TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<TransportButton>
    with SingleTickerProviderStateMixin {
  bool _hop = false;
  Timer? _back;
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: Motion.fast,
    value: widget.playing == true ? 1 : 0,
  );

  @override
  void didUpdateWidget(TransportButton old) {
    super.didUpdateWidget(old);
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
    _back?.cancel();
    _morph.dispose();
    super.dispose();
  }

  void _pressed() {
    tick();
    if (widget.nudge != 0 && !MediaQuery.disableAnimationsOf(context)) {
      setState(() => _hop = true);
      _back?.cancel();
      _back = Timer(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _hop = false);
      });
    }
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.filled ? Colors.black : Colors.white;
    final glyph = widget.playing != null
        ? AnimatedIcon(
            icon: AnimatedIcons.play_pause,
            progress: _morph,
            size: widget.size * 0.55,
            color: color,
          )
        : Icon(widget.icon, size: widget.size * 0.55, color: color);
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
              color: widget.filled ? Colors.white : Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                splashFactory: NoSplash.splashFactory,
                onTap: _pressed,
                child: SizedBox.square(
                  dimension: widget.size,
                  child: AnimatedSlide(
                    // a quick hop one way, then it springs back
                    offset: _hop ? Offset(0.14 * widget.nudge, 0) : Offset.zero,
                    duration: Duration(milliseconds: _hop ? 90 : 300),
                    curve: _hop ? easeOutStrong : easeBounce,
                    child: Center(child: glyph),
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
      : DecorationImage(image: image, fit: BoxFit.cover);
}
