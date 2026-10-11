import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/core/apple.dart';

void main() {
  test('a flick is projected like scroll deceleration', () {
    expect(projectMomentum(1000), closeTo(499, 1));
    expect(projectMomentum(-1000), closeTo(-499, 1));
    expect(projectMomentum(0), 0);
  });

  test(
    'the rubber band follows less the further you pull, never past the edge',
    () {
      final a = rubberBand(20, 400);
      final b = rubberBand(200, 400);
      expect(a, lessThan(20));
      expect(b, lessThan(200));
      expect(b, greaterThan(a));
      expect(rubberBand(100000, 400), lessThan(400 / 0.55 + 1));
    },
  );

  Future<bool> openDock(
    WidgetTester tester, {
    required void Function() onClosed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SpringDock(
              axis: Axis.horizontal,
              extent: 300,
              onClosed: onClosed,
              builder: (context, h) => Column(
                children: [
                  GestureDetector(
                    key: const Key('header'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) => h.dragUpdate(d.delta.dx),
                    onHorizontalDragEnd: (d) =>
                        h.dragEnd(d.primaryVelocity ?? 0),
                    child: const SizedBox(width: 300, height: 60),
                  ),
                  TextButton(onPressed: h.dismiss, child: const Text('Done')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return true;
  }

  testWidgets('the dock springs open to its full size', (tester) async {
    await openDock(tester, onClosed: () {});
    expect(tester.getSize(find.byType(SpringDock)).width, closeTo(300, 0.01));
  });

  testWidgets('Done slides it away, then reports it closed', (tester) async {
    var closed = 0;
    await openDock(tester, onClosed: () => closed++);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(closed, 0); // still on its way out
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('a flick on the header sends it away', (tester) async {
    var closed = 0;
    await openDock(tester, onClosed: () => closed++);
    await tester.fling(
      find.byKey(const Key('header')),
      const Offset(60, 0),
      1500,
    );
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('a short, slow drag snaps back open', (tester) async {
    var closed = 0;
    await openDock(tester, onClosed: () => closed++);
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('header'))),
    );
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(
      tester.getSize(find.byType(SpringDock)).width,
      lessThan(300),
    ); // follows the finger
    await tester.pump(
      const Duration(milliseconds: 400),
    ); // held still: no velocity
    await g.up();
    await tester.pumpAndSettle();
    expect(closed, 0);
    expect(tester.getSize(find.byType(SpringDock)).width, closeTo(300, 0.01));
  });

  testWidgets('Materialize keeps its child while it is visible', (
    tester,
  ) async {
    Widget app(bool v) => MaterialApp(
      home: Materialize(visible: v, child: const Text('hi')),
    );
    await tester.pumpWidget(app(false));
    expect(find.text('hi'), findsNothing);
    await tester.pumpWidget(app(true));
    expect(find.text('hi'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsNothing);
  });
}
