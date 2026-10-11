import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/domain/standby_models.dart';
import 'package:standby_pro/src/state/standby_controller.dart';

// The controller applies a settings change to `settings` straight away (before
// it saves or talks to the system), so these read it without waiting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  StandbyController make(StandbySettings s) {
    final c = StandbyController(autostartTicker: false, initialSettings: s);
    addTearDown(c.dispose);
    return c;
  }

  test('a three-finger swipe sends the one panel to Summary and back', () {
    final c = make(
      const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.weather,
      ),
    );
    c.toggleSummary(left: true);
    expect(c.settings.leftWidget, StandbyWidgetType.summary);
    c.toggleSummary(left: true);
    expect(c.settings.leftWidget, StandbyWidgetType.weather); // where it was
  });

  test('with two panels there is no Summary: the swipe does nothing', () {
    final c = make(const StandbySettings());
    c.toggleSummary(left: true);
    c.toggleSummary(left: false);
    expect(c.settings.leftWidget, StandbyWidgetType.clock);
    expect(c.settings.rightWidget, StandbyWidgetType.weather);
  });

  test('swiping through widgets skips Summary with two panels only', () {
    final duo = make(const StandbySettings());
    for (var i = 0; i < 6; i++) {
      duo.cyclePanelWidget(left: false, step: 1);
      expect(duo.settings.rightWidget, isNot(StandbyWidgetType.summary));
    }
    final single = make(
      const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.music,
      ),
    );
    single.cyclePanelWidget(left: true, step: 1);
    expect(single.settings.leftWidget, StandbyWidgetType.summary);
  });

  test(
    'going to two panels while on Summary returns that panel to what it was',
    () {
      final c = make(
        const StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.calendar,
        ),
      );
      c.toggleSummary(left: true);
      expect(c.settings.leftWidget, StandbyWidgetType.summary);
      c.setLayout(StandbyLayoutMode.duo);
      expect(c.settings.layoutMode, StandbyLayoutMode.duo);
      expect(c.settings.leftWidget, StandbyWidgetType.calendar);
      expect(c.settings.rightWidget, isNot(StandbyWidgetType.summary));
    },
  );
}
