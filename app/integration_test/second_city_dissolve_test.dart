// Removes the second city in the real app and takes screenshots while its tile
// dissolves.
//
//   flutter drive --profile -d macos --driver test_driver/shots_driver.dart \
//     --target integration_test/second_city_dissolve_test.dart
//
// The pictures are saved in build/shots/.
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
import 'package:standby_pro/src/services/standby_system_service.dart';

// The whole window as a picture, saved in the app's temp folder (printed).
final _root = GlobalKey();

Future<void> _shot(String name) async {
  final box =
      _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await box.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final f = File('${Directory.systemTemp.path}/shot_$name.png')
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
  debugPrint('SHOT ${f.path} ${box.size.width}x${box.size.height}');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('second city dissolve', (t) async {
    final start = StandbySettings(
      layoutMode: StandbyLayoutMode.single,
      leftWidget: StandbyWidgetType.summary,
      summaryLayout: 'v2:here,there,date,weather,music',
      worldZone: 'Asia/Kolkata',
      worldCity: 'Nagpur',
      summaryThereStyle: 2,
    );
    SharedPreferences.setMockInitialValues({
      'standby_settings_v1': jsonEncode(start.toJson()),
    });
    // full screen: a wide window, so the settings open beside the panel
    await StandbySystemService().setFullscreen(true);
    await Future<void>.delayed(const Duration(seconds: 3));
    await t.pumpWidget(
      RepaintBoundary(key: _root, child: const StandbyProApp(fitScreen: true)),
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    await t.pump();
    await _shot('0_before');
    // the second city's tile opens its settings; the trash is in there
    await t.tap(find.text('Nagpur'));
    await Future<void>.delayed(const Duration(seconds: 2));
    await t.pump();
    await _shot('1_settings');
    final size = t.view.physicalSize / t.view.devicePixelRatio;
    // swipe the open settings up until [what] is built (they list lazily)
    Future<void> reach(Finder what) async {
      for (var i = 0; i < 40 && what.evaluate().isEmpty; i++) {
        await t.dragFrom(
          Offset(size.width * 0.85, size.height * 0.6),
          const Offset(0, -140),
        );
        await t.pump(const Duration(milliseconds: 250));
      }
    }

    // the second city lives in Options, which starts closed
    final options = find.text('Options');
    await reach(options);
    await t.ensureVisible(options.first);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(options.first);
    await t.pump(const Duration(milliseconds: 600));
    final trash = find.byTooltip('Remove the second city');
    await reach(trash);
    await t.ensureVisible(trash);
    await t.pump(const Duration(milliseconds: 300));
    await _shot('1b_scrolled');
    await t.tap(trash);
    for (final ms in [150, 300, 300, 400]) {
      await Future<void>.delayed(Duration(milliseconds: ms));
      await t.pump();
      await _shot(
        '2_dissolve_${DateTime.now().millisecondsSinceEpoch % 100000}',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await t.pump();
    await _shot('3_after');
    // and back: type a city, pick it, and watch it dissolve in
    await t.tap(find.text('Tap to add a second city').first);
    await Future<void>.delayed(const Duration(seconds: 2));
    await t.pump();
    await _shot('4_city_page');
    // the text input channel does not reach a real window here: set the
    // field and press Enter by calling what it would
    final field = t.widget<TextField>(find.byType(TextField).first);
    field.controller?.text = 'Nagpur';
    field.onChanged?.call('Nagpur');
    field.onSubmitted?.call('Nagpur');
    await Future<void>.delayed(const Duration(seconds: 4));
    await t.pump();
    await _shot('5_results');
    await t.tap(find.byType(ListTile).first);
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await t.pump();
      await _shot('6_in_$i');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await t.pump();
    await _shot('7_done');
    await StandbySystemService().setFullscreen(false);
  });
}
