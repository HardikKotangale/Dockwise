import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/settings/city_page.dart';
import 'package:standby_pro/src/features/standby/settings/controls.dart';
import 'package:standby_pro/src/features/standby/widgets/clock/flip_clock.dart';
import 'package:standby_pro/src/features/standby/widgets/clock/frame_clock.dart';

// The two time tiles on the Summary panel draw the time as digits, flip cards
// or a dial, in a picked colour or plain, in a wide window and a tall one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a tap on a time tile opens its own settings group', (t) async {
    SharedPreferences.setMockInitialValues({});
    SettingsSection.debugOpenAll = false; // the real thing: closed unless asked
    addTearDown(() => SettingsSection.debugOpenAll = true);
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const StandbyProApp(
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.summary,
        ),
      ),
    );
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Style'), findsNothing);
    await t.tap(find.text('Here'));
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Style'), findsOneWidget); // Summary clocks, open
    await t.pumpWidget(const SizedBox());
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final style in TileClockStyle.values) {
    for (final size in const [Size(1600, 900), Size(420, 900)]) {
      for (final color in const [0, 0xFF30D158]) {
        testWidgets('Summary clocks: ${style.name}, $size, color $color', (
          t,
        ) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            StandbyProApp(
              initialSettings: StandbySettings(
                layoutMode: StandbyLayoutMode.single,
                leftWidget: StandbyWidgetType.summary,
                summaryClockStyle: style,
                hereColor: color,
                thereColor: color,
                worldZone: 'Asia/Kolkata',
                worldCity: 'Nagpur',
              ),
            ),
          );
          await t.pump(const Duration(seconds: 1));
          expect(t.takeException(), isNull);
          expect(
            find.byType(FrameClockFace),
            style == TileClockStyle.digital ? findsWidgets : findsNothing,
          );
          expect(
            find.byType(FlipClockFace),
            style == TileClockStyle.flip ? findsWidgets : findsNothing,
          );
          // the dial is the shared painter
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is CustomPaint &&
                  w.painter.runtimeType.toString() == 'DialPainter',
            ),
            style == TileClockStyle.analog ? findsWidgets : findsNothing,
          );
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  }

  testWidgets('the trash button on the second city clears it', (tester) async {
    StandbySettings? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: CityRow(
            settings: const StandbySettings(
              worldZone: 'Asia/Kolkata',
              worldCity: 'Nagpur',
              worldLat: 21.1,
              worldLon: 79.0,
            ),
            onTap: () {},
            onChanged: (v) => saved = v,
          ),
        ),
      ),
    );
    expect(find.text('Nagpur'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove the second city'));
    expect(saved?.worldZone, isEmpty);
    expect(saved?.worldCity, isEmpty);
    // nothing to remove: no trash button
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: CityRow(
            settings: const StandbySettings(),
            onTap: () {},
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.byTooltip('Remove the second city'), findsNothing);
  });
}
