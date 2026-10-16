import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/weather_card.dart';

// A small refresh button on the weather card, which can be turned off.
void main() {
  Widget host(StandbySettings s, VoidCallback? onRefresh) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 600,
        child: WeatherCard(snapshot: null, settings: s, onRefresh: onRefresh),
      ),
    ),
  );

  testWidgets('the button refreshes the weather', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(const StandbySettings(weatherRefresh: 2), () => taps++),
    );
    await tester.tap(find.bySemanticsLabel('Refresh weather'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(taps, 1);
  });

  testWidgets('"when touched" shows it only near the pointer', (tester) async {
    await tester.pumpWidget(host(const StandbySettings(), () {}));
    double opacity() => tester
        .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).last)
        .opacity;
    expect(opacity(), 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(200, 300));
    await tester.pump();
    expect(opacity(), 1);
    await mouse.moveTo(const Offset(900, 900));
    await tester.pump();
    expect(opacity(), 0);
  });

  testWidgets('it is gone when turned off in settings', (tester) async {
    await tester.pumpWidget(
      host(const StandbySettings(weatherRefresh: 0), () {}),
    );
    expect(find.bySemanticsLabel('Refresh weather'), findsNothing);
  });

  test('the setting is saved; the default is "when touched"', () {
    expect(const StandbySettings().weatherRefresh, 1);
    final always = const StandbySettings().copyWith(weatherRefresh: 2);
    expect(StandbySettings.fromJson(always.toJson()).weatherRefresh, 2);
    expect(StandbySettings.fromJson(const {}).weatherRefresh, 1);
    expect(
      StandbySettings.fromJson(const {'weatherRefresh': 9}).weatherRefresh,
      2,
    );
  });

  test('it says how long ago the weather was fetched', () {
    final now = DateTime(2026, 10, 16, 12, 0);
    String age(Duration d) =>
        WeatherRefreshButton.ageText(now.subtract(d), now);
    expect(age(const Duration(seconds: 20)), 'Updated just now');
    expect(age(const Duration(minutes: 4)), 'Updated 4 min ago');
    expect(age(const Duration(minutes: 125)), 'Updated 2 h ago');
    expect(age(const Duration(hours: 50)), 'Updated 2 d ago');
  });
}
