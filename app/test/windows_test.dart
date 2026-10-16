import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';

// On a PC there is no tilt sensor, no charger watching and no other-app music
// list: the app must start and draw all the same.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final os in [TargetPlatform.windows, TargetPlatform.macOS])
    for (final style in [
      ClockStyle.digital,
      ClockStyle.float,
      ClockStyle.flip,
    ]) {
      testWidgets('starts on ${os.name} with the ${style.name} clock', (
        t,
      ) async {
        debugDefaultTargetPlatformOverride = os;
        try {
          t.view.physicalSize = const Size(1600, 900);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            StandbyProApp(initialSettings: StandbySettings(clockStyle: style)),
          );
          await t.pump(const Duration(seconds: 1));
          expect(t.takeException(), isNull);
          expect(find.byType(Scaffold), findsWidgets);
          await t.pumpWidget(const SizedBox());
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
}
