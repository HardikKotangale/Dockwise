# Formal specs (PlusCal + TLC)

Two small PlusCal models of the Kotlin logic that decides when Dockwise opens and closes itself, checked with the TLC model checker. TLC found four real problems in the Kotlin code. Each is fixed, pinned by a JVM regression test, and the fix is proven in the model by a switch (`Fix*` constant) that turns the model from "code as it was" to "code as it is now".

```
./spec/run_tlc.sh        # downloads tla2tools.jar once, runs all 12 configs, exit 0 = all behave as expected
```

Needs Java. Raw TLC output of every run is in [results/](results/), and `python3 trace_summary.py results/<cfg>.txt` prints a counterexample as a compact step table.

## What is modelled

| Module | Kotlin it models | Question |
|---|---|---|
| [PostureLogic.tla](PostureLogic.tla) | `PostureLogic.onSample` / `reset` (dwell timers, hysteresis, free-fall) | Can the debounced "phone is docked" flag turn on or off without the posture really being held for the dwell time? |
| [AutoLaunch.tla](AutoLaunch.tla) | `StandbyService` (power receiver, sensor callback, 700 ms `postDelayed` launch, notification) and `MainActivity` (`launchedByAuto`, `onNewIntent`, exit receiver) | Does the app open when it should, and close only what the watcher opened? |

Model choices:
- **Time is abstract.** `PostureLogic` uses a saturating "age" of each timer in sample periods (not absolute timestamps), which keeps the state space finite. `GapLimit = 2` periods corresponds to `maxGapMs = 500`.
- **Android is nondeterministic.** All callbacks (broadcast, sensor, handler, lifecycle, user taps) run in one process that picks the next event, so every interleaving is explored. A launch may succeed or be silently refused (`BAL_BLOCK`).
- **Fairness.** The process is `fair` (weak fairness), so liveness counterexamples are real lassos, not "TLC just stopped".
- **Ghost variables** (`userOwned`, `closedWhileUserVisible`, `gLen`, `hLen`, ...) exist only to state requirements; they never feed back into behaviour.

## Spec to code map

| Spec | Kotlin |
|---|---|
| `goodAge` / `badAge` | `goodSince` / `badSince` |
| `OnSample` label | `PostureLogic.onSample` (line for line) |
| `GapLimit`, `FixGaps` | `Config.maxGapMs`, the `lastSampleMs` check |
| `Plug` / `Unplug` branch | `StandbyService.setCharging(on)` → `AutoSession.setCharging` |
| `PostureChange` | `onSensorChanged` → `AutoSession.onPosture` |
| `pendingLaunch`, `PerformLaunch` | 700 ms `postDelayed` → `launchQueued` / `launchDue` |
| `notified`, `FixWatchdog` | `notifyToOpen()`, 3 s watchdog → `watchdogDue` |
| `launchedByAuto`, `FixNewIntent`, `FixLeave` | `MainActivity.launchedByAuto` → `activityNewIntent`, `userLeft` |
| `FixRace` | `cancelPendingLaunch()` on unplug |

The decision logic of the service/activity pair was pulled out of Android classes into the pure class `AutoSession.kt` so the JVM tests in `AutoSessionTest.kt` replay the traces below against the real code.

## Properties

PostureLogic: `TypeOK`; `EnterSound` (active only after the posture was matched for the full enter dwell); `ExitSound` (inactive only after it was lost for the full exit dwell); `HysteresisKeepsActive`; `FreeFallIgnored`; `GhostConsistent`; liveness `EnterLive == <>active` (steady match) and `ExitLive == <>~active` (steady mismatch).

AutoLaunch: `NoSurpriseClose` (R1: an unplug never closes a screen the user opened or took over); `UnplugLeavesNothingAutoOpened` (R2); `FlagOnlyWithTask`, `WasActiveImpliesCharging`; liveness `EventuallyOffered == <>(visible \/ notified)` (R3: docked and charging means the user is shown the app or offered a notification).

## Results

"Expected" = the outcome the config was designed to show. All 12 match.

| Config | What it checks | Result | States | Trace |
|---|---|---|---|---|
| PostureLogic_nogaps | original code, samples evenly spaced | passes | 5027 | – |
| PostureLogic_gaps | original code, holes in the data, enter | **EnterSound violated** | 126 | 7 steps |
| PostureLogic_gaps_exit | original code, holes in the data, exit | **ExitSound violated** | 653 | 10 steps |
| PostureLogic_gaps_fixed | with the gap rule | passes | 15849 | – |
| PostureLogic_live_enter | steady match | `EnterLive` holds | 30 | – |
| PostureLogic_live_exit | steady mismatch | `ExitLive` holds | 32 | – |
| AutoLaunch_race | unplug during the 700 ms wait | **R2 violated** | 11 | 5 steps |
| AutoLaunch_ownership | user taps the icon during the wait | **R1 violated** | 34 | 6 steps |
| AutoLaunch_ownership_partial | user goes Home and comes back | **R1 violated** | 42 | 7 steps |
| AutoLaunch_live_original | Android silently refuses the launch | **R3 violated** (lasso) | 6 | 5 steps |
| AutoLaunch_fixed | all four fixes, all events | passes | 48 | – |
| AutoLaunch_live_fixed | all fixes, liveness | `EventuallyOffered` holds | 5 | – |

## Counterexamples

### 1. A hole in the sensor data counts as a held posture (PostureLogic, enter and exit)

`PostureLogic_gaps`: `EnterSound` violated. Enter dwell is 3 periods.

