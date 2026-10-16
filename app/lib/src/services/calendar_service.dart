import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether Hushdock may read the calendar.
enum CalendarAccess {
  /// not asked yet
  unknown,
  granted,
  denied,

  /// this platform has no calendar bridge (Android, Windows)
  unsupported,
}

/// One meeting, as much as the Agenda shows: nothing else is read.
class Meeting {
  const Meeting({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.calendar = '',
    this.color = 0,
  });

  /// empty when the titles are hidden (they are then never read at all)
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String calendar;

  /// the calendar's own colour (0xAARRGGBB), 0 when unknown
  final int color;

  factory Meeting.fromMap(Map<Object?, Object?> m) => Meeting(
    title: (m['title'] as String?) ?? '',
    start: DateTime.fromMillisecondsSinceEpoch(m['start'] as int),
    end: DateTime.fromMillisecondsSinceEpoch(m['end'] as int),
    allDay: (m['allDay'] as bool?) ?? false,
    calendar: (m['calendar'] as String?) ?? '',
    color: (m['color'] as int?) ?? 0,
  );
}

/// Read-only access to the system calendar (Apple Calendar on a Mac or an
/// iPhone, which also shows Outlook / Exchange / Google calendars added to it
/// under Internet Accounts). The permission is the system's own "calendar" one;
/// Hushdock never writes, never sends anything over the network, and keeps the
/// meetings in memory only. When [titles] is false the titles are not even
/// read: the native side leaves them out.
class CalendarService {
  CalendarService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('standby_pro/calendar');

  final MethodChannel _channel;

  static bool get platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<CalendarAccess> status() async {
    if (!platformSupported) return CalendarAccess.unsupported;
    try {
      return _parse(await _channel.invokeMethod<String>('status'));
    } on MissingPluginException {
      return CalendarAccess.unsupported;
    } on PlatformException {
      return CalendarAccess.denied;
    }
  }

  /// Shows the system's permission question (once); the answer.
  Future<CalendarAccess> request() async {
    if (!platformSupported) return CalendarAccess.unsupported;
    try {
      final ok = await _channel.invokeMethod<bool>('request');
      return ok == true ? CalendarAccess.granted : CalendarAccess.denied;
    } on MissingPluginException {
      return CalendarAccess.unsupported;
    } on PlatformException {
      return CalendarAccess.denied;
    }
  }

  /// The meetings from the start of today for [days] days (a month by default),
  /// earliest first.
  Future<List<Meeting>> meetings({int days = 31, bool titles = true}) async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('events', {
        'days': days,
        'titles': titles,
      });
      return [
        for (final e in raw ?? const <Object?>[])
          Meeting.fromMap(e! as Map<Object?, Object?>),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static CalendarAccess _parse(String? s) => switch (s) {
    'granted' => CalendarAccess.granted,
    'denied' => CalendarAccess.denied,
    _ => CalendarAccess.unknown,
  };
}
