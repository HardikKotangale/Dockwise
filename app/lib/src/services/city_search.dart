import 'dart:convert';
import 'package:http/http.dart' as http;

class CityResult {
  const CityResult({
    required this.name,
    required this.region,
    required this.timezone,
  });

  final String name;
  final String region; // "Massachusetts, United States"
  final String timezone; // IANA id, e.g. America/New_York
}

/// Worldwide city search (Open-Meteo geocoding, no API key). Throws when
/// offline so the caller can fall back to the offline zone list.
Future<List<CityResult>> searchCities(
  String query, {
  http.Client? client,
}) async {
  final q = query.trim();
  if (q.length < 2) return const [];
  final res = await (client ?? http.Client())
      .get(
        Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
          'name': q,
          'count': '10',
          'language': 'en',
          'format': 'json',
        }),
      )
      .timeout(const Duration(seconds: 6));
  if (res.statusCode != 200) {
    throw StateError('search failed ${res.statusCode}');
  }
  final list = (jsonDecode(res.body)['results'] as List?) ?? const [];
  return [
    for (final r in list.whereType<Map<String, dynamic>>())
      if (r['timezone'] != null)
        CityResult(
          name: r['name'] as String? ?? '',
          region: [
            r['admin1'],
            r['country'],
          ].whereType<String>().where((v) => v.isNotEmpty).join(', '),
          timezone: r['timezone'] as String,
        ),
  ];
}
