import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/calendar_agenda.dart';
import 'package:standby_pro/src/services/calendar_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

// The Calendar card's Meetings tab: what it shows for each state of the
// permission, that hiding titles also stops reading them, and the tab order.
class _FakeCalendar extends CalendarService {
  _FakeCalendar(this.access, [this.list = const []]);
  CalendarAccess access;
  final List<Meeting> list;
  final titlesAsked = <bool>[];
  var requested = 0;

  @override
  Future<CalendarAccess> status() async => access;

  @override
  Future<CalendarAccess> request() async {
    requested++;
    access = CalendarAccess.granted;
    return access;
  }

  @override
  Future<List<Meeting>> meetings({int days = 3, bool titles = true}) async {
    titlesAsked.add(titles);
    return [
      for (final m in list)
        Meeting(
          title: titles ? m.title : '',
          start: m.start,
          end: m.end,
          allDay: m.allDay,
        ),
    ];
  }
}

final _now = DateTime(2026, 10, 16, 9, 0);
final _list = [
  Meeting(
    title: 'Design review',
    start: DateTime(2026, 10, 16, 10),
    end: DateTime(2026, 10, 16, 11),
    allDay: false,
  ),
  Meeting(
    title: 'Offsite',
    start: DateTime(2026, 10, 17),
    end: DateTime(2026, 10, 18),
    allDay: true,
  ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host({
    required CalendarAccess access,
    List<Meeting> meetings = const [],
    bool titles = true,
    VoidCallback? onConnect,
    bool compact = false,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 500,
        height: 600,
        child: CalendarAgenda(
          now: _now,
          accent: Colors.red,
          access: access,
          meetings: meetings,
          showTitles: titles,
          onConnect: onConnect,
          compact: compact,
        ),
      ),
    ),
  );

  testWidgets('meetings are listed by day, all-day ones say so', (t) async {
    await t.pumpWidget(host(access: CalendarAccess.granted, meetings: _list));
    expect(find.text('Design review'), findsOneWidget);
    expect(find.text('Offsite'), findsOneWidget);
    expect(find.text('All day'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
  });

  testWidgets('with titles off each meeting is just "Busy"', (t) async {
    await t.pumpWidget(
      host(access: CalendarAccess.granted, meetings: _list, titles: false),
    );
    expect(find.text('Design review'), findsNothing);
    expect(find.text('Busy'), findsNWidgets(2));
  });

  testWidgets('a meeting that is over is not listed', (t) async {
    final past = Meeting(
      title: 'Standup',
      start: DateTime(2026, 10, 16, 7),
      end: DateTime(2026, 10, 16, 8),
      allDay: false,
    );
    await t.pumpWidget(host(access: CalendarAccess.granted, meetings: [past]));
    expect(find.text('Standup'), findsNothing);
    expect(find.text('No meetings coming up'), findsOneWidget);
  });

  testWidgets('not asked yet: a button asks; denied and unsupported explain', (
    t,
  ) async {
    var asked = 0;
    await t.pumpWidget(
      host(access: CalendarAccess.unknown, onConnect: () => asked++),
    );
    await t.tap(find.text('Allow calendar'));
    expect(asked, 1);
    await t.pumpWidget(host(access: CalendarAccess.denied));
    expect(find.textContaining('System Settings'), findsOneWidget);
    expect(find.text('Allow calendar'), findsNothing);
    await t.pumpWidget(host(access: CalendarAccess.unsupported));
    expect(find.textContaining('Mac or an iPhone'), findsOneWidget);
  });

  testWidgets('a small tile shows only what fits, with no heading', (t) async {
    await t.pumpWidget(
      host(access: CalendarAccess.granted, meetings: _list, compact: true),
    );
    expect(find.text('Meetings'), findsNothing);
    expect(find.text('Design review'), findsOneWidget);
  });

  testWidgets('a month of meetings scrolls; pulling past the end changes tab', (
    t,
  ) async {
    var edges = 0;
    final many = [
      for (var i = 0; i < 40; i++)
        Meeting(
          title: 'Meeting $i',
          start: DateTime(
            2026,
            10,
            16,
            10,
          ).add(Duration(days: i ~/ 3, hours: i % 3)),
          end: DateTime(
            2026,
            10,
            16,
            11,
          ).add(Duration(days: i ~/ 3, hours: i % 3)),
          allDay: false,
        ),
    ];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 600,
            child: CalendarAgenda(
              now: _now,
              accent: Colors.red,
              access: CalendarAccess.granted,
              meetings: many,
              showTitles: true,
              onEdge: () => edges++,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Meeting 0'), findsOneWidget);
    expect(find.text('Meeting 39'), findsNothing); // below the fold
    for (var i = 0; i < 12; i++) {
      await t.drag(find.byType(ListView), const Offset(0, -900));
      await t.pump();
    }
    expect(find.text('Meeting 39'), findsOneWidget); // reached by scrolling
    expect(edges, greaterThanOrEqualTo(1)); // pulled past the end
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('a short list takes no drags, so a swipe is left to the panel', (
    t,
  ) async {
    var edges = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 600,
            child: CalendarAgenda(
              now: _now,
              accent: Colors.red,
              access: CalendarAccess.granted,
              meetings: _list,
              showTitles: true,
              onEdge: () => edges++,
            ),
          ),
        ),
      ),
    );
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pump();
    expect(edges, 0);
  });

  test('the swipe goes Today, Month, Meetings, Today', () async {
    final c = StandbyController(
      initialSettings: const StandbySettings(),
      autostartTicker: false,
      calendarService: _FakeCalendar(CalendarAccess.unsupported),
    );
    addTearDown(c.dispose);
    final seen = <CalendarStyle>[c.settings.calendarStyle];
    for (var i = 0; i < 3; i++) {
      c.toggleCalendarStyle();
      await Future<void>.delayed(Duration.zero);
      seen.add(c.settings.calendarStyle);
    }
    expect(seen, [
      CalendarStyle.day,
      CalendarStyle.month,
      CalendarStyle.agenda,
      CalendarStyle.day,
    ]);
  });

  test(
    'meetings are fetched only on the Meetings tab, titles per setting',
    () async {
      final fake = _FakeCalendar(CalendarAccess.granted, _list);
      final c = StandbyController(
        initialSettings: const StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.calendar,
        ),
        autostartTicker: false,
        calendarService: fake,
      );
      addTearDown(c.dispose);
      await c.refreshMeetings();
      expect(fake.titlesAsked, isEmpty); // Today tab: the calendar is not read
      await c.updateSettings(
        c.settings.copyWith(calendarStyle: CalendarStyle.agenda),
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.meetings.map((m) => m.title), ['Design review', 'Offsite']);
      await c.updateSettings(c.settings.copyWith(calendarTitles: false));
      await Future<void>.delayed(Duration.zero);
      expect(fake.titlesAsked.last, isFalse); // never read, not just hidden
      expect(c.meetings.every((m) => m.title.isEmpty), isTrue);
    },
  );

  test('allowing access fills the tab, and the settings round-trip', () async {
    final fake = _FakeCalendar(CalendarAccess.unknown, _list);
    final c = StandbyController(
      initialSettings: const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.calendar,
        calendarStyle: CalendarStyle.agenda,
      ),
      autostartTicker: false,
      calendarService: fake,
    );
    addTearDown(c.dispose);
    await c.refreshMeetings();
    expect(c.calendarAccess, CalendarAccess.unknown);
    expect(c.meetings, isEmpty);
    await c.connectCalendar();
    expect(fake.requested, 1);
    expect(c.calendarAccess, CalendarAccess.granted);
    expect(c.meetings.length, 2);
    final back = StandbySettings.fromJson(
      const StandbySettings(
        calendarStyle: CalendarStyle.agenda,
        calendarTitles: false,
      ).toJson(),
    );
    expect(back.calendarStyle, CalendarStyle.agenda);
    expect(back.calendarTitles, isFalse);
  });
}
