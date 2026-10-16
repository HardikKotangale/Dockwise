import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/features/standby/widgets/music_card.dart';
import 'package:standby_pro/src/features/standby/widgets/music_controls.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';

class _FakePc extends StandbySystemService {
  @override
  Future<bool> setKeepAwake(bool enabled) async => true;
}

// The music keys pulse the matching control on the card, wherever the Summary
// panel has put the music tile; with no music tile they do nothing visible.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final pc = TargetPlatformVariant({TargetPlatform.macOS});

  Finder button(String label) =>
      find.byWidgetPredicate((w) => w is TransportButton && w.label == label);

  Future<void> pump(WidgetTester t, String layout) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      StandbyProApp(
        systemService: _FakePc(),
        initialSettings: StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.summary,
          summaryLayout: layout,
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 800));
  }

  for (final layout in [
    'v2:here,there,date,weather,music',
    'v2:music,date,weather,here,there',
    'v2:here,music,date,weather',
    'v2:date,weather,music',
  ]) {
    testWidgets('. and , pulse Next and Previous: $layout', (t) async {
      await pump(t, layout);
      final next = t.widget<TransportButton>(button('Next'));
      final prev = t.widget<TransportButton>(button('Previous'));
      expect(next.pulse!.value, 0);
      await t.sendKeyEvent(LogicalKeyboardKey.period);
      await t.pump();
      expect(next.pulse!.value, 1);
      expect(prev.pulse!.value, 0);
      await t.sendKeyEvent(LogicalKeyboardKey.comma);
      await t.pump();
      expect(prev.pulse!.value, 1);
      await t.pump(const Duration(seconds: 1));
    }, variant: pc);
  }

  testWidgets('space pulses play/pause', (t) async {
    await pump(t, 'v2:here,there,date,weather,music');
    final play = t.widget<TransportButton>(button('Play'));
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(play.pulse!.value, 1);
    await t.pump(const Duration(seconds: 1));
  }, variant: pc);

  testWidgets('no music tile: the keys do nothing visible and do not break', (
    t,
  ) async {
    await pump(t, 'v2:here,there,date,weather');
    expect(button('Next'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.period);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
  }, variant: pc);

  testWidgets('a mouse over the progress bar shows a circle, a click seeks', (
    t,
  ) async {
    final seeks = <int>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 700,
            child: MusicCard(
              snapshot: const NowPlayingSnapshot(
                title: 'Song',
                artist: 'Artist',
                source: 'Spotify',
                progress: 0.1,
                isPlaying: false,
                isControllable: true,
                positionMs: 20000,
                durationMs: 200000,
              ),
              settings: const StandbySettings(),
              onCommand: (_) async => true,
              onSeek: (ms) async {
                seeks.add(ms);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    Finder knob() => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
          w.constraints?.maxWidth == 18,
    );
    expect(knob(), findsNothing);
    final bar = find.bySemanticsLabel(RegExp('Song position'));
    final box = t.getRect(bar);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(Offset(box.left + box.width * 0.5, box.top + 10));
    await t.pump();
    expect(knob(), findsOneWidget);
    await mouse.down(Offset(box.left + box.width * 0.5, box.top + 10));
    await mouse.up();
    await t.pump(const Duration(milliseconds: 400));
    expect(seeks.length, 1);
    expect(seeks.single, closeTo(100000, 8000)); // half way
    await mouse.moveTo(const Offset(5, 5));
    await t.pump();
    expect(knob(), findsNothing);
  });
}
