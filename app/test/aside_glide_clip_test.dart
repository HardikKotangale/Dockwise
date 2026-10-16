import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/core/motion/aside_glide.dart';

// At rest the dashboard must not be clipped by the box around it: the burn-in
// shift moves it a few points, and a clip there cut off the card's corners.
void main() {
  testWidgets('AsideGlide does not clip its child at rest', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: AsideGlide(
            axis: Axis.horizontal,
            finalExtent: 400,
            child: Transform.translate(
              offset: const Offset(10, 8),
              child: const SizedBox.expand(
                child: ColoredBox(color: Colors.red),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    final clip = t.widget<ClipRect>(
      find.descendant(
        of: find.byType(AsideGlide),
        matching: find.byType(ClipRect),
      ),
    );
    expect(clip.clipBehavior, Clip.none);
  });
}
