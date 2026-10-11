# Architecture

Flutter app in `app/`, with a small native Android layer in Kotlin.

```
app/lib/src/
  app.dart                  MaterialApp, the iOS-style theme
  core/                     no UI of its own; pure logic and motion helpers
    motion/                 springs, Pressable, Glass, SpringDock, SplitPanels,
                            PageDots, HoldLabel (apple.dart re-exports them)
    screen_fit, night_mode_policy, burn_in_protection, ...   small pure rules
  domain/                   StandbySettings, SummaryLayout, snapshots (plain data)
  data/                     SettingsRepository (SharedPreferences)
  services/                 Spotify, weather, city search, the Android bridge
  state/                    StandbyController: the one ChangeNotifier
  features/standby/
    standby_screen.dart     the screen: layout, dock, page dots, low battery
    dashboard.dart          the panels, swipes and pinch gestures
    widgets/                weather/calendar/music cards, Summary, dock, keyboard
    widgets/clock/          one file per clock style, plus shared clock helpers
    settings/               the pages inside the settings dock
app/android/.../kotlin/     PostureLogic, AutoSession, StandbyService (see spec/)
spec/                       PlusCal models checked with TLC, and their results
```

Rules the code follows:

- **Logic out of widgets.** Anything with a rule worth testing (posture debounce,
  auto-launch ownership, night tint, pinch, Summary layout) is a plain class with
  unit tests; widgets only draw and forward.
- **One state object.** `StandbyController` owns settings, the music and weather
  snapshots and the timers; screens listen to it. Settings changes go through
  `updateSettings`, which normalises them (for example, no Summary with two panels).
- **Motion is a setting.** Every animation reads `MediaQuery.disableAnimations`,
  which the screen sets from the Animations switch (and the OS Reduce Motion), so
  turning it off stops springs, slides and the moving weather backdrop together.
- **Motion rules.** Press feedback is about 100 to 160 ms and subtle; entrances
  use a strong ease-out, never ease-in; nothing starts from scale 0; springs are
  critically damped unless a flick came first. Only transform and opacity animate
  where possible.
- **Tests.** `flutter test` for the app, `./gradlew :app:testDebugUnitTest` (in
  `app/android`) for Kotlin, `./spec/run_tlc.sh` for the formal models.
