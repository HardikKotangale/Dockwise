import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/core/apple.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/domain/summary_layout.dart';
import 'package:standby_pro/src/features/standby/widgets/integration_cards.dart';
import 'package:standby_pro/src/features/standby/widgets/summary_card.dart';

void main() {
  group('SummaryLayout', () {
    test('the standard arrangement round-trips', () {
      final text = SummaryLayout.standard.encode();
      expect(text, 'here,there,date,weather;2');
      expect(SummaryLayout.parse(text), SummaryLayout.standard);
    });

    test('anything unreadable falls back to the standard one', () {
      for (final bad in [
        null,
        '',
        'nonsense',
        'here,here,date,weather;2',
        'here,there,date;2',
        'here,there,date,weather;9',
        'here,there,date,weather;x',
      ]) {
        expect(
          SummaryLayout.parse(bad),
          SummaryLayout.standard,
          reason: '$bad',
        );
      }
    });

    test('columns read the small tiles two by two around the music', () {
      final cols = SummaryLayout.standard.columns;
      expect(cols[0], [SummaryTile.here, SummaryTile.there]);
      expect(cols[1], [SummaryTile.date, SummaryTile.weather]);
      expect(cols[2], isNull);
      final moved = SummaryLayout.standard.withMusicColumn(0).columns;
      expect(moved[0], isNull);
      expect(moved[1], [SummaryTile.here, SummaryTile.there]);
      expect(moved[2], [SummaryTile.date, SummaryTile.weather]);
    });

    test('swapping two tiles keeps all four and the music column', () {
      final l = SummaryLayout.standard.swap(
        SummaryTile.here,
        SummaryTile.weather,
      );
      expect(l.tiles, [
        SummaryTile.weather,
        SummaryTile.there,
        SummaryTile.date,
        SummaryTile.here,
      ]);
      expect(l.musicColumn, 2);
      expect(l.columnOf(SummaryTile.here), 1);
      expect(
        SummaryLayout.standard.swap(SummaryTile.date, SummaryTile.date),
        SummaryLayout.standard,
      );
    });
  });

  Widget host(Widget child, {Size size = const Size(880, 400)}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox.fromSize(size: size, child: child),
      ),
    ),
  );

  Widget card({
    String layout = 'here,there,date,weather;2',
    ValueChanged<String>? onLayout,
    VoidCallback? onCity,
    ValueChanged<bool>? onEditing,
  }) => SummaryCard(
    now: DateTime(2026, 10, 11, 14, 5),
    settings: StandbySettings(
      worldZone: 'Asia/Tokyo',
      worldCity: 'Tokyo',
      summaryLayout: layout,
    ),
    weather: const ColoredBox(color: Colors.blue),
    music: const ColoredBox(
      color: Colors.purple,
      child: Center(child: Text('MUSIC')),
    ),
    onLayout: onLayout,
    onCityTap: onCity,
    onEditing: onEditing,
  );

  testWidgets('tapping the second city asks to choose another', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(card(onCity: () => taps++)));
    await tester.tap(find.textContaining('Tokyo'));
    expect(taps, 1);
  });

  testWidgets('holding a tile starts editing and Done ends it', (tester) async {
    final editing = <bool>[];
    await tester.pumpWidget(host(card(onEditing: editing.add)));
    expect(find.text('Done'), findsNothing);
    await tester.longPress(find.text('SUNDAY'));
    await tester.pump();
    expect(find.text('Done'), findsOneWidget);
    expect(editing, [true]);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Done'), findsNothing);
    expect(editing, [true, false]);
  });

  testWidgets('dragging one tile onto another swaps them', (tester) async {
    String? saved;
    await tester.pumpWidget(host(card(onLayout: (v) => saved = v)));
    await tester.longPress(find.text('SUNDAY'));
    await tester.pump();
    final date = tester.getCenter(find.text('SUNDAY'));
    final here = tester.getCenter(find.textContaining('Here').first);
    final g = await tester.startGesture(date);
    await tester.pump(const Duration(milliseconds: 200));
    await g.moveTo(here);
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(saved, isNotNull);
    expect(SummaryLayout.parse(saved).tiles.first, SummaryTile.date);
  });

  testWidgets('dragging the music tile to the first column moves it there', (
    tester,
  ) async {
    String? saved;
    await tester.pumpWidget(host(card(onLayout: (v) => saved = v)));
    await tester.longPress(find.text('SUNDAY'));
    await tester.pump();
    final music = tester.getCenter(find.text('MUSIC'));
    final here = tester.getCenter(find.textContaining('Here').first);
    final g = await tester.startGesture(music);
    await tester.pump(const Duration(milliseconds: 200));
    await g.moveTo(here);
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(SummaryLayout.parse(saved).musicColumn, 0);
  });

  testWidgets('tiles glide to their new places after a swap', (tester) async {
    var layout = 'here,there,date,weather;2';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 880,
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) => SummaryCard(
                  now: DateTime(2026, 10, 11, 14, 5),
                  settings: StandbySettings(
                    worldZone: 'Asia/Tokyo',
                    worldCity: 'Tokyo',
                    summaryLayout: layout,
                  ),
                  weather: const ColoredBox(color: Colors.blue),
                  music: const ColoredBox(color: Colors.purple),
                  onLayout: (v) => setState(() => layout = v),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final before = tester.getCenter(find.text('SUNDAY'));
    await tester.longPress(find.text('SUNDAY'));
    await tester.pump();
    final g = await tester.startGesture(before);
    await tester.pump(const Duration(milliseconds: 200));
    await g.moveTo(tester.getCenter(find.textContaining('Here').first));
    await tester.pump();
    await g.up();
    await tester.pump(); // the swap has happened; the tile starts moving
    await tester.pump(const Duration(milliseconds: 120));
    final mid = tester.getCenter(find.text('SUNDAY'));
    await tester.pump(const Duration(milliseconds: 600));
    final after = tester.getCenter(find.text('SUNDAY'));
    expect(after.dx, lessThan(before.dx)); // it ended up in the first column
    // part-way at 120 ms: not still at the start, not yet at the end
    expect(mid.dx, lessThan(before.dx));
    expect(mid.dx, greaterThan(after.dx));
  });

  testWidgets('the tiles deal in one after another when Summary appears', (
    tester,
  ) async {
    await tester.pumpWidget(host(card()));
    await tester.pump(const Duration(milliseconds: 150));
    double opacityOf(String text) {
      final o = find
          .ancestor(of: find.text(text), matching: find.byType(Opacity))
          .evaluate()
          .map((e) => (e.widget as Opacity).opacity)
          .reduce((a, b) => a < b ? a : b);
      return o;
    }

    // left to right: the first tile is further along than the last
    expect(opacityOf('Here'), greaterThan(opacityOf('SUNDAY')));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('SUNDAY'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('SUNDAY'), matching: find.byType(Opacity)),
      findsNothing, // settled: no leftover fade layers
    );
  });

  testWidgets('the page indicator shows each page as its icon, not dots', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PageDots(
              labels: const [
                'Clock',
                'Weather',
                'Calendar',
                'Music',
                'Summary',
              ],
              icons: const [
                Icons.schedule_rounded,
                Icons.wb_sunny_rounded,
                Icons.calendar_today_rounded,
                Icons.music_note_rounded,
                Icons.dashboard_rounded,
              ],
              index: 1,
              bright: true,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.wb_sunny_rounded), findsOneWidget);
    expect(find.byIcon(Icons.dashboard_rounded), findsOneWidget);
  });

  testWidgets('the glass strip is drawn above an opaque card, on every page', (
    tester,
  ) async {
    // a card that paints over the strip's row, like Weather, Music or Summary
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 22,
                child: PageDots(
                  labels: const [
                    'Clock',
                    'Weather',
                    'Calendar',
                    'Music',
                    'Summary',
                  ],
                  icons: const [
                    Icons.schedule_rounded,
                    Icons.wb_sunny_rounded,
                    Icons.calendar_today_rounded,
                    Icons.music_note_rounded,
                    Icons.dashboard_rounded,
                  ],
                  index: 2,
                  bright: true,
                  onSelect: (_) {},
                ),
              ),
              const Expanded(child: ColoredBox(color: Colors.black)),
            ],
          ),
        ),
      ),
    );
    final dots = tester.getCenter(find.byIcon(Icons.calendar_today_rounded));
    await tester.startGesture(dots);
    await tester.pump();
    // the label is in the Overlay (above the opaque card), not under it
    final label = find.text('Calendar');
    expect(label, findsOneWidget);
    expect(
      find.ancestor(
        of: label,
        matching: find.byType(CompositedTransformFollower),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'swiping up or down on the Summary weather tile changes its page',
    (tester) async {
      final swipes = <int>[];
      await tester.pumpWidget(
        host(
          SummaryCard(
            now: DateTime(2026, 10, 11, 14, 5),
            settings: const StandbySettings(),
            weather: const Center(child: Text('WEATHER TILE')),
            music: const ColoredBox(color: Colors.purple),
            onWeatherSwipe: swipes.add,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.fling(
        find.text('WEATHER TILE'),
        const Offset(0, -150),
        1500,
      );
      await tester.pump();
      await tester.fling(find.text('WEATHER TILE'), const Offset(0, 150), 1500);
      await tester.pump();
      expect(swipes, [1, -1]);
    },
  );

  testWidgets('holding a transport button shows a glass label', (tester) async {
    await tester.pumpWidget(
      host(
        MusicCard(
          snapshot: const NowPlayingSnapshot(
            title: 'Song',
            artist: 'Artist',
            source: 'Spotify',
            progress: 0.2,
            isPlaying: true,
            isControllable: true,
            durationMs: 200000,
            positionMs: 40000,
          ),
          settings: const StandbySettings(),
          onCommand: (_) async => true,
          nextUp: () async => 'Next: Blinding Lights · The Weeknd',
        ),
        size: const Size(420, 460),
      ),
    );
    final next = find.byTooltip('Next');
    await tester.startGesture(tester.getCenter(next));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Next: Blinding Lights · The Weeknd'), findsOneWidget);
  });

  testWidgets(
    'press a dot and slide: each page is named as you pass it, and lifting goes there',
    (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PageDots(
                labels: const [
                  'Clock',
                  'Weather',
                  'Calendar',
                  'Music',
                  'Summary',
                ],
                index: 0,
                bright: false,
                onSelect: picked.add,
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(PageDots));
      final box = Rect.fromCenter(center: center, width: 110, height: 22);
      Offset dot(int i) => Offset(box.left + 22.0 * i + 11, box.center.dy);

      // hidden at first: a touch only brings the dots back
      await tester.tapAt(dot(3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(picked, isEmpty);

      // a tap goes to that dot, and the strip lists every page
      await tester.tapAt(dot(3));
      await tester.pump();
      expect(picked, [3]);
      for (final name in ['Clock', 'Weather', 'Calendar', 'Music', 'Summary']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      await tester.pump(const Duration(seconds: 3)); // it all fades away
      await tester.tapAt(dot(0)); // brings the dots back
      await tester.pump(const Duration(milliseconds: 300));

      // press the second dot, slide along, lift on the last: goes there
      final g = await tester.startGesture(dot(1));
      await tester.pump();
      expect(find.text('Weather'), findsOneWidget); // lit and named
      await g.moveTo(dot(2));
      await tester.pump();
      await g.moveTo(dot(3));
      await tester.pump();
      await g.moveTo(dot(4));
      await tester.pump();
      expect(picked, [3]); // nothing happens until the finger lifts
      await g.up();
      await tester.pump();
      expect(picked, [3, 4]);
    },
  );
}
