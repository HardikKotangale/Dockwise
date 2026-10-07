import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/features/standby/widgets/battery_badge.dart';

void main() {
  const channel = MethodChannel('standby_pro/system');
  var level = 64;

  setUp(() {
    level = 64;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'batteryInfo') {
            return {'level': level, 'charging': false, 'full': false};
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('the level comes from the system battery broadcast', () async {
    final r = await readBattery();
    expect(r, (level: 64, charging: false, full: false));
  });

  testWidgets('a drop of 1% reaches the badge on the next check', (
    tester,
  ) async {
    final monitor = BatteryMonitor(every: const Duration(seconds: 10));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BatteryBadge(monitor: monitor)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('64%'), findsOneWidget);

    level = 61; // the battery drops 3%
    await tester.pump(const Duration(seconds: 10)); // the next check
    await tester.pump();
    expect(find.text('61%'), findsOneWidget);

    level = 60;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('60%'), findsOneWidget); // and again, 1% at a time
    await tester.pumpWidget(const SizedBox());
    monitor.dispose();
  });
}
