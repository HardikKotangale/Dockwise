import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// City name for an IANA zone id, e.g. "America/New_York" -> "New York".
String zoneLabel(String zoneId) => zoneId.split('/').last.replaceAll('_', ' ');

const _regions = {
  'Africa',
  'America',
  'Antarctica',
  'Arctic',
  'Asia',
  'Atlantic',
  'Australia',
  'Europe',
  'Indian',
  'Pacific',
};

/// Search every city in the time-zone database (offline). Best matches first.
List<String> searchZones(String query, {int limit = 8}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  initZones();
  final hits = <String>[];
  for (final id in tz.timeZoneDatabase.locations.keys) {
    if (!_regions.contains(id.split('/').first)) continue;
    if (zoneLabel(id).toLowerCase().contains(q)) hits.add(id);
  }
  hits.sort((a, b) {
    final sa = zoneLabel(a).toLowerCase().startsWith(q) ? 0 : 1;
    final sb = zoneLabel(b).toLowerCase().startsWith(q) ? 0 : 1;
    return sa != sb ? sa - sb : zoneLabel(a).compareTo(zoneLabel(b));
  });
  return hits.take(limit).toList();
}

bool _tzReady = false;

void initZones() {
  if (_tzReady) return;
  tzdata.initializeTimeZones(); // lazy: only when the world clock is used
  _tzReady = true;
}

/// [now] as it is in the city with IANA id [zoneId].
DateTime timeInZone(DateTime now, String zoneId) {
  try {
    initZones();
    return tz.TZDateTime.from(now.toUtc(), tz.getLocation(zoneId));
  } catch (_) {
    return now.toUtc(); // unknown zone id: show UTC rather than crash
  }
}
