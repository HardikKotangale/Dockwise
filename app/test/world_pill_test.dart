import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/clock/world_clock.dart';
import 'package:standby_pro/src/features/standby/widgets/clock/zones.dart';

// The World clock (Clock panel, one or two panels) names how far ahead the
// second city is in a pill, as the Summary's tile does.
void main() {
  test('hoursAway words the difference', () {
    initZones();
    final here = timeInZone(DateTime.utc(2026, 10, 16, 15), 'America/Chicago');
    final india = timeInZone(DateTime.utc(2026, 10, 16, 15), 'Asia/Kolkata');
    expect(hoursAway(here, india), '+10.5 h');
    expect(hoursAway(india, here), '−10.5 h');
    expect(hoursAway(here, here), 'Same time');
    final late = timeInZone(DateTime.utc(2026, 10, 16, 21), 'Asia/Kolkata');
    expect(hoursAway(here, late, day: true), '+10.5 h · Tmrw');
  });

  testWidgets('the world clock shows the pill beside the second city', (
    t,
  ) async {
    initZones();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 700,
            child: WorldClockFace(
              time: DateTime(2026, 10, 16, 10),
              settings: const StandbySettings(
                clockStyle: ClockStyle.world,
                worldZone: 'Asia/Kolkata',
                worldCity: 'Nagpur',
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Nagpur'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp(r'^([+−]\d+(\.\d)? h|Same time)$').hasMatch(w.data ?? ''),
      ),
      findsOneWidget,
    );
  });
}
