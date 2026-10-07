import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/core/screen_fit.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/standby_screen.dart';

void main() {
  test('the scale follows the short side of the screen', () {
    // iPhone 15: the design size, so nothing is scaled (393 / 390 rounds to 1.01)
    expect(screenScaleFor(const Size(393, 852)), closeTo(1.0, 0.02));
    // iPhone 17 Pro Max is about 12% bigger
    expect(screenScaleFor(const Size(440, 956)), closeTo(1.13, 0.01));
    // turning the phone does not change it
    expect(
      screenScaleFor(const Size(956, 440)),
      screenScaleFor(const Size(440, 956)),
    );
    // a tablet grows, but not without limit; a tiny screen shrinks a little
    expect(screenScaleFor(const Size(820, 1180)), 1.8);
    expect(screenScaleFor(const Size(300, 600)), 0.85);
    expect(screenScaleFor(const Size(360, 800)), closeTo(0.92, 0.01));
  });

  testWidgets(
    'ScreenFit lays the app out on the reference size and scales it up',
    (tester) async {
      tester.view.physicalSize = const Size(
        780,
        1560,
      ); // short side 780 -> scale 1.8
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Size? seen;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ScreenFit(child: child!),
          home: Builder(
            builder: (context) {
              seen = MediaQuery.sizeOf(context);
              return Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: GestureDetector(
                    behavior: HitTestBehavior
                        .opaque, // an empty box has no hit area otherwise
                    onTap: () => taps++,
                    child: const SizedBox(width: 100, height: 100),
                  ),
                ),
              );
            },
          ),
        ),
      );
      // the app believes the screen is the smaller reference size...
      expect(seen!.width, closeTo(780 / 1.8, 0.01));
      expect(seen!.height, closeTo(1560 / 1.8, 0.01));
      // ...a 100-point box is drawn 1.8 times as big on the real screen...
      final box = tester.getRect(find.byType(SizedBox).last);
      expect(box.width, closeTo(180, 0.5));
      // ...and touches still land on it
      await tester.tapAt(const Offset(170, 170));
      expect(taps, 1);
      await tester.tapAt(const Offset(190, 190)); // just outside
      expect(taps, 1);
    },
  );

  testWidgets('a normal phone is left exactly as it is', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Size? seen;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ScreenFit(child: child!),
        home: Builder(
          builder: (context) {
            seen = MediaQuery.sizeOf(context);
            return const Scaffold();
          },
        ),
      ),
    );
    expect(seen, const Size(390, 844));
  });

  group('the whole app at real phone sizes', () {
    const phones = {
      // logical size x pixel ratio, as the phones report it
      'iPhone 15': (Size(393, 852), 3.0),
      'iPhone 17 Pro Max': (Size(440, 956), 3.0),
      'iPad mini': (Size(744, 1133), 2.0),
    };
    for (final entry in phones.entries) {
      for (final landscape in [true, false]) {
        testWidgets(
          '${entry.key} ${landscape ? 'landscape' : 'portrait'}: no overflow, fitted to the screen',
          (tester) async {
            SharedPreferences.setMockInitialValues({});
            final logical = entry.value.$1;
            final dpr = entry.value.$2;
            final size = landscape
                ? Size(logical.height, logical.width)
                : logical;
            tester.view.physicalSize = size * dpr;
            tester.view.devicePixelRatio = dpr;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              const StandbyProApp(
                fitScreen: true,
                initialSettings: StandbySettings(),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.takeException(), isNull); // no overflow stripes

            // the app lays itself out on the scaled-down size and fills the screen
            final scale = screenScaleFor(size);
            final laidOut = tester.getSize(find.byType(StandbyScreen));
            expect(laidOut.width, closeTo(size.width / scale, 0.5));
            expect(laidOut.height, closeTo(size.height / scale, 0.5));
            await tester.pumpWidget(const SizedBox()); // stops the timers
          },
        );
      }
    }
  });
}
