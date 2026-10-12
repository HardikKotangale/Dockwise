import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'core/apple.dart';
import 'core/palette.dart';
import 'core/screen_fit.dart';
import 'domain/standby_models.dart';
import 'features/standby/standby_screen.dart';
import 'features/standby/widgets/battery_badge.dart' show BatteryMonitor;
import 'services/standby_system_service.dart';

class StandbyProApp extends StatelessWidget {
  const StandbyProApp({
    super.key,
    this.initialSettings,
    this.systemService,
    this.battery,
    this.fitScreen = false,
  });

  final StandbySettings? initialSettings;
  final StandbySystemService? systemService; // tests pass a fake
  final BatteryMonitor? battery; // tests pass a fake

  /// Scale the whole app to the screen size (see [ScreenFit]). On in the real
  /// app; off by default so tests keep their exact layouts.
  final bool fitScreen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hushdock',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      scrollBehavior: const AppleScrollBehavior(),
      darkTheme: _appleDark(),
      builder: fitScreen ? (context, child) => ScreenFit(child: child!) : null,
      home: StandbyScreen(
        initialSettings: initialSettings,
        systemService: systemService,
        battery: battery,
      ),
    );
  }
}

const _blue = Palette.blue; // iOS system blue (dark)
const _green = Palette.green; // iOS system green (dark)

/// The whole app in an iOS look: the platform's own font (SF on iPhone), tracking
/// that tightens as text grows, pill-shaped chips and buttons, green switches,
/// thin white sliders, iOS page transitions, and dark glass messages.
ThemeData _appleDark() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.black,
    colorScheme: ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: const Color(0xFF7DD3FC),
      surface: const Color(0xFF07070A),
      primary: _blue,
    ),
  );
  const pill = StadiumBorder();
  return base.copyWith(
    // tighter tracking on big text, a hair of air on small text
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        letterSpacing: -0.6,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        letterSpacing: -0.4,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        letterSpacing: -0.2,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(letterSpacing: -0.1),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(letterSpacing: 0),
      labelSmall: base.textTheme.labelSmall?.copyWith(letterSpacing: 0.3),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    splashFactory: NoSplash.splashFactory, // feedback is a press, not a ripple
    highlightColor: Colors.white.withValues(alpha: 0.06),
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: 0.10),
      thickness: 0.5,
    ),
    listTileTheme: const ListTileThemeData(
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: Colors.white,
      ),
      subtitleTextStyle: TextStyle(fontSize: 13, color: Colors.white54),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? _green : const Color(0xFF39393D),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: Colors.white,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
      thumbColor: Colors.white,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 9,
        elevation: 3,
      ),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide.none,
      showCheckmark: false,
      backgroundColor: Colors.white.withValues(alpha: 0.10),
      selectedColor: _blue,
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: Colors.white,
      ),
      secondaryLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: pill,
        foregroundColor: _blue,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        foregroundColor: _blue,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(highlightColor: Colors.white12),
    ),
    // dark, rounded, floating messages that match the app (not white)
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xF22C2C2E),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w500,
        fontSize: 15,
        letterSpacing: -0.2,
      ),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
    ),
  );
}
