import 'package:flutter/material.dart';
import 'core/screen_fit.dart';
import 'domain/standby_models.dart';
import 'services/standby_system_service.dart';
import 'features/standby/standby_screen.dart';
import 'features/standby/widgets/battery_badge.dart' show BatteryMonitor;

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
      title: 'Dockwise',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF7DD3FC),
          surface: const Color(0xFF07070A),
        ),
        fontFamily: 'Roboto',
        // dark, rounded, floating messages that match the app (not white)
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xF22C2C2E),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          behavior: SnackBarBehavior.floating,
          insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
      ),
      builder: fitScreen ? (context, child) => ScreenFit(child: child!) : null,
      home: StandbyScreen(
        initialSettings: initialSettings,
        systemService: systemService,
        battery: battery,
      ),
    );
  }
}
