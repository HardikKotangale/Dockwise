/// Apple-style motion and materials, from the WWDC "Designing Fluid
/// Interfaces" ideas: springs (not fixed-duration curves), motion that keeps
/// the finger's velocity, momentum projection, rubber-banding, and feedback on
/// touch-down. Everything here is interruptible: animations start from the
/// live on-screen value.
library;

export 'motion/glass.dart';
export 'motion/hold_label.dart';
export 'motion/materialize.dart';
export 'motion/morph_layout.dart';
export 'motion/motion.dart';
export 'motion/page_dots.dart';
export 'motion/pressable.dart';
export 'motion/scroll_behavior.dart';
export 'motion/split_panels.dart';
export 'motion/spring_dock.dart';
export 'motion/swipe_rail.dart';
