import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/core/motion/dissolve.dart';

// Removing something breaks its picture into particles for a moment, then the
// new content stands alone; with reduce motion it just changes.
void main() {
  Widget host(bool present, {bool reduce = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Scaffold(
        body: Center(
          child: DissolveSwitcher(
            present: present,
            child: present
                ? const SizedBox(width: 200, height: 60, child: Text('Nagpur'))
                : const Text('Tap to add a city'),
          ),
        ),
      ),
    ),
  );

  testWidgets('the old content dissolves, then only the new is left', (
    tester,
  ) async {
    await tester.pumpWidget(host(true));
    expect(find.text('Nagpur'), findsOneWidget);
    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Tap to add a city'), findsOneWidget);
    // the particles are drawn while it runs
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Nagpur'), findsNothing);
    expect(find.text('Tap to add a city'), findsOneWidget);
  });

  testWidgets('with reduce motion it just changes', (tester) async {
    await tester.pumpWidget(host(true, reduce: true));
    await tester.pumpWidget(host(false, reduce: true));
    await tester.pumpAndSettle();
    expect(find.text('Tap to add a city'), findsOneWidget);
  });

  testWidgets('adding it back gathers it from particles', (tester) async {
    await tester.pumpWidget(host(false));
    await tester.pumpWidget(host(true));
    await tester.pump(); // pictured, then the particles gather
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Nagpur'), findsOneWidget);
  });

  testWidgets('while it dissolves the new content keeps the cell size', (
    tester,
  ) async {
    Widget cell(bool present) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 500,
            child: DissolveSwitcher(
              present: present,
              child: Container(key: ValueKey(present), child: const Text('x')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(cell(true));
    await tester.pumpWidget(cell(false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byType(DissolveSwitcher),
              matching: find.byType(Opacity),
            ),
          )
          .height,
      500,
    );
  });
}
