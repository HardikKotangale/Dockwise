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
    try {
      final forecast = await _client
          .get(
            Uri.https('api.open-meteo.com', '/v1/forecast', {
              'latitude': lat,
              'longitude': lon,
              'current': 'temperature_2m,weather_code,is_day',
              'daily': 'temperature_2m_max,temperature_2m_min',
              'forecast_days': '1',
              'timezone': 'auto',
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (forecast.statusCode != 200) {
        throw const WeatherException(WeatherProblem.offline);
      }
      final body = jsonDecode(forecast.body) as Map<String, dynamic>;
      final current = body['current'] as Map<String, dynamic>;
      final daily = body['daily'] as Map<String, dynamic>;
      final code = (current['weather_code'] as num?)?.round();
      final temp = (current['temperature_2m'] as num).round();
      return WeatherSnapshot(
        city: await _cityName(lat, lon),
        condition: conditionForCode(code),
        temperatureCelsius: temp,
        highCelsius: ((daily['temperature_2m_max'] as List).first as num)
            .round(),
        lowCelsius: ((daily['temperature_2m_min'] as List).first as num)
            .round(),
        updatedAt: DateTime.now(),
        code: code,
        isDay: (current['is_day'] as num?) != 0,
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
