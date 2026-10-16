import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/features/standby/settings/simple_settings.dart';

void main() {
  testWidgets('dragging the colour pad follows the finger but hands on rarely', (
    t,
  ) async {
    final given = <int>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [ColorRow(label: 'Time', value: 0, onChanged: given.add)],
          ),
        ),
      ),
    );
    final pad = find.byWidgetPredicate(
      (w) =>
          w is CustomPaint && w.painter.runtimeType.toString() == '_PadPainter',
    );
    final box = t.getRect(pad);
    final g = await t.startGesture(Offset(box.left + 40, box.center.dy));
    for (var i = 1; i <= 60; i++) {
      await g.moveTo(Offset(box.left + 40 + i * 4, box.center.dy));
      await t.pump(const Duration(milliseconds: 2));
    }
    await g.up();
    await t.pump(const Duration(milliseconds: 200));
    expect(given, isNotEmpty);
    // 60 moves of the finger, a handful of colours handed on, the last one exact
    expect(given.length, lessThan(15));
    expect(given.last, isNot(0));
    await t.pumpWidget(const SizedBox());
  });
}
