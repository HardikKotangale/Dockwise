import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/clock_faces.dart';
import 'package:standby_pro/src/features/standby/widgets/mini_keyboard.dart';

void main() {
  Widget keyboard() => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: MiniKeyboard(onChar: (_) {}, onBackspace: () {}, onDone: () {}),
      ),
    ),
  );

  double keyHeight(WidgetTester tester) => tester
      .getSize(
        find
            .ancestor(of: find.text('q'), matching: find.byType(DecoratedBox))
            .first,
      )
      .height;

  testWidgets('the keys are bigger in portrait than in landscape', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpWidget(keyboard());
    await tester.pumpAndSettle();
    final landscape = keyHeight(tester);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    final portrait = keyHeight(tester);
    expect(portrait, greaterThan(landscape + 10));
  });

  testWidgets('turning the phone makes the keys grow smoothly, not at once', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpWidget(keyboard());
    await tester.pumpAndSettle();
    final from = keyHeight(tester);
    tester.view.physicalSize = const Size(400, 800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final mid = keyHeight(tester);
    await tester.pumpAndSettle();
    final to = keyHeight(tester);
    expect(mid, greaterThan(from));
    expect(mid, lessThan(to));
  });

  testWidgets(
    'the world clock stacks each time in portrait so it fills the height',
    (tester) async {
      Widget at(Size panel) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: panel,
              child: ClockFace(
                time: DateTime(2026, 10, 11, 10, 9),
                settings: const StandbySettings(
                  clockStyle: ClockStyle.world,
                  layoutMode: StandbyLayoutMode.single,
                  use24HourTime: true,
                  worldZone: 'Asia/Tokyo',
                  worldCity: 'Tokyo',
                ),
              ),
            ),
          ),
        ),
      );
      // sizes as drawn (the face is scaled to fit), not as laid out
      double drawnHeight(WidgetTester t, Finder f) =>
          t.getBottomRight(f).dy - t.getTopLeft(f).dy;
      double digits(WidgetTester t) =>
          drawnHeight(t, find.text('10')); // the hour of the first city

      await tester.pumpWidget(at(const Size(800, 300)));
      await tester.pumpAndSettle();
      final wide = digits(tester);
      await tester.pumpWidget(at(const Size(360, 700)));
      await tester.pumpAndSettle();
      final tall = digits(tester);
      // fills the tall panel: from the first label to the last digits
      final texts = find.descendant(
        of: find.byType(ClockFace),
        matching: find.byType(RichText),
      );
      var bottom = 0.0;
      for (final e in texts.evaluate()) {
        final d = tester.getBottomRight(find.byWidget(e.widget)).dy;
        if (d > bottom) bottom = d;
      }
      expect(
        bottom - tester.getTopLeft(find.text('Local')).dy,
        greaterThan(450),
      );
      expect(tall, greaterThan(wide)); // the digits are larger than on a line
    },
  );
}
