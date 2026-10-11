import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/weather_card.dart';
import 'package:standby_pro/src/services/weather_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

// The weather card's pages, swiped up and down:
// 0 now, 1 Fahrenheit only, 2 forecast, 3 the second city.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> answer() => {
    'current': {
      'time': '2026-10-11T14:30',
      'temperature_2m': 19.4,
      'weather_code': 2,
      'is_day': 1,
    },
    'hourly': {
      'time': [
        for (var h = 0; h < 24; h++)
          '2026-10-11T${h.toString().padLeft(2, '0')}:00',
      ],
      'temperature_2m': [for (var h = 0; h < 24; h++) 10 + h],
      'weather_code': [for (var h = 0; h < 24; h++) 0],
      'is_day': [for (var h = 0; h < 24; h++) (h > 6 && h < 19) ? 1 : 0],
    },
    'daily': {
      'time': [for (var d = 11; d < 18; d++) '2026-10-$d'],
      'weather_code': [for (var d = 0; d < 7; d++) 61],
      'temperature_2m_max': [for (var d = 0; d < 7; d++) 20 + d],
      'temperature_2m_min': [for (var d = 0; d < 7; d++) 10 + d],
    },
  };

  WeatherSnapshot snap(String city) => parseForecast(answer(), city: city);

  Widget host(Widget card) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 480, height: 400, child: card)),
  );

  test('the forecast answer becomes hours from now and seven days', () {
    final w = parseForecast(answer(), city: 'Springfield');
    expect(w.city, 'Springfield');
    expect(w.temperatureCelsius, 19);
    expect(w.days.length, 7);
    expect(w.days.first.highCelsius, 20);
    expect(w.days.last.lowCelsius, 16);
    // starts with the current hour (14:00) and runs to the end of the day
    expect(w.hours.first.time.hour, 14);
    expect(w.hours.length, 10);
    expect(w.hours.first.temperatureCelsius, 24);
  });

  test('an answer without the forecast lists still reads', () {
    final w = parseForecast({
      'current': {'temperature_2m': 5, 'weather_code': 0, 'is_day': 1},
      'daily': {
        'temperature_2m_max': [8],
        'temperature_2m_min': [2],
      },
    }, city: 'X');
    expect(w.days, isEmpty);
    expect(w.hours, isEmpty);
    expect(w.highCelsius, 8);
  });

  testWidgets('page 1 is the same card as page 0, in Fahrenheit', (
    tester,
  ) async {
    Widget at(int page) => host(
      WeatherCard(
        snapshot: snap('Springfield'),
        settings: const StandbySettings(), // Celsius in the settings
        page: page,
      ),
    );
    await tester.pumpWidget(at(0));
    await tester.pumpAndSettle();
    expect(find.text('19°'), findsOneWidget);
    expect(find.text('Partly cloudy'), findsOneWidget);
    expect(find.text('Springfield'), findsOneWidget);
    expect(find.textContaining('H:20°'), findsOneWidget);

    await tester.pumpWidget(at(1));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // same look: the city, the condition, the backdrop; only the unit differs
    expect(find.text('66°'), findsOneWidget); // 19 C
    expect(find.text('Partly cloudy'), findsOneWidget);
    expect(find.text('Springfield'), findsOneWidget);
    expect(find.textContaining('H:68°'), findsOneWidget); // 20 C
    expect(find.text('19°'), findsNothing);
  });

  testWidgets('page 2 is the forecast: hours and the days ahead', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        WeatherCard(
          snapshot: snap('Springfield'),
          settings: const StandbySettings(use24HourTime: true),
          page: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('forecast'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('15:00'), findsOneWidget);
  });

  testWidgets('page 3 asks for a second city when there is none', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        WeatherCard(
          snapshot: snap('Springfield'),
          settings: const StandbySettings(),
          page: 3,
          onCityTap: () => taps++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add a second city'), findsOneWidget);
    await tester.tap(find.text('Add a second city'));
    expect(taps, 1); // goes to the city search
  });

  testWidgets('page 3 shows the second city weather once it is chosen', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        WeatherCard(
          snapshot: snap('Springfield'),
          settings: const StandbySettings(
            worldZone: 'Asia/Tokyo',
            worldCity: 'Tokyo',
            worldLat: 35.7,
            worldLon: 139.7,
          ),
          page: 3,
          secondSnapshot: snap('Tokyo'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tokyo'), findsOneWidget);
    expect(find.text('Springfield'), findsNothing);
  });

  testWidgets('the pages slide when the page changes', (tester) async {
    Widget at(int page) => host(
      WeatherCard(
        snapshot: snap('Springfield'),
        settings: const StandbySettings(),
        page: page,
      ),
    );
    await tester.pumpWidget(at(0));
    expect(find.text('Springfield'), findsOneWidget);
    await tester.pumpWidget(at(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('forecast'), findsOneWidget); // mid-slide
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets(
    'swiping up on the weather panel steps through the pages and wraps',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const StandbyProApp(initialSettings: StandbySettings()),
      );
      await tester.pump();
      Future<void> swipeUp(Finder on) async {
        await tester.fling(on, const Offset(0, -300), 1500);
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      final weather = find.textContaining('Loading weather');
      expect(weather, findsOneWidget); // 0: now
      await swipeUp(weather);
      expect(
        find.textContaining('Loading weather'),
        findsOneWidget,
      ); // 1: Fahrenheit
      await swipeUp(find.textContaining('Loading weather'));
      expect(find.textContaining('No forecast yet'), findsOneWidget); // 2
      await swipeUp(find.textContaining('No forecast yet'));
      expect(find.text('Add a second city'), findsOneWidget); // 3
      await swipeUp(find.text('Add a second city'));
      expect(find.textContaining('Loading weather'), findsOneWidget); // wrapped
    },
  );

  test('the controller wraps the weather pages in both directions', () {
    SharedPreferences.setMockInitialValues({});
    final c = StandbyController(autostartTicker: false);
    addTearDown(c.dispose);
    expect(c.weatherPage, 0);
    c.cycleWeatherPage(-1);
    expect(c.weatherPage, 3);
    c.cycleWeatherPage(1);
    expect(c.weatherPage, 0);
    c.cycleWeatherPage(1);
    expect(c.weatherPage, 1);
  });

  testWidgets('the weather card fits a small tile (as in the Summary panel)', (
    tester,
  ) async {
    for (final size in const [Size(190, 140), Size(160, 120), Size(300, 150)]) {
      for (final page in [0, 1, 2, 3]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox.fromSize(
                  size: size,
                  child: WeatherCard(
                    snapshot: snap('Springfield'),
                    secondSnapshot: snap('Tokyo'),
                    settings: const StandbySettings(
                      worldZone: 'Asia/Tokyo',
                      worldLat: 35.7,
                      worldLon: 139.7,
                    ),
                    page: page,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: '$size page $page');
      }
    }
  });
}
