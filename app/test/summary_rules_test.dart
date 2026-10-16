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

  test('with one panel, swiping sideways reaches Summary after Music', () {
    final c = make(
      const StandbySettings(
        layoutMode: StandbyLayoutMode.single,
        leftWidget: StandbyWidgetType.music,
      ),
    );
    c.cyclePanelWidget(left: true, step: 1);
    expect(c.settings.leftWidget, StandbyWidgetType.summary);
    c.cyclePanelWidget(left: true, step: 1);
    expect(c.settings.leftWidget, StandbyWidgetType.timer);
    c.cyclePanelWidget(left: true, step: 1);
    expect(c.settings.leftWidget, StandbyWidgetType.photos);
    c.cyclePanelWidget(left: true, step: 1);
    expect(c.settings.leftWidget, StandbyWidgetType.clock); // wraps round
  });

  test('with two panels there is no Summary in the swipe order', () {
    final c = make(const StandbySettings());
    for (var i = 0; i < 6; i++) {
      c.cyclePanelWidget(left: false, step: 1);
      expect(c.settings.rightWidget, isNot(StandbyWidgetType.summary));
    }
  });

  test(
    'going to two panels while on Summary gives that panel something else',
    () {
      final c = make(
        const StandbySettings(
          layoutMode: StandbyLayoutMode.single,
          leftWidget: StandbyWidgetType.summary,
        ),
      );
      c.setLayout(StandbyLayoutMode.duo);
      expect(c.settings.layoutMode, StandbyLayoutMode.duo);
      expect(c.settings.leftWidget, StandbyWidgetType.clock);
      expect(c.settings.rightWidget, isNot(StandbyWidgetType.summary));
    },
  );
}
