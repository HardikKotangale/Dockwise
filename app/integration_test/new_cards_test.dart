// The Photos card (panel, Summary tile, two panels), the empty Photos card and
// the Calendar's Meetings tab, in the real app in full screen, as pictures
// saved in the app's temp folder.
//
//   flutter drive --profile -d macos --driver test_driver/perf_driver.dart \
//     --target integration_test/new_cards_test.dart
//
// A fake charged battery keeps this Mac's own low-battery screen from covering
// the cards; the pictures are made up, never anyone's own photos.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/battery_badge.dart';
import 'package:standby_pro/src/services/calendar_service.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';

final _root = GlobalKey();

// made-up meetings, so no one's own calendar ends up in a picture
class _SampleCalendar extends CalendarService {
  @override
  Future<CalendarAccess> status() async => CalendarAccess.granted;

  @override
  Future<List<Meeting>> meetings({int days = 3, bool titles = true}) async {
    final d = DateTime.now();
    DateTime at(int day, int h, int m) =>
        DateTime(d.year, d.month, d.day + day, h, m);
    return [
      Meeting(
        title: 'First Day of Durga Puja Festival',
        start: at(0, 0, 0),
        end: at(1, 0, 0),
        allDay: true,
        color: 0xFF8E4EC6,
      ),
      Meeting(
        title: 'Maha Saptami',
        start: at(0, 0, 0),
        end: at(1, 0, 0),
        allDay: true,
        color: 0xFFE5484D,
      ),
      Meeting(
        title: 'Design review with the whole platform team',
        start: d.subtract(const Duration(minutes: 20)),
        end: d.add(const Duration(minutes: 40)),
        allDay: false,
        color: 0xFF0091FF,
      ),
      Meeting(
        title: 'Lunch with Priya',
        start: at(0, 13, 0),
        end: at(0, 14, 0),
        allDay: false,
        color: 0xFF30A46C,
      ),
      Meeting(
        title: 'Quarterly planning',
        start: at(1, 9, 30),
        end: at(1, 10, 30),
        allDay: false,
        color: 0xFFF76B15,
      ),
    ];
  }
}

Future<void> _shot(String name) async {
  final box =
      _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await box.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(
    '${Directory.systemTemp.path}/feat_$name.png',
  ).writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<void> _makePictures(Directory dir) async {
  final palettes = [
    [const Color(0xFF1E3C72), const Color(0xFF2A9D8F)],
    [const Color(0xFFE76F51), const Color(0xFFF4A261)],
    [const Color(0xFF3D348B), const Color(0xFFF7B801)],
  ];
  for (var i = 0; i < palettes.length; i++) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const size = Size(1600, 1000);
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          palettes[i],
        ),
    );
    c.drawCircle(
      Offset(size.width * (0.3 + i * 0.2), size.height * 0.4),
      180,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    final img = await rec.endRecording().toImage(1600, 1000);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/pic$i.png').writeAsBytesSync(data!.buffer.asUint8List());
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('features', (t) async {
    final dir = Directory('${Directory.systemTemp.path}/feat_pics')
      ..createSync(recursive: true);
    await _makePictures(dir);
    // full screen, and wait until the window really is (it can take a moment,
    // or a second try)
    final view = ui.PlatformDispatcher.instance.views.first;
    await StandbySystemService().setFullscreen(true);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (view.physicalSize.width / view.devicePixelRatio > 1300) break;
    }
    expect(view.physicalSize.width / view.devicePixelRatio, greaterThan(1300));
    Future<void> launch(StandbySettings s) async {
      SharedPreferences.setMockInitialValues({
        'standby_settings_v1': jsonEncode(s.toJson()),
      });
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        RepaintBoundary(
          key: _root,
          child: StandbyProApp(
            fitScreen: true,
            // a full, charging battery: this Mac's real one may be low, and the
            // low-battery screen would cover everything
            calendarService: _SampleCalendar(),
            battery: BatteryMonitor(
              read: () async => (level: 90, charging: true, full: false),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 4));
      await t.pump();
    }

    // 1: the Photos panel, one panel
    await launch(
      StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.photos,
        photoSource: PhotoSource.folder,
        photoFolder: dir.path,
        photoSeconds: 5,
      ),
    );
    await _shot('1_photos_panel');
    // 2: the Summary with a photos tile in the third place
    await launch(
      StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.summary,
        summaryLayout: 'v2:here,there,photos,date,weather',
        worldZone: 'Asia/Kolkata',
        worldCity: 'Nagpur',
        photoSource: PhotoSource.folder,
        photoFolder: dir.path,
      ),
    );
    await _shot('2_summary_photos');
    // 3: two panels, photos and clock
    await launch(
      StandbySettings(
        layoutMode: StandbyLayoutMode.duo,
        leftWidget: StandbyWidgetType.photos,
        rightWidget: StandbyWidgetType.clock,
        photoSource: PhotoSource.folder,
        photoFolder: dir.path,
      ),
    );
    await _shot('3_duo');
    // 4: the calendar's Meetings tab (the permission is not asked here)
    await launch(
      const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.calendar,
        calendarStyle: CalendarStyle.agenda,
      ),
    );
    await _shot('4_meetings');
    // 6: the Meetings tab with meetings, as a panel and as a Summary tile
    await _shot('6_meetings_list');
    await launch(
      StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.summary,
        summaryLayout: 'v2:here,there,date,weather,music',
        calendarStyle: CalendarStyle.agenda,
        worldZone: 'Asia/Kolkata',
        worldCity: 'Nagpur',
      ),
    );
    await _shot('7_summary_meetings');
    // 8: the World clock with its pill, one panel and two
    await launch(
      StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.clock,
        clockStyle: ClockStyle.world,
        worldZone: 'Asia/Kolkata',
        worldCity: 'Nagpur',
      ),
    );
    await _shot('8_world_one');
    await launch(
      StandbySettings(
        layoutMode: StandbyLayoutMode.duo,
        leftWidget: StandbyWidgetType.clock,
        rightWidget: StandbyWidgetType.calendar,
        clockStyle: ClockStyle.world,
        calendarStyle: CalendarStyle.agenda,
        worldZone: 'Asia/Kolkata',
        worldCity: 'Nagpur',
      ),
    );
    await _shot('9_world_duo');
    // 5: an empty Photos card
    await launch(
      const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.photos,
      ),
    );
    await _shot('5_photos_empty');
    await StandbySystemService().setFullscreen(false);
  });
}
