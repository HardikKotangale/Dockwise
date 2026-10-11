import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../domain/standby_models.dart';

/// Why weather could not be loaded; shown on the card instead of fake data.
enum WeatherProblem { permission, locationOff, offline }

class WeatherException implements Exception {
  const WeatherException(this.problem);
  final WeatherProblem problem;
}

/// Weather for the phone's current location (Open-Meteo, no API key).
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<WeatherSnapshot> fetchForPhone() async {
    final position = await _position();
    final lat = position.latitude.toStringAsFixed(3);
    final lon = position.longitude.toStringAsFixed(3);
    return _fetch(lat, lon, city: await _cityName(lat, lon));
  }

  /// Weather for a chosen city (the second city), by its coordinates.
  Future<WeatherSnapshot> fetchForCity({
    required String city,
    required double latitude,
    required double longitude,
  }) => _fetch(
    latitude.toStringAsFixed(3),
    longitude.toStringAsFixed(3),
    city: city,
  );

  Future<WeatherSnapshot> _fetch(
    String lat,
    String lon, {
    required String city,
  }) async {
    try {
      final forecast = await _client
          .get(
            Uri.https('api.open-meteo.com', '/v1/forecast', {
              'latitude': lat,
              'longitude': lon,
              'current': 'temperature_2m,weather_code,is_day',
              'hourly': 'temperature_2m,weather_code,is_day',
              'daily': 'weather_code,temperature_2m_max,temperature_2m_min',
              'forecast_days': '7',
              'timezone': 'auto',
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (forecast.statusCode != 200) {
        throw const WeatherException(WeatherProblem.offline);
      }
      return parseForecast(
        jsonDecode(forecast.body) as Map<String, dynamic>,
        city: city,
      );
    } on WeatherException {
      rethrow;
    } catch (_) {
      throw const WeatherException(WeatherProblem.offline);
    }
  }

  // Coarse accuracy is enough for a city and saves battery.
  Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const WeatherException(WeatherProblem.locationOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const WeatherException(WeatherProblem.permission);
    }
    try {
      return await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 12),
            ),
          );
    } catch (_) {
      throw const WeatherException(WeatherProblem.locationOff);
    }
  }

  Future<String> _cityName(String lat, String lon) async {
    try {
      final res = await _client
          .get(
            Uri.https('api.bigdatacloud.net', '/data/reverse-geocode-client', {
              'latitude': lat,
              'longitude': lon,
              'localityLanguage': 'en',
            }),
          )
          .timeout(const Duration(seconds: 6));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final city = (json['city'] as String?)?.trim() ?? '';
      final locality = (json['locality'] as String?)?.trim() ?? '';
      // "Township of Perry" / "Marion County" read badly; prefer the locality.
      final administrative = RegExp(
        r'township|county|borough|district|municipality',
        caseSensitive: false,
      ).hasMatch(city);
      final ordered = administrative ? [locality, city] : [city, locality];
      return ordered.firstWhere(
        (v) => v.isNotEmpty,
        orElse: () => 'Current location',
      );
    } catch (_) {
      return 'Current location';
    }
  }
}

/// WMO weather interpretation codes -> short label.
String conditionForCode(int? code) {
  if (code == null) return 'Weather';
  if (code == 0) return 'Clear';
  if (code <= 2) return 'Partly cloudy';
  if (code == 3) return 'Cloudy';
  if (code == 45 || code == 48) return 'Fog';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if (code >= 61 && code <= 67) return 'Rain';
  if (code >= 71 && code <= 77) return 'Snow';
  if (code >= 80 && code <= 82) return 'Showers';
  if (code == 85 || code == 86) return 'Snow showers';
  if (code >= 95) return 'Thunderstorm';
  return 'Weather';
}

/// Reads an Open-Meteo forecast answer (current, hourly and daily) into a
/// [WeatherSnapshot]. Times are the place's own local times.
WeatherSnapshot parseForecast(
  Map<String, dynamic> body, {
  required String city,
}) {
  final current = body['current'] as Map<String, dynamic>;
  final daily = body['daily'] as Map<String, dynamic>;
  final code = (current['weather_code'] as num?)?.round();
  final highs = (daily['temperature_2m_max'] as List).cast<num>();
  final lows = (daily['temperature_2m_min'] as List).cast<num>();
  final dates = (daily['time'] as List?)?.cast<String>() ?? const [];
  final codes = (daily['weather_code'] as List?) ?? const [];
  final days = [
    for (
      var i = 0;
      i < dates.length && i < highs.length && i < lows.length;
      i++
    )
      ForecastDay(
        date: DateTime.parse(dates[i]),
        code: i < codes.length ? (codes[i] as num?)?.round() : null,
        highCelsius: highs[i].round(),
        lowCelsius: lows[i].round(),
      ),
  ];
  // the next hours, starting with the current one
  final hours = <ForecastHour>[];
  final hourly = body['hourly'] as Map<String, dynamic>?;
  if (hourly != null) {
    final times = (hourly['time'] as List).cast<String>();
    final temps = (hourly['temperature_2m'] as List).cast<num>();
    final hcodes = (hourly['weather_code'] as List?) ?? const [];
    final isDay = (hourly['is_day'] as List?) ?? const [];
    final nowText = current['time'] as String?;
    final now = nowText == null ? null : DateTime.tryParse(nowText);
    for (var i = 0; i < times.length && i < temps.length; i++) {
      final t = DateTime.parse(times[i]);
      if (now != null &&
          t.isBefore(DateTime(now.year, now.month, now.day, now.hour))) {
        continue;
      }
      hours.add(
        ForecastHour(
          time: t,
          code: i < hcodes.length ? (hcodes[i] as num?)?.round() : null,
          temperatureCelsius: temps[i].round(),
          isDay: i < isDay.length ? (isDay[i] as num?) != 0 : true,
        ),
      );
      if (hours.length == 12) break;
    }
  }
  return WeatherSnapshot(
    city: city,
    condition: conditionForCode(code),
    temperatureCelsius: (current['temperature_2m'] as num).round(),
    highCelsius: highs.first.round(),
    lowCelsius: lows.first.round(),
    updatedAt: DateTime.now(),
    code: code,
    isDay: (current['is_day'] as num?) != 0,
    days: days,
    hours: hours,
  );
}
