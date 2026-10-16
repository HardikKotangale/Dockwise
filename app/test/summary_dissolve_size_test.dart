import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/core/motion/dissolve.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/summary_card.dart';

// Removing the second city: while its tile dissolves it must stay as big as
// its place on the panel (the Here tile's size), not shrink to its content.
void main() {
  Widget panel(String zone) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1000,
        height: 640,
        child: SummaryCard(
          now: DateTime(2026, 10, 15, 22, 0),
          settings: StandbySettings(
            summaryLayout: 'v2:here,there,date,weather,music',
            worldZone: zone,
            worldCity: zone.isEmpty ? '' : 'Nagpur',
          ),
          weather: const SizedBox(),
          music: const SizedBox(),
        ),
      ),
    ),
  );

  testWidgets('the dissolving second-city tile keeps its place size', (
    tester,
  ) async {
    await tester.pumpWidget(panel('Asia/Kolkata'));
    await tester.pump(const Duration(seconds: 1));
    List<Size> sizes(Finder f) => [
      for (final e in f.evaluate())
        tester.getSize(find.byElementPredicate((x) => x == e)),
    ];
    final cells = find.byType(DissolveSwitcher);
    final before = sizes(cells);
    await tester.pumpWidget(panel(''));
    await tester.pump(const Duration(milliseconds: 300));
    // each tile's picture-holder (the Opacity inside) is as big as its cell
    final inner = find.descendant(of: cells, matching: find.byType(Opacity));
    expect(sizes(inner).first, before.first);
    await tester.pumpAndSettle();
  });
}
