import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/app.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/domain/summary_layout.dart';
import 'package:standby_pro/src/features/standby/widgets/photos_card.dart';
import 'package:standby_pro/src/services/photo_service.dart';
import 'package:standby_pro/src/services/standby_system_service.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

// The photo slideshow: reading a folder, the card playing and stepping, the
// choice of source, and the Summary tile and its keys.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

class _Feed implements PhotoFeed {
  _Feed(this.length, {this.broken = const {}});
  @override
  final int length;
  final Set<int> broken;
  final asked = <int>[];

  @override
  Future<Uint8List?> bytes(int index, int px) async {
    asked.add(index);
    return broken.contains(index) ? null : _png;
  }
}

class _FakePhotos extends PhotoService {
  _FakePhotos({this.folder, this.feed});
  final ({String path, String bookmark})? folder;
  final PhotoFeed? feed;
  var opened = 0;

  @override
  Future<({String path, String bookmark})?> pickFolder() async => folder;

  @override
  Future<PhotoFeed?> folderFeed(String path, {String bookmark = ''}) async {
    opened++;
    return feed;
  }

  @override
  Future<PhotoAccess> libraryAccess() async => PhotoAccess.granted;
}

class _FakePc extends StandbySystemService {
  @override
  Future<bool> setKeepAwake(bool enabled) async => true;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a folder feed lists only pictures, not hidden files or other files',
    () {
      final dir = Directory.systemTemp.createTempSync('photos_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final n in ['a.jpg', 'b.PNG', 'c.heic', 'notes.txt', '._d.jpg']) {
        File('${dir.path}/$n').writeAsBytesSync(_png);
      }
      Directory('${dir.path}/sub').createSync();
      File('${dir.path}/sub/e.webp').writeAsBytesSync(_png);
      final feed = FolderFeed.open(dir.path, seed: 1)!;
      expect(feed.length, 4); // a, b, c and the one in the folder inside
      expect(FolderFeed.open('${dir.path}/missing'), isNull);
    },
  );

  testWidgets('the card shows a picture, then the next one after its time', (
    t,
  ) async {
    final feed = _Feed(3);
    await t.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: PhotosCard(
            feed: feed,
            settings: const StandbySettings(photoSeconds: 5),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(feed.asked, [0]);
    await t.pump(const Duration(seconds: 5));
    await t.pump();
    expect(feed.asked, [0, 1]);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('a key steps on and back; a picture that cannot be read is '
      'skipped', (t) async {
    final feed = _Feed(4, broken: {1});
    final steps = ValueNotifier<(int, int)>((0, 0));
    await t.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: PhotosCard(
            feed: feed,
            settings: const StandbySettings(photoSeconds: 600),
            steps: steps,
          ),
        ),
      ),
    );
    await t.pump();
    steps.value = (1, 1); // next: picture 1 is unreadable, so 2 shows
    await t.pump();
    await t.pump();
    expect(feed.asked.last, 2);
    steps.value = (-1, 2); // back
    await t.pump();
    await t.pump();
    expect(feed.asked.last, 0); // 1 is unreadable: back skips to 0
    expect(feed.asked, containsAllInOrder([0, 1, 2, 1, 0]));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('no source yet: the card says so and a tap goes to settings', (
    t,
  ) async {
    var tapped = 0;
    await t.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: PhotosCard(
            feed: null,
            settings: const StandbySettings(),
            onSetup: () => tapped++,
          ),
        ),
      ),
    );
    expect(find.text('Choose the pictures to show'), findsOneWidget);
    await t.tap(find.text('Choose the pictures to show'));
    expect(tapped, 1);
  });

  test(
    'choosing a folder saves it and opens the pictures, only on screen',
    () async {
      final feed = _Feed(2);
      final photos = _FakePhotos(
        folder: (path: '/Users/me/Pictures/trip', bookmark: 'abc'),
        feed: feed,
      );
      final c = StandbyController(
        initialSettings: const StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.clock,
        ),
        autostartTicker: false,
        photoService: photos,
      );
      addTearDown(c.dispose);
      await c.choosePhotoFolder();
      expect(c.settings.photoSource, PhotoSource.folder);
      expect(c.settings.photoFolder, '/Users/me/Pictures/trip');
      expect(c.settings.photoFolderBookmark, 'abc');
      expect(photos.opened, 0); // no Photos card on screen: nothing is read
      await c.updateSettings(
        c.settings.copyWith(leftWidget: StandbyWidgetType.photos),
      );
      await Future<void>.delayed(Duration.zero);
      expect(photos.opened, 1);
      expect(c.photoFeed, same(feed));
      // and it survives the settings being saved and read back
      final back = StandbySettings.fromJson(c.settings.toJson());
      expect(back.photoSource, PhotoSource.folder);
      expect(back.photoFolderBookmark, 'abc');
    },
  );

  test('a folder that cannot be read says so', () async {
    final c = StandbyController(
      initialSettings: const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.photos,
        photoSource: PhotoSource.folder,
        photoFolder: '/gone',
      ),
      autostartTicker: false,
      photoService: _FakePhotos(),
    );
    addTearDown(c.dispose);
    await c.rebuildPhotoFeed();
    expect(c.photoFeed, isNull);
    expect(c.photoProblem, 'That folder cannot be read');
  });

  test('the Summary can hold a photos tile like any other', () {
    final layout = SummaryLayout.parse('v2:photos,here,there,date,weather');
    expect(layout.tiles.first, SummaryTile.photos);
    expect(layout.fits, isTrue);
    expect(SummaryLayout.standard.missing, contains(SummaryTile.photos));
    // the standard panel has all three columns: photos fits once music goes
    expect(SummaryLayout.standard.added(SummaryTile.photos), isNull);
    expect(
      SummaryLayout.standard
          .without(SummaryTile.music)
          .added(SummaryTile.photos),
      isNotNull,
    );
  });

  testWidgets('Q + up on a photos tile steps the slideshow, wherever it is', (
    t,
  ) async {
    t.view.physicalSize = const Size(1600, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      StandbyProApp(
        systemService: _FakePc(),
        initialSettings: const StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.summary,
          summaryLayout: 'v2:here,there,photos,date,weather',
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 800));
    final steps = t.widget<PhotosCard>(find.byType(PhotosCard)).steps!;
    expect(steps.value.$2, 0);
    // the photos tile is the third place: E
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyE);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyE);
    await t.pump();
    expect(steps.value, (1, 1));
    await t.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
