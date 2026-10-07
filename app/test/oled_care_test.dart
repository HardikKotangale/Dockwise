import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/core/burn_in_protection.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/idle_dim.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

void main() {
  test(
    'the pixel shift is an orbit: it never repeats and stays in the safe area',
    () {
      const on = StandbySettings(burnInProtection: true);
      final seen = <OffsetSnapshot>{};
      for (var tick = 0; tick < 1440; tick++) {
        // a whole day, one move a minute
        final o = BurnInProtection.offsetForTick(tick, on);
        expect(o.dx.abs(), lessThanOrEqualTo(10)); // the screen margin is 12
        expect(o.dy.abs(), lessThanOrEqualTo(8));
        seen.add(o);
      }
      expect(
        seen.length,
        1440,
      ); // not one position repeated in a day (the old grid had 9)
      final xs = seen.map((o) => o.dx);
      final ys = seen.map((o) => o.dy);
      // and it uses the whole range, edge to edge
      expect(
        xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b),
        greaterThan(19),
      );
      expect(
        ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b),
        greaterThan(15),
      );
      // switched off: no shift at all
      expect(
        BurnInProtection.offsetForTick(
          5,
          const StandbySettings(burnInProtection: false),
        ),
        OffsetSnapshot.zero,
      );
    },
  );

  test('the screen dims after the idle time and wakes on a touch', () {
    final c = StandbyController(
      autostartTicker: false,
      initialSettings: const StandbySettings(idleDimMinutes: 5),
    );
    expect(c.idle, isFalse); // just started
    c.lastTouch = DateTime.now().subtract(const Duration(minutes: 4));
    expect(c.idle, isFalse);
    c.lastTouch = DateTime.now().subtract(const Duration(minutes: 6));
    expect(c.idle, isTrue); // untouched for 6 of 5 minutes

    var woke = 0;
    c.addListener(() => woke++);
    c.touched();
    expect(c.idle, isFalse);
    expect(woke, 1); // the screen is told to wake at once
    c.touched();
    expect(woke, 1); // while awake, touches do not make it rebuild
  });

  test('"Off" never dims, and the default is 5 minutes', () {
    final off = StandbyController(
      autostartTicker: false,
      initialSettings: const StandbySettings(idleDimMinutes: 0),
    )..lastTouch = DateTime.now().subtract(const Duration(hours: 5));
    expect(off.idle, isFalse);
    expect(const StandbySettings().idleDimMinutes, 5);
    // it survives saving and loading
    final back = StandbySettings.fromJson(
      const StandbySettings(idleDimMinutes: 10).toJson(),
    );
    expect(back.idleDimMinutes, 10);
  });

  testWidgets(
    'IdleDim fades to about half brightness and lets touches through',
    (tester) async {
      var taps = 0;
      Widget under({required bool idle}) => MaterialApp(
        home: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior
                  .opaque, // an empty box has no hit area otherwise
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
            IdleDim(idle: idle),
          ],
        ),
      );
      double opacity() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

      await tester.pumpWidget(under(idle: false));
      expect(opacity(), 0);
      await tester.pumpWidget(under(idle: true));
      await tester.pump(const Duration(seconds: 4));
      expect(opacity(), closeTo(0.45, 0.001));
      await tester.tap(
        find.byType(GestureDetector),
      ); // the dim never blocks a tap
      expect(taps, 1);
    },
  );
}
