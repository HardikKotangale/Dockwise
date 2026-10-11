import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'motion.dart';

/// A glass-like surface: translucent, with a lit top edge, a hairline border
/// and a soft shadow. Bigger surfaces read as thicker (more blur and shadow).
/// With "increase contrast" on, it turns into a solid, clearly outlined card.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.blur = 0,
    this.tint = const Color(0xFF1C1C1E),
    this.opacity = 0.78,
  });

  final Widget child;
  final double radius;

  /// Background blur. Only worth paying for where there is something behind.
  final double blur;
  final Color tint;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final solid = MediaQuery.highContrastOf(context);
    final r = BorderRadius.circular(radius);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        color: solid ? tint : tint.withValues(alpha: opacity),
        gradient: solid
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0, 0.5],
              ),
        border: Border.all(
          color: Colors.white.withValues(alpha: solid ? 0.45 : 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18 + radius,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: r, child: child),
    );
    if (blur > 0 && !solid) {
      body = ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: body,
        ),
      );
    }
    return body;
  }
}

class GlassLabel extends StatelessWidget {
  const GlassLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final label = Glass(
      radius: 14,
      blur: 18,
      opacity: 0.62,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
    if (still) return label;
    // arrives from a little smaller, never from nothing
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: easeOutStrong,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
      ),
      child: label,
    );
  }
}
