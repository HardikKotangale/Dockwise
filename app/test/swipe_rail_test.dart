import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/core/apple.dart';
import 'package:standby_pro/src/domain/standby_models.dart';

void main() {
  Widget host(int index) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 300,
        child: Stack(
          children: [
            Positioned.fill(
              child: SwipeRail(
                index: index,
                labels: const ['One', 'Two', 'Three'],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  double shown(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
      .opacity;

  testWidgets('hidden until the page changes, then names it and fades away', (
    tester,
  ) async {
    await tester.pumpWidget(host(0));
    expect(find.byType(AnimatedOpacity), findsNothing); // nothing built at rest
    expect(find.text('One'), findsNothing);
    await tester.pumpWidget(host(1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(shown(tester), 1);
    expect(find.text('Two'), findsOneWidget); // tells what it is
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Two'), findsNothing); // gone again
  });

  testWidgets('swiping the clock up shows the new style by name', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(layoutMode: StandbyLayoutMode.single),
      ),
    );
    await tester.pump();
    expect(find.text('Analog'), findsNothing);
    await tester.fling(find.byType(Scaffold), const Offset(0, -200), 1500);
    await tester.pump(const Duration(milliseconds: 300));
    // digital -> analog: the rail says so
    expect(find.text('Analog'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
