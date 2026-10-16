import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/features/standby/settings/controls.dart';

Widget _page() => const MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: Column(
        children: [
          SettingsSection(title: 'First', first: true, child: Text('one')),
          SettingsSection(title: 'Second', child: Text('two')),
        ],
      ),
    ),
  ),
);

void main() {
  setUp(() => SettingsSection.debugOpenAll = false);
  tearDown(() => SettingsSection.debugOpenAll = true);

  testWidgets('the first group starts open, the others closed', (t) async {
    await t.pumpWidget(_page());
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsNothing);
  });

  testWidgets('tapping a heading opens it, tapping again closes it', (t) async {
    await t.pumpWidget(_page());
    await t.tap(find.text('Second'));
    await t.pumpAndSettle();
    expect(find.text('two'), findsOneWidget);
    await t.tap(find.text('Second'));
    await t.pumpAndSettle();
    expect(find.text('two'), findsNothing);
  });

  testWidgets('a group remembers it was opened, after a rebuild', (t) async {
    await t.pumpWidget(_page());
    await t.tap(find.text('Second'));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_page()); // the settings closed and opened again
    expect(find.text('two'), findsOneWidget);
    await t.tap(find.text('Second')); // leave it as it was found
    await t.pumpAndSettle();
  });
}
