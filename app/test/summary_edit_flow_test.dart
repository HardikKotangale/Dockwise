import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';

// Remove a Summary widget, open the "+" window, add one back: swiping between
// panels must still work afterwards.
void main() {
  testWidgets('swipes still work after removing and adding a Summary widget', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(932, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.summary,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    // hold a tile: edit mode, then take the second city away
    await tester.longPress(find.textContaining('Here').first);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byIcon(Icons.remove_rounded).at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // the "+" opens the Add window; pick the widget that was left out
    await tester.tap(find.text('Add a widget')); // the dashed "+" tile
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Second city'), findsOneWidget); // the window is open
    await tester.tap(find.text('Second city'));
    await tester.pump(const Duration(milliseconds: 800));

    // still editing, as before the window opened: Done is there
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 600));

    // a sideways swipe must change the panel
    await tester.flingFrom(const Offset(466, 200), const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Here'),
      findsNothing,
      reason: 'still on Summary: the swipe was ignored',
    );
  });
}
