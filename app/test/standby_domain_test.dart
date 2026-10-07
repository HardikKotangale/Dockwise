import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/core/burn_in_protection.dart';
import 'package:standby_pro/src/core/clock_cadence.dart';
import 'package:standby_pro/src/core/night_mode_policy.dart';
import 'package:standby_pro/src/data/settings_repository.dart';
import 'package:standby_pro/src/domain/standby_models.dart';

void main() {
  test('settings serialize all user-facing customization choices', () {
    const settings = StandbySettings(
      layoutMode: StandbyLayoutMode.single,
      activeThemeId: 'night-red',
      clockStyle: ClockStyle.flip,
      leftWidget: StandbyWidgetType.music,
      rightWidget: StandbyWidgetType.calendar,
      showSeconds: true,
      nightModeEnabled: true,
      burnInProtection: false,
      keepAwakeWhileCharging: false,
      brightness: 0.42,
      nightTintIntensity: 0.74,
      animationIntensity: 0.33,
      fontScale: 1.18,
      fontWeight: 820,
      glowIntensity: 0.61,
    );

    final roundTrip = StandbySettings.fromJson(settings.toJson());

    expect(roundTrip, settings);
    expect(
      roundTrip.copyWith(layoutMode: StandbyLayoutMode.duo).layoutMode,
      StandbyLayoutMode.duo,
    );
  });

  test('settings repository persists and restores settings', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    const expected = StandbySettings(
      activeThemeId: 'solar',
      clockStyle: ClockStyle.analog,
      brightness: 0.36,
    );

    await repository.save(expected);

    expect(await repository.load(), expected);
  });

  test(
    'clock cadence slows down when seconds are hidden or app is backgrounded',
    () {
      const hiddenSeconds = StandbySettings(showSeconds: false);
      const visibleSeconds = StandbySettings(showSeconds: true);
      final now = DateTime(2026, 5, 3, 18, 42, 17, 500);

      expect(
        ClockCadence.nextDelay(now, hiddenSeconds),
        const Duration(seconds: 43),
      );
      expect(
        ClockCadence.nextDelay(now, visibleSeconds),
        const Duration(milliseconds: 500),
      );
      expect(
        ClockCadence.nextDelay(now, visibleSeconds, appVisible: false),
        const Duration(minutes: 5),
      );
    },
  );

  test('burn-in protection produces bounded, repeatable OLED-safe offsets', () {
    const disabled = StandbySettings(burnInProtection: false);
    const enabled = StandbySettings(burnInProtection: true);

    expect(BurnInProtection.offsetForTick(8, disabled), OffsetSnapshot.zero);

    final first = BurnInProtection.offsetForTick(8, enabled);
    final same = BurnInProtection.offsetForTick(8, enabled);
    final next = BurnInProtection.offsetForTick(9, enabled);

    expect(first, same);
    expect(first, isNot(next));
    expect(first.dx.abs(), lessThanOrEqualTo(10));
    expect(first.dy.abs(), lessThanOrEqualTo(10));
  });

  test('fallback has no fake weather and an idle, uncontrollable player', () {
    final bundle = IntegrationSnapshotBundle.fallback(
      now: DateTime(2026, 5, 3, 18, 42),
    );

    expect(bundle.weather, isNull); // never show invented weather
    expect(bundle.nowPlaying.title, isNotEmpty);
    expect(bundle.nowPlaying.isControllable, isFalse);
  });

  test('night mode follows the hours you set, even past midnight', () {
    const evening = StandbySettings(
      nightModeEnabled: true,
      nightStartMin: 22 * 60 + 30, // 10:30 pm
      nightEndMin: 6 * 60, // 6 am
    );
    bool at(int h, int m) =>
        NightModePolicy.shouldTint(DateTime(2026, 5, 3, h, m), evening);
    expect(at(22, 29), isFalse);
    expect(at(22, 30), isTrue);
    expect(at(2, 0), isTrue);
    expect(at(6, 0), isFalse);
    // a same-day window (a nap, 1-3 pm)
    const nap = StandbySettings(
      nightModeEnabled: true,
      nightStartMin: 13 * 60,
      nightEndMin: 15 * 60,
    );
    expect(NightModePolicy.shouldTint(DateTime(2026, 5, 3, 14), nap), isTrue);
    expect(NightModePolicy.shouldTint(DateTime(2026, 5, 3, 16), nap), isFalse);
  });

  test('night mode can auto-tint only during bedside hours', () {
    const enabled = StandbySettings(nightModeEnabled: true);
    const disabled = StandbySettings(nightModeEnabled: false);

    expect(
      NightModePolicy.shouldTint(DateTime(2026, 5, 3, 21), enabled),
      isTrue,
    );
    expect(
      NightModePolicy.shouldTint(DateTime(2026, 5, 3, 4), enabled),
      isTrue,
    );
    expect(
      NightModePolicy.shouldTint(DateTime(2026, 5, 3, 12), enabled),
      isFalse,
    );
    expect(
      NightModePolicy.shouldTint(DateTime(2026, 5, 3, 22), disabled),
      isFalse,
    );
  });

  test('theme presets expose distinct visual identities', () {
    final ids = standbyThemes.map((theme) => theme.id).toSet();

    expect(ids, containsAll(['aurora', 'night-red', 'solar', 'matrix']));
    expect(themeById('missing').id, 'aurora');
    expect(
      standbyThemes.map((theme) => theme.accent).toSet().length,
      standbyThemes.length,
    );
  });

  test('song position advances in real time only while playing', () {
    final t0 = DateTime(2026, 1, 1, 12);
    NowPlayingSnapshot snap({required bool playing, int duration = 200000}) =>
        NowPlayingSnapshot(
          title: 't',
          artist: 'a',
          source: 's',
          progress: 0,
          isPlaying: playing,
          isControllable: true,
          positionMs: 60000,
          durationMs: duration,
          fetchedAt: t0,
        );

    expect(
      snap(playing: true).positionAt(t0.add(const Duration(seconds: 5))),
      65000,
    );
    expect(
      snap(playing: false).positionAt(t0.add(const Duration(seconds: 5))),
      60000,
    );
    // never runs past the end of the song
    expect(
      snap(playing: true).positionAt(t0.add(const Duration(minutes: 10))),
      200000,
    );
  });

  test('clock does not tick every second for styles without seconds', () {
    final now = DateTime(2026, 10, 6, 12, 0, 10, 500);
    const flip = StandbySettings(
      showSeconds: true,
      clockStyle: ClockStyle.text, // cannot show seconds
    );
    const digital = StandbySettings(showSeconds: true);

    expect(
      ClockCadence.nextDelay(now, digital),
      const Duration(milliseconds: 500),
    );
    expect(
      ClockCadence.nextDelay(now, flip),
      greaterThan(const Duration(seconds: 30)),
    );
  });

  test('burn-in shift moves once a minute, not on every second tick', () {
    final t = DateTime(2026, 10, 6, 12, 0, 5);

    expect(
      BurnInProtection.shouldAdvance(t, DateTime(2026, 10, 6, 12, 0, 6)),
      isFalse,
    );
    expect(
      BurnInProtection.shouldAdvance(t, DateTime(2026, 10, 6, 12, 0, 59)),
      isFalse,
    );
    expect(
      BurnInProtection.shouldAdvance(t, DateTime(2026, 10, 6, 12, 1, 0)),
      isTrue,
    );
    expect(
      BurnInProtection.shouldAdvance(t, DateTime(2026, 10, 6, 13, 0, 5)),
      isTrue,
    );
    expect(
      BurnInProtection.shouldAdvance(t, DateTime(2026, 10, 7, 12, 0, 5)),
      isTrue,
    );
    expect(BurnInProtection.shouldAdvance(null, t), isTrue);
  });
}