| # | Step | Effect |
|---|---|---|
| 2 | Tick | sample "match" arrives |
| 3 | OnSample | `goodAge = 0` (timer starts) |
| 5 | Tick | **a 3-period gap**, then another match: `goodAge = 3` |
| 6 | OnSample | `active = TRUE` |

Two matching samples three periods apart activated the posture. Nothing proved it was held in between (the phone may have been picked up and put down). The exit side is symmetric (`PostureLogic_gaps_exit`, 10 steps): one mismatch, a 4-period gap, then a second sample, and the age reaches the exit dwell of 8 with `exitedWith = 0`.

Why it matters: the sensor listener is paused and resumed (screen state, charger changes), so gaps happen in real use. The code compared timestamps only.

Fix: `PostureLogic.Config.maxGapMs = 500`. If two samples are further apart than that, both timers restart. Model switch `FixGaps`; tests `aHoleInTheDataIsNotEvidenceThatThePostureWasHeld`, `...WasLost`, `aSingleMissedSampleIsTolerated`, `freeFallSamplesCountAsDataForTheGapRule` (the first two fail on the old code).

### 2. Unplug while the launch is queued (AutoLaunch_race)

`UnplugLeavesNothingAutoOpened` violated:

| # | Step | Effect |
|---|---|---|
| 2 | Plug | `charging = TRUE` |
| 3 | PostureChange | docked: `pendingLaunch = TRUE` (700 ms timer) |
| 4 | Unplug | `charging = FALSE`; nothing to close yet |
| 5 | PerformLaunch | the timer still fires: app opens, `launchedByAuto = TRUE` |

The app opens on a phone that is no longer charging, and since the unplug broadcast was already handled, nothing ever closes it.

Fix: unplug removes the queued launch (`cancelPendingLaunch()`), and `launchDue()` also requires `charging`. Model switch `FixRace`; test `unpluggingCancelsALaunchThatIsStillQueued`. (The `launchDue` guard alone is a redundant mutant of the cancel; the test asserts both.)

### 3. Auto-launch claims a screen the user already owns (AutoLaunch_ownership)

`NoSurpriseClose` violated: Plug, PostureChange, **UserOpen**, PerformLaunch, Unplug.

The user taps the icon during the 700 ms wait. The watcher's launch then arrives as `onNewIntent` with `auto = true` and sets `launchedByAuto = TRUE` on the screen the user is looking at. Unplug closes it.

Fix: `onNewIntent` only sets the flag if the activity is not visible. Switch `FixNewIntent`; test `anAutoLaunchDoesNotClaimAScreenTheUserAlreadyHasOpen`, plus `anAutoLaunchThatBringsABackgroundedAppForwardStillOwnsIt` so the fix does not over-correct.

### 4. The claim survives going Home (AutoLaunch_ownership_partial)

With fix 3 alone TLC still finds a 7-step violation: Plug, PostureChange, PerformLaunch, **UserHome**, **UserOpen**, Unplug. The user leaves the auto-opened app, comes back by themselves (no new intent, so no new flag), and the old claim closes their screen on unplug.

Fix: `onUserLeaveHint` clears `launchedByAuto`. Switch `FixLeave`; test `goingHomeEndsTheWatchersClaimOnTheScreen`.

### 5. A silent launch refusal leaves the user with nothing (AutoLaunch_live_original)

`EventuallyOffered` violated by a lasso: Plug, PostureChange, PerformLaunch (`res = "silent"`), then stuttering forever.

Android can refuse a background activity launch without an error (`startActivity` returns normally). The edge detector only fires once per docking, so there is no retry, no screen, and no notification.

Fix: a 3 s watchdog after `startActivity`; if nothing is on screen and still charging, post the "tap to open" notification. Switch `FixWatchdog`; tests `aLaunchThatNeverShowedTheScreenIsNoticedByTheWatchdog`, `noNotificationIsNeededWhenTheScreenDidAppear`, `noNotificationIsPostedForAChargerThatIsGone`.

## Tests as evidence

`./gradlew :app:testDebugUnitTest` (from `app/android`) runs 28 Kotlin tests (`PostureLogicTest`, `AutoSessionTest`). The regression tests were mutation-checked: removing each fix makes its test fail. The one survivor, the redundant `launchDue` charging guard, is an equivalent mutant of the cancel and is covered by asserting `pendingLaunch` directly.

## Modelling pitfalls hit (and what they taught)

- **PlusCal reads see earlier writes in the same step.** The first `AutoLaunch` edge test read the already-updated `wasActive`, so the bug did not show up and the "fixed" run failed on state count. The edge test must come before `wasActive := p`.
- **An over-permissive environment gives false alarms.** `AutoLaunch_fixed` first failed on a user "tapping the launcher" while the app was visible, which is impossible. `UserOpen` now requires `~visible`.
- **TLC metadirs collide** when two runs start in the same second, giving a spurious empty failure; the script gives each config its own `-metadir`.

## Limits

- The model is only as good as the mapping: it does not prove the Kotlin compiles to what the spec says, only that the logic modelled is sound. `AutoSession` and `PostureLogic` are the parts where the spec and the code match line for line.
- Time is abstract (sample periods); real jitter is covered only by the `maxGapMs` threshold choice.
- Android behaviour (launch refusal, broadcast ordering) is assumed to be arbitrary, which is conservative, not measured.
- The new service/activity wiring has been compiled and unit-tested on the JVM but not yet exercised on a real phone.
