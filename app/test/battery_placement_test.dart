import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/dashboard.dart';
import 'package:standby_pro/src/features/standby/widgets/battery_badge.dart';

// The battery number and line must never sit on a card's content: beside the
// camera when there is room, in the side margin turned sideways, and in the
// card's top-right corner (the only free spot) on a phone with no cutout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(Rect, Rect)> place(
    WidgetTester t,
    double w,
    double h, {
    double top = 0,
    double right = 0,
  }) async {
    t.view.physicalSize = Size(w * 3, h * 3);
    t.view.devicePixelRatio = 3;
    t.view.padding = FakeViewPadding(top: top * 3, right: right * 3);
    t.view.viewPadding = FakeViewPadding(top: top * 3, right: right * 3);
    addTearDown(t.view.reset);
    final m = BatteryMonitor(
      read: () async => (level: 73, charging: false, full: false),
      every: const Duration(hours: 1),
    );
    await t.pumpWidget(
      StandbyProApp(initialSettings: const StandbySettings(), battery: m),
    );
    await t.pump(const Duration(milliseconds: 600));
    final r = (
      t.getRect(find.byType(BatteryLine)),
      t.getRect(find.byType(Dashboard)),
    );
    await t.pumpWidget(const SizedBox());
    m.dispose();
    return r;
  }

  testWidgets('beside a camera: above the cards, right of the hole', (t) async {
    final (b, d) = await place(t, 360, 787, top: 39);
    expect(b.bottom, lessThanOrEqualTo(d.top));
    expect(b.right, lessThan(360 - 8));
    expect(b.left, greaterThan(360 / 2 + 20)); // clear of a centred hole
  });

  testWidgets('sideways with a side cutout: in the side margin', (t) async {
    final (b, d) = await place(t, 844, 390, right: 59);
    expect(b.left, greaterThanOrEqualTo(d.right));
  });

  testWidgets('no cutout: tucked into the top-right corner of the card', (
    t,
  ) async {
    final (b, d) = await place(t, 390, 844);
    expect(b.top - d.top, lessThan(24)); // near the card's top edge
    expect(d.right - b.right, greaterThan(20)); // inside its rounded corner
    expect(b.left, greaterThan(390 / 2)); // right half, away from the dots
  });
}
