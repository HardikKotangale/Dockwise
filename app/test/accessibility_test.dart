import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/core/apple.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/settings/simple_settings.dart';
import 'package:standby_pro/src/features/standby/settings/summary_add.dart';
import 'package:standby_pro/src/features/standby/widgets/clock/clock_face.dart';
import 'package:standby_pro/src/features/standby/widgets/timer_card.dart';
import 'package:standby_pro/src/features/standby/widgets/timer_entry.dart';
import 'package:standby_pro/src/features/standby/widgets/timer_tile.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

// What a design review (Apple's HIG, via the apple-design skill) found, kept
// as checks: controls big enough, a screen reader can reach everything, and
// nothing breaks at twice the text size.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  StandbyController make() {
    final c = StandbyController(
      autostartTicker: false,
      initialSettings: const StandbySettings(),
    );
    addTearDown(c.dispose);
    return c;
  }

  Widget host(Widget child, {double textScale = 1}) => MaterialApp(
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: app!,
    ),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('the page dots are 28 pt tall or more, and screen readers can '
      'pick each page', (tester) async {
    final handle = tester.ensureSemantics();
    final picked = <int>[];
    await tester.pumpWidget(
      host(
        PageDots(
          labels: const ['Clock', 'Weather', 'Calendar'],
          icons: const [
            Icons.schedule_rounded,
            Icons.wb_sunny_rounded,
            Icons.calendar_today_rounded,
          ],
          index: 0,
          bright: true,
          onSelect: picked.add,
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(PageDots)).height,
      greaterThanOrEqualTo(28),
    );
    tester.semantics.tap(find.semantics.byLabel('Weather'));
    expect(picked, [1]);
    handle.dispose();
  });

  testWidgets('a clock reads as one sentence to a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 400,
          height: 200,
          child: ClockFace(
            time: DateTime(2026, 10, 11, 23, 50),
            settings: const StandbySettings(use24HourTime: true),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel(RegExp(r'^Time 23:50')), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
    'the squeezed timer tile keeps all three buttons at 28 pt or more',
    (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 185,
            height: 93,
            child: TimerTile(
              settings: const StandbySettings(),
              leftMs: 12000,
              totalMs: 60000,
              running: true,
              started: true,
              done: false,
              onStart: () {},
              onPause: () {},
              onReset: () {},
              onAddMinute: () {},
              onOpen: () {},
            ),
          ),
        ),
      );
      for (final label in ['Reset', '+1 min', 'Pause']) {
        final box = find.ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        );
        expect(box, findsOneWidget, reason: label);
        expect(
          tester.getSize(box).height,
          greaterThanOrEqualTo(28),
          reason: label,
        );
      }
    },
  );

  testWidgets('the main timer screens survive twice the text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = make();
    Widget card({required bool roomy, required bool horizontal}) => SizedBox(
      width: 400,
      height: 700,
      child: TimerCard(
        settings: const StandbySettings(),
        leftMs: 187000,
        totalMs: 300000,
        running: false,
        started: false,
        done: false,
        onStart: () {},
        onPause: () {},
        onReset: () {},
        onAdd: (_) {},
        onPreset: (_) {},
        onType: () {},
        roomy: roomy,
        horizontal: horizontal,
      ),
    );
    for (final w in <Widget>[
      card(roomy: true, horizontal: false),
      card(roomy: false, horizontal: true),
      SizedBox(
        width: 400,
        height: 700,
        child: TimerSettings(controller: c, onAll: () {}),
      ),
      SizedBox(
        width: 400,
        height: 700,
        child: SummaryAdd(controller: c, onDone: () {}),
      ),
      SizedBox(
        width: 400,
        height: 700,
        child: TimerEntry(controller: c, onDone: () {}),
      ),
    ]) {
      await tester.pumpWidget(host(w, textScale: 2));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull, reason: '${w.runtimeType}');
    }
  });
}
