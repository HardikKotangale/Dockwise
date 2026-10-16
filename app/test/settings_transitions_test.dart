import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/clock_faces.dart';
import 'package:standby_pro/src/features/standby/widgets/weather_card.dart';
import 'package:standby_pro/src/services/weather_service.dart';

import 'temp_finder.dart';

// A setting that changes how things look eases in instead of jumping.
void main() {
  Widget clock(StandbySettings s) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 240,
          child: ClockFace(time: DateTime(2026, 10, 11, 15, 7), settings: s),
        ),
      ),
    ),
  );

  List<TextSpan> spans(WidgetTester t) => [
    for (final r in t.widgetList<RichText>(
      find.descendant(
        of: find.byType(ClockFace),
        matching: find.byType(RichText),
      ),
    ))
      ...(() {
        final out = <TextSpan>[];
        r.text.visitChildren((s) {
          if (s is TextSpan && s.text != null) out.add(s);
          return true;
        });
        return out;
      })(),
  ];

  testWidgets(
    '12 / 24-hour: the old and new clock cross-fade, then one is left',
    (tester) async {
      const base = StandbySettings(
        clockStyle: ClockStyle.digital,
        use24HourTime: true,
        layoutMode: StandbyLayoutMode.single,
      );
      await tester.pumpWidget(clock(base));
      await tester.pumpAndSettle();
      expect(find.text('15'), findsOneWidget);

      await tester.pumpWidget(clock(base.copyWith(use24HourTime: false)));
      await tester.pump(const Duration(milliseconds: 100));
      // part-way: both the 24-hour and the 12-hour readings are on screen
      expect(find.text('15'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('15'), findsNothing);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('PM'), findsOneWidget);
    },
  );

  testWidgets('a color change fades from the old color to the new one', (
    tester,
  ) async {
    const base = StandbySettings(
      clockStyle: ClockStyle.digital,
      use24HourTime: true,
      hoursColor: 0xFFFFFFFF,
      layoutMode: StandbyLayoutMode.single,
    );
    await tester.pumpWidget(clock(base));
    await tester.pumpAndSettle();
    await tester.pumpWidget(clock(base.copyWith(hoursColor: 0xFFFF453A)));
    await tester.pump(const Duration(milliseconds: 100));
    final during = spans(tester).where((s) => s.text == '15').length;
    expect(during, 2); // the white hours fading out, the red ones in
    await tester.pumpAndSettle();
    final after = spans(tester).where((s) => s.text == '15').toList();
    expect(after.length, 1);
    expect(after.single.style?.color, const Color(0xFFFF453A));
  });

  testWidgets('the size slider eases to its new size', (tester) async {
    StandbySettings s(double v) => StandbySettings(
      clockStyle: ClockStyle.digital,
      use24HourTime: true,
      fontScale: v,
      layoutMode: StandbyLayoutMode.single,
    );
    double width(WidgetTester t) =>
        t.getSize(find.byType(FittedBox).first).width;
    await tester.pumpWidget(clock(s(1)));
    await tester.pumpAndSettle();
    final full = width(tester);
    await tester.pumpWidget(clock(s(0.5)));
    await tester.pump(const Duration(milliseconds: 60));
    final mid = width(tester);
    await tester.pumpAndSettle();
    final half = width(tester);
    expect(mid, lessThan(full));
    expect(mid, greaterThan(half));
  });

  testWidgets('with Animations off the change is instant', (tester) async {
    const base = StandbySettings(
      clockStyle: ClockStyle.digital,
      use24HourTime: true,
      layoutMode: StandbyLayoutMode.single,
    );
    Widget still(StandbySettings s) => MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: clock(s),
    );
    await tester.pumpWidget(still(base));
    await tester.pumpWidget(still(base.copyWith(use24HourTime: false)));
    await tester.pump();
    expect(find.text('15'), findsNothing); // no old clock left fading
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('weather: Celsius to Fahrenheit fades the number', (
    tester,
  ) async {
    final w = parseForecast({
      'current': {
        'time': '2026-10-11T14:30',
        'temperature_2m': 20,
        'weather_code': 0,
        'is_day': 1,
      },
      'daily': {
        'temperature_2m_max': [24],
        'temperature_2m_min': [12],
      },
    }, city: 'Springfield');
    Widget card(bool f) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 300,
          child: WeatherCard(
            snapshot: w,
            settings: StandbySettings(fahrenheit: f),
          ),
        ),
      ),
    );
    await tester.pumpWidget(card(false));
    await tester.pumpAndSettle();
    expect(bigTemp('20'), findsOneWidget);
    await tester.pumpWidget(card(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(bigTemp('20'), findsOneWidget); // fading out
    expect(bigTemp('68'), findsOneWidget); // fading in
    await tester.pumpAndSettle();
    expect(bigTemp('20'), findsNothing);
  });
}
