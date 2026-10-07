import 'package:flutter/widgets.dart';

/// The short side, in logical points, of the phone the layout is designed on
/// (an iPhone 15 is 393 wide). On a screen like that, nothing is scaled.
const double referenceShortSide = 390;

/// How much the whole interface is scaled on a screen of this [size]: 1 on a
/// normal phone, more on a bigger one (an iPhone 17 Pro Max, a tablet), a
/// little less on a small one. It uses the shorter side, so turning the phone
/// does not change it.
double screenScaleFor(Size size) {
  final scale = (size.shortestSide / referenceShortSide).clamp(0.85, 1.8);
  // two decimals, so tiny differences never make the layout jump around
  return (scale * 100).round() / 100;
}

/// Reads the screen size once and lays the whole app out as if the screen were
/// the reference phone, then scales the result up or down to the real screen.
/// So every card, margin, icon and text grows or shrinks together, and a 15 and
/// a 17 Pro Max show the same composition at their own size.
class ScreenFit extends StatelessWidget {
  const ScreenFit({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final scale = screenScaleFor(mq.size);
    if (scale == 1.0) return child;
    // the app thinks the screen is this size (and so do its safe areas)...
    final virtual = Size(mq.size.width / scale, mq.size.height / scale);
    return FittedBox(
      fit: BoxFit.fill, // ...and it is stretched evenly onto the real screen
      child: SizedBox.fromSize(
        size: virtual,
        child: MediaQuery(
          data: mq.copyWith(
            size: virtual,
            padding: mq.padding / scale,
            viewPadding: mq.viewPadding / scale,
            viewInsets: mq.viewInsets / scale,
            systemGestureInsets: mq.systemGestureInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}
