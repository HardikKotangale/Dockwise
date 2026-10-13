import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/clock/float_clock.dart';

void main() {
  final time = DateTime(2026, 10, 13, 9, 41);

  double angleOf(WidgetTester t, String digit) {
    final m = t
        .widget<Transform>(
          find
              .ancestor(of: find.text(digit), matching: find.byType(Transform))
              .first,
        )
        .transform;
    return math.atan2(m.storage[1], m.storage[0]);
  }

  Future<StreamController<(double, double, double)>> pump(
    WidgetTester t, {
    bool still = false,
  }) async {
    final tilt = StreamController<(double, double, double)>();
    // not awaited: with nobody listening, close() never finishes
    addTearDown(() => unawaited(tilt.close()));
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            disableAnimations: still,
          ),
          child: Scaffold(
            body: FloatClockFace(
              time: time,
              settings: const StandbySettings(),
              tilt: tilt.stream,
              random: math.Random(7),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(seconds: 1));
    return tilt;
  }

  Future<void> lean(
    WidgetTester t,
    StreamController<(double, double, double)> s,
    double x,
  ) async {
    for (var i = 0; i < 60; i++) {
      s.add((x, 9.0, 3.0));
      await t.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('each digit sits at its own small angle', (t) async {
    await pump(t);
    final angles = [
      for (final d in ['0', '9', '4', '1']) angleOf(t, d),
    ];
    for (final a in angles) {
      expect(a.abs(), lessThanOrEqualTo(0.07 + 1e-9));
    }
    expect(angles.toSet().length, greaterThan(1)); // not all the same
    expect(angles.any((a) => a != 0), isTrue);
  });

  testWidgets('the digits sway when the phone leans, and settle back', (
    t,
  ) async {
    final tilt = await pump(t);
    final rest = angleOf(t, '9');
    await lean(t, tilt, -6); // right edge down
    final leaned = angleOf(t, '9');
    expect(leaned, isNot(closeTo(rest, 0.02)));
    await lean(t, tilt, 0); // level again
    expect(angleOf(t, '9'), closeTo(rest, 0.02));
  });

  testWidgets('with animations off the digits stay tilted but do not sway', (
    t,
  ) async {
    final tilt = await pump(t, still: true);
    final rest = angleOf(t, '9');
    expect(rest, isNot(0));
    await lean(t, tilt, -6);
    expect(angleOf(t, '9'), closeTo(rest, 1e-9));
  });

  Future<void> show(WidgetTester t, DateTime at, {bool stacked = true}) =>
      t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: Scaffold(
              body: FloatClockFace(
                time: at,
                settings: const StandbySettings(),
                stacked: stacked,
                tilt: const Stream.empty(),
                random: math.Random(3),
              ),
            ),
          ),
        ),
      );

  Finder dots() => find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle,
  );

  testWidgets('a colon floats between hours and minutes on one line', (
    t,
  ) async {
    await show(t, time, stacked: false);
    await t.pump(const Duration(seconds: 1));
    expect(dots(), findsNWidgets(2)); // the two dots
    final colon = t.getCenter(dots().first).dx;
    expect(colon, greaterThan(t.getCenter(find.text('9')).dx));
    expect(colon, lessThan(t.getCenter(find.text('4')).dx));
  });

  testWidgets('a changing digit never moves the others', (t) async {
    await show(t, DateTime(2026, 10, 13, 12, 8));
    await t.pump(const Duration(seconds: 1));
    final minuteSlot = t.getCenter(find.text('8')).dx; // the second minute
    final hourSlot = t.getCenter(find.text('2')).dx;
    await show(t, DateTime(2026, 10, 13, 12, 18)); // the 0 becomes a 1
    await t.pump(const Duration(seconds: 1));
    expect(t.getCenter(find.text('8')).dx, closeTo(minuteSlot, 0.5));
    expect(t.getCenter(find.text('2')).dx, closeTo(hourSlot, 0.5));
    // 1 and 0 are different widths in most fonts, but get the same slot
    await show(t, DateTime(2026, 10, 13, 12, 11));
    await t.pump(const Duration(seconds: 1));
    expect(t.getCenter(find.text('2')).dx, closeTo(hourSlot, 0.5));
  });

  testWidgets('hours and minutes sway together, neither left behind', (
    t,
  ) async {
    final tilt = await pump(t);
    await lean(t, tilt, -6);
    final hours = angleOf(t, '0') - 0; // hours row, first digit
    final minutes = angleOf(t, '4'); // minutes row, first digit
    // both leaned the same way by about the same amount on top of their own
    // random angles: strip those off and compare the sway
    await lean(t, tilt, 0);
    final hoursRest = angleOf(t, '0');
    final minutesRest = angleOf(t, '4');
    final swayH = hours - hoursRest;
    final swayM = minutes - minutesRest;
    expect(swayH.sign, swayM.sign);
    expect(swayH.abs() / swayM.abs(), inInclusiveRange(0.6, 1.6));
  });

  testWidgets(
    'it turns clearly and fast: most of the way in a third of a second',
    (t) async {
      final tilt = await pump(t);
      final rest = angleOf(t, '9');
      for (var i = 0; i < 20; i++) {
        tilt.add((-3.3, 9.0, 3.0)); // turned about 20 degrees
        await t.pump(const Duration(milliseconds: 16));
      }
      // 20 degrees is 0.35 rad; they turn back against it (a hanging weight)
      expect((angleOf(t, '9') - rest).abs(), greaterThan(0.2));
    },
  );

  testWidgets('AM/PM turns with the rest, and the colon takes its own color', (
    t,
  ) async {
    final tilt = StreamController<(double, double, double)>();
    addTearDown(() => unawaited(tilt.close()));
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Scaffold(
            body: FloatClockFace(
              time: time,
              settings: const StandbySettings(
                use24HourTime: false,
                colonColor: 0xFF00C853,
              ),
              stacked: false,
              tilt: tilt.stream,
              random: math.Random(5),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(seconds: 1));
    final rest = angleOf(t, 'AM');
    await lean(t, tilt, -6);
    expect(angleOf(t, 'AM'), isNot(closeTo(rest, 0.05)));
    expect(
      (t.widget<DecoratedBox>(dots().first).decoration as BoxDecoration).color,
      const Color(0xFF00C853),
    );
  });
}
