import 'package:flutter_test/flutter_test.dart';
import 'package:standby_pro/src/domain/standby_models.dart';

void main() {
  test('calendar and music colors are kept, and default to the theme', () {
    const base = StandbySettings();
    expect(base.calendarColor, 0);
    expect(base.musicColor, 0);
    final s = base.copyWith(
      calendarColor: 0xFF30D158,
      musicColor: 0xFFFF375F,
      hereColor: 0xFF0A84FF,
      thereColor: 0xFFFF9F0A,
      summaryHours: 2,
    );
    final back = StandbySettings.fromJson(s.toJson());
    expect(back.calendarColor, 0xFF30D158);
    expect(back.musicColor, 0xFFFF375F);
    expect(back.hereColor, 0xFF0A84FF);
    expect(back.thereColor, 0xFFFF9F0A);
    expect(back.summaryHours, 2);
    expect(base.summaryHours, 0);
    expect(base.hereColor, 0);
    expect(back, s); // the colours count when two settings are compared
    expect(base.copyWith(musicColor: 5) == base, isFalse);
  });
}
