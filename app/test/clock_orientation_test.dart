import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/clock_faces.dart';

void main() {
  Widget at(Size panel, ClockStyle style) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox.fromSize(
          size: panel,
          child: ClockFace(
            time: DateTime(2026, 10, 11, 10, 9, 30),
            settings: StandbySettings(
              clockStyle: style,
              use24HourTime: true,
              layoutMode: StandbyLayoutMode.single,
            ),
          ),
        ),
      ),
    ),
  );

  List<Offset> parts(WidgetTester tester) => [
    for (final e
        in find
            .descendant(
              of: find.byType(ClockFace),
              matching: find.byType(RichText),
            )
            .evaluate())
      tester.getCenter(find.byWidget(e.widget)),
  ];

  for (final style in [ClockStyle.digital, ClockStyle.mono]) {
    testWidgets(
      '${style.name}: one line when wide, hours over minutes when tall',
      (tester) async {
        await tester.pumpWidget(at(const Size(800, 300), style));
        await tester.pumpAndSettle();
        var p = parts(tester); // hours, colon, minutes
        expect(p[2].dx, greaterThan(p[0].dx + 40)); // minutes to the right
        expect((p[2].dy - p[0].dy).abs(), lessThan(4));

        await tester.pumpWidget(at(const Size(360, 700), style));
        await tester.pumpAndSettle();
        p = parts(tester);
        expect(p[2].dy, greaterThan(p[0].dy + 40)); // minutes below
        expect((p[2].dx - p[0].dx).abs(), lessThan(4));
      },
    );
  }

  testWidgets(
    'turning the phone glides the digits: hours to the top, minutes to the bottom',
    (tester) async {
      await tester.pumpWidget(at(const Size(800, 300), ClockStyle.digital));
      await tester.pumpAndSettle();
      final wide = parts(tester);
      await tester.pumpWidget(at(const Size(360, 700), ClockStyle.digital));
      await tester.pump(); // the change starts from where they were
      await tester.pump(const Duration(milliseconds: 120));
      final mid = parts(tester);
      await tester.pumpAndSettle();
      final tall = parts(tester);
      // the minutes' vertical position is between where it was and where it ends
      final from = wide[2].dy, to = tall[2].dy;
      expect(to, greaterThan(from));
      expect(mid[2].dy, greaterThan(from));
      expect(mid[2].dy, lessThan(to));
    },
  );

  for (final style in ClockStyle.values) {
    for (final size in const [
      Size(360, 700),
      Size(390, 800),
      Size(800, 360),
      Size(380, 340),
      Size(900, 400),
    ]) {
      testWidgets(
        '${style.name} fits ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await tester.pumpWidget(at(size, style));
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  Widget at12(Size panel, ClockStyle style) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox.fromSize(
          size: panel,
          child: ClockFace(
            time: DateTime(2026, 10, 11, 9, 7), // 9:07 AM
            settings: StandbySettings(
              clockStyle: style,
              use24HourTime: false,
              layoutMode: StandbyLayoutMode.single,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('flip, 12-hour: two hour tiles when tall, one when wide', (
    tester,
  ) async {
    await tester.pumpWidget(at12(const Size(360, 700), ClockStyle.flip));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hours0')), findsOneWidget);
    expect(find.byKey(const ValueKey('hours1')), findsOneWidget); // "09"
    await tester.pumpWidget(at12(const Size(800, 300), ClockStyle.flip));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hours0')), findsOneWidget);
    expect(find.byKey(const ValueKey('hours1')), findsNothing); // "9"
  });

  testWidgets(
    'flip, 12-hour, tall: the tiles stay centred and AM sits at the end of the minutes line',
    (tester) async {
      await tester.pumpWidget(at12(const Size(360, 700), ClockStyle.flip));
      await tester.pumpAndSettle();
      Offset tile(String k) => tester.getCenter(find.byKey(ValueKey(k)));
      final hoursMid = (tile('hours0').dx + tile('hours1').dx) / 2;
      final minutesMid = (tile('minutes0').dx + tile('minutes1').dx) / 2;
      expect((hoursMid - minutesMid).abs(), lessThan(1)); // one column
      final am = tester.getCenter(find.text('AM'));
      expect(am.dx, greaterThan(tile('minutes1').dx)); // to the right of them
      final minutesBox = tester.getRect(find.byKey(const ValueKey('minutes1')));
      expect(am.dy, greaterThan(minutesBox.center.dy)); // down at their bottom
      expect(am.dy, lessThan(minutesBox.bottom + 1));
    },
  );

  testWidgets(
    'flip with seconds, tall: seconds are a smaller centred row, AM ends that row',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 700,
                child: ClockFace(
                  time: DateTime(2026, 10, 11, 9, 7, 17),
                  settings: const StandbySettings(
                    clockStyle: ClockStyle.flip,
                    use24HourTime: false,
                    showSeconds: true,
                    layoutMode: StandbyLayoutMode.single,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Rect box(String k) => tester.getRect(find.byKey(ValueKey(k)));
      final minutes = box('minutes0');
      final sec = box('detail0');
      expect(sec.height, lessThan(minutes.height)); // smaller than the others
      final minutesMid =
          (box('minutes0').center.dx + box('minutes1').center.dx) / 2;
      final secMid = (box('detail0').center.dx + box('detail1').center.dx) / 2;
      expect((secMid - minutesMid).abs(), lessThan(1)); // centred under them
      final am = tester.getCenter(find.text('AM'));
      expect(
        am.dx,
        greaterThan(box('detail1').right),
      ); // at the end of that row
    },
  );

  for (final style in [ClockStyle.digital, ClockStyle.mono]) {
    testWidgets('${style.name}, 12-hour keeps the hour as it is when tall', (
      tester,
    ) async {
      await tester.pumpWidget(at12(const Size(360, 700), style));
      await tester.pumpAndSettle();
      expect(find.text('9'), findsOneWidget);
      expect(find.text('09'), findsNothing);
    });
  }

  testWidgets('tall 12-hour digital: AM sits centred under the minutes', (
    tester,
  ) async {
    await tester.pumpWidget(at12(const Size(360, 700), ClockStyle.digital));
    await tester.pumpAndSettle();
    final minutes = tester.getCenter(find.text('07'));
    final am = tester.getCenter(find.text('AM'));
    expect((am.dx - minutes.dx).abs(), lessThan(1));
    expect(am.dy, greaterThan(minutes.dy));
  });

  // With two panels, World and Flip stay on one line whichever way the phone
  // is held: at that size side by side reads better than stacked.
  for (final style in [ClockStyle.world, ClockStyle.flip]) {
    for (final size in const [Size(360, 640), Size(400, 360), Size(380, 700)]) {
      testWidgets(
        '${style.name} stays on one line in two-panel mode (${size.width.toInt()}x${size.height.toInt()})',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox.fromSize(
                    size: size,
                    child: ClockFace(
                      time: DateTime(2026, 10, 11, 10, 9),
                      settings: StandbySettings(
                        clockStyle: style,
                        use24HourTime: true,
                        layoutMode: StandbyLayoutMode.duo,
                        worldZone: 'Asia/Tokyo',
                        worldCity: 'Tokyo',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (style == ClockStyle.flip) {
            // the hour tiles and the minute tiles are on the same line
            final hour = tester.getCenter(find.byKey(const ValueKey('hours1')));
            final minute = tester.getCenter(
              find.byKey(const ValueKey('minutes0')),
            );
            expect((hour.dy - minute.dy).abs(), lessThan(2));
            expect(minute.dx, greaterThan(hour.dx));
          } else {
            // hours and minutes of the first city side by side
            final texts = find
                .descendant(
                  of: find.byType(ClockFace),
                  matching: find.text('10'),
                )
                .first;
            final mins = find
                .descendant(
                  of: find.byType(ClockFace),
                  matching: find.text('09'),
                )
                .first;
            expect(
              (tester.getCenter(texts).dy - tester.getCenter(mins).dy).abs(),
              lessThan(2),
            );
            expect(
              tester.getCenter(mins).dx,
              greaterThan(tester.getCenter(texts).dx),
            );
          }
        },
      );
    }
  }
}
