# Hushdock

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Android / iOS / Windows](https://img.shields.io/badge/Platform-Android%20%2F%20iOS%20%2F%20Windows-blue.svg)](#platforms)
[![Tech: Flutter](https://img.shields.io/badge/Tech-Flutter-02569B.svg)](#)

Hushdock turns a charging phone into a bedside display: big readable clocks, live weather, a calendar, a timer and a Spotify now-playing card, designed for a dark room. It is built with Flutter for Android and iPhone (and, experimentally, Windows), and is based on the open-source Standby Pro project.

The look is inspired by iOS StandBy, but the layouts, themes, controls and motion are original. The interface is built to feel like iOS: springs instead of fixed-time animations, glass surfaces, press feedback on touch-down, and layouts that rearrange themselves when you turn the phone.

<p align="center">
  <img src="docs/screenshots/frame-fullscreen.png" width="49%" alt="Frame clock filling the whole screen">
  <img src="docs/screenshots/night-mode.png" width="49%" alt="Night mode, dim red">
</p>
<p align="center">
  <img src="docs/screenshots/flip-clock.png" width="49%" alt="Flip clock with seconds">
  <img src="docs/screenshots/world-clock.png" width="49%" alt="World clock">
</p>
<p align="center">
  <img src="docs/screenshots/settings-dock.png" width="60%" alt="Live-preview settings dock">
</p>

*The clock screenshots are from an Android phone. The settings dock, the music screenshots and every animation below are rendered from the app's own widgets with sample data (`app/tool`).*

## Features

### Clocks

Digital, analog, frame, flip, mono, float, text and world clock. Colors are set per part (hours, minutes, colon, label, ticks), with presets such as "Red & white" and "Night red". 12/24-hour time, optional seconds and adjustable size.

Held upright, the clocks stack the hours over the minutes so the digits fill the tall screen; turned sideways they go back on one line. The parts glide between the two arrangements. The world clock searches any city in the world on the app's own keyboard.

<p align="center">
  <img src="docs/clock-rotate.gif" width="52%" alt="Digital, Flip and World clocks gliding between one line and stacked hours over minutes">
</p>

The flip clock gives every digit its own hinged card, and AM / PM is a small card too. A digit only flips when it changes.

<p align="center">
  <img src="docs/flip-clock.gif" width="62%" alt="Flip clock: each digit flips on its own card">
</p>

### Weather and calendar

- **Weather:** animated scenes (sun, clouds, rain, snow, fog, storm, night sky) from your phone's location. Swipe up and down for four pages: now, Fahrenheit, the forecast, and a second city.
- **Calendar:** today or the whole month (swipe up or down). The text scales with the panel in portrait and landscape, and the days land one after another when it appears.

Turn the phone and the calendar, the weather and the timer glide their parts from the portrait arrangement to the landscape one instead of swapping.

<p align="center">
  <img src="docs/calendar-rotate.gif" width="30%" alt="Calendar gliding between portrait and landscape">
  <img src="docs/weather-rotate.gif" width="30%" alt="Weather gliding between portrait and landscape">
  <img src="docs/timer-rotate.gif" width="30%" alt="Timer gliding between portrait and landscape">
</p>
<p align="center">
  <img src="docs/weather-scenes.gif" width="40%" alt="Animated weather scenes">
</p>

### Summary

One panel of widgets: the time here, the time in a second city, the date, the weather, the music card and the timer. Hold any tile and they jiggle like the iOS home screen: tap the red **-** to remove a widget, tap the dashed **+** to add one back, drag a tile onto another (or onto the empty place) to move it, then tap Done. There is room for three columns, and the arrangement is saved. It is only available with one panel.

<p align="center">
  <img src="docs/summary-widgets.gif" width="75%" alt="Summary panel: remove a widget, add the timer, swipe it to the flip style">
</p>

### Timer

A big digital or flip countdown with a small figure running along a track under it as the time goes: a horse towards a finish flag, or a football player towards the end zone. When the time is up the player scores: confetti and fireworks, a sound and a buzz, repeating every three seconds until you press Stop. The figures are a few strokes that only move with the clock, so a running timer costs next to nothing.

<p align="center">
  <img src="docs/timer-horse.gif" width="46%" alt="Timer, digital style: a horse gallops along the track">
  <img src="docs/timer-touchdown.gif" width="46%" alt="Timer, flip style: the player scores and confetti fly">
</p>

- **Buttons:** +1, +5 and +10 minutes, Reset, Start / Pause, and quick lengths from 1 minute to 2 hours. It also fits the Summary tile, whatever its shape.
- **Type a length:** tap the time. A window slides up with the app's own number pad; swipe it down or press X to go back.
- **Own look and sound:** its own colors (separate from the clock's), and an alarm, a chime or a fanfare, with an optional buzz. On Android a phone on silent buzzes instead.

<p align="center">
  <img src="docs/timer-type.gif" width="34%" alt="Typing 1 5 0 0 on the number pad">
</p>

### Music and Spotify

The music card shows what is playing with a sharp cover over a soft blurred backdrop, transport and 10-second skips, hold the progress bar to seek, and a source menu to pick a device. Its header has three small buttons: **queue**, **search** and **volume**.

<p align="center">
  <img src="docs/music-buttons.gif" width="40%" alt="Music card: press feedback, play and pause morph, a hold label naming the next song">
</p>

Sign in with Spotify to control playback on any device: a Mac, a speaker, a TV or the phone (Spotify Premium is needed for control).

- **Play goes to the right place.** With nothing playing, Play starts on this phone (it opens Spotify first if needed). A song or playlist you pick goes to the device that is already playing.
- **Search** on the app's own keyboard, so the phone's keyboard never covers the screen. Tap a result to play it, or **+** to add it to the queue.
- **Queue** shows what is playing and what is next. Tap a song to jump straight to it. Drag a song to reorder; Spotify's public API cannot move a queued song, so the new order takes effect as the current song ends.
- **Playlists** open into their songs: tap one and it plays with the rest of the playlist after it.
- **Volume** of the playing device, from the card or the music settings.

<p align="center">
  <img src="docs/screenshots/spotify-search.png" width="49%" alt="Spotify search with songs, albums and playlists">
  <img src="docs/screenshots/spotify-queue.png" width="49%" alt="The queue: now playing and next in queue">
</p>

### Layout and gestures

- **One or two panels.** Pinch with two fingers: spread for one panel (the one you spread on), pinch together for two.
- **Swipe sideways** to change the card; **swipe up or down** to change the clock style, the calendar view, the weather page or the timer style.
- **Page indicator.** After a swipe, small symbols show the pages for a moment. Press one and slide: a glass strip names each page under your finger, and lifting goes there.
- **Settings dock.** Tap any panel to open a dock whose changes preview live behind it. Drag its header to move it away.
- **Fits any screen.** Everything is laid out on a standard phone size and scaled to the real screen, in portrait and landscape.

<p align="center">
  <img src="docs/page-dots.gif" width="62%" alt="Page indicator: press, slide across the pages, lift to go there">
</p>

### Night and battery

- **Auto brightness:** the screen stays on while charging and follows the room light, like Apple's StandBy, with eased changes so a passing shadow does not flicker it.
- **Night mode:** your own hours, and it also starts when the room is dark. Colors fade to a dim red, amber or your accent, with no blue light.
- **OLED care:** the whole screen glides to a new spot once a minute on a slow orbit that never repeats, and it drops to about half brightness after 2, 5 or 10 minutes without a touch.
- **Battery badge** in the top-right corner when the battery is not full, and a **low-battery prompt** at a level you choose (default 20%).

<p align="center">
  <img src="docs/low-battery-prompt.gif" width="40%" alt="Low-battery prompt">
</p>

### Rotation and auto-start

- If the screen is not turned the way you hold the phone (for example iPhone rotation lock is on), Hushdock follows the phone by itself after a moment, using the gravity sensor, and notices a 180-degree flip. It never rotates while you are touching the screen.
- **Android only:** Hushdock opens itself when the phone is charging and propped up in landscape, and closes when you unplug (see [Android auto-start](#android-auto-start)).

### Accessibility

Controls are at least 28 pt, secondary text is at least 4.5:1 contrast, and Reduce Motion and the in-app **Animations** switch turn off every spring, slide and moving backdrop. For screen readers the page dots are labelled buttons, a clock reads as one sentence, and every swipe or drag has an action instead ("Next panel", "Move earlier", "Remove from Summary").

## Platforms

| Feature | Android | iPhone | Windows |
|---|---|---|---|
| All clock styles, themes, presets, layouts, pinch | Yes | Yes | Yes (pinch needs a touch screen) |
| Weather, calendar, world clock | Yes | Yes | Yes (weather needs Windows location services) |
| Night mode, burn-in shift, keep awake | Yes | Yes | Night mode and burn-in shift yes; no keep-awake |
| Brightness that follows the room light | Yes, with the light sensor | Through iOS's own auto-brightness (iPhone does not let apps read the sensor) | No |
| Night look when the room is dark | Yes | No (hours only) | No (hours only) |
| Spotify account control and volume | Yes | Yes | Yes |
| Battery badge and low-battery prompt | Yes | Yes | Laptops only |
| Spotify search and queue | Yes | Yes | Yes |
| Follows the phone's rotation (works with rotation lock on) | Yes | Yes | No |
| Show and control music from other apps on the phone | Yes | No (iOS does not allow it) | No |
| Open itself when docked and charging | Yes | No (iOS does not allow it; use the built-in StandBy) | No |

### Windows app (experimental)

The same app builds as a Windows program, `Hushdock.exe`. It has not been built or run on a Windows PC yet: the project is set up and the Dart code is tested as Windows, but the first real build may need fixes.

**What works:** every clock style, themes and layouts, weather and calendar, the world clock, timer, Summary, and Spotify (account control, search, queue, volume). **What a PC does not have:** a tilt sensor (the Float clock does not sway and the rotation hint is off), a charger to watch (no auto-start), a light sensor (no brightness that follows the room), and the phone's media sessions (no "music from other apps"). The battery number shows on laptops only. Windows does not keep the screen awake for the app: set your power plan to never sleep the display.

**Build it** (it must be built on Windows; Flutter cannot build a Windows app on a Mac):

1. Install [Flutter](https://docs.flutter.dev/get-started/install/windows/desktop) and Visual Studio 2022 with the **Desktop development with C++** workload (the Windows setup script does not install this). Check with `flutter doctor`.
2. In the `app` folder run:
   ```powershell
   flutter pub get
   flutter build windows --release
   ```
3. The program is in `app\build\windows\x64\runner\Release`: `Hushdock.exe` with its DLLs and the `data` folder. Keep them together. Zip the whole folder to share it, or wrap it in an installer with Inno Setup or MSIX.
4. For Spotify, add this redirect URI in the Spotify dashboard too: `http://127.0.0.1:43823/callback` (a PC cannot open a `hushdock://` link, so the browser returns to a small local server instead). Then follow [Spotify (optional)](#6-spotify-optional).

To try it without building a release: `flutter run -d windows`.

### Android auto-start

When enabled, a small foreground service watches the charger. While charging, it reads the gravity sensor at a low rate and opens Hushdock once the phone has been propped up (default 40° or more from flat) in landscape for 1.5 seconds. It closes the app as soon as you unplug, but only if it opened itself and you have not taken over the screen (opened it yourself, or pressed Home). To launch from the background it uses "Display over other apps" and a full-screen notification over the lock screen. In the app go to Settings > All settings > Auto-start; a checklist there shows what still needs to be allowed (overlay, notifications, battery set to Unrestricted).

## Permissions

| Platform | Permission | Used for |
|---|---|---|
| Both | Location, only while the app is open | Local weather and your city name |
| Both | Internet | Weather (Open-Meteo, BigDataCloud) and Spotify |
| Both | Motion sensor (no prompt needed) | The rotation hint reads the gravity direction |
| Android | Light sensor (no prompt needed) | Auto brightness and the dark-room night look |
| Android | Notification access (optional) | Reading what other apps are playing |
| Android | Display over other apps, full-screen notifications, foreground service, boot completed, wake lock | Auto-start and keeping the tilt sensor alive while charging |
| iPhone | None beyond location | |

Your location is used only to look up weather and a city name and is not stored anywhere but on your device.

## Getting Started

### 1. Install what you need

The full checklist with versions is in [requirements.txt](requirements.txt). Easiest is to let a script install whatever is missing:

| Your computer | Run | Builds for |
|---|---|---|
| **Mac** | `./scripts/setup_mac.sh` | Android and iPhone |
| **Windows** | `.\scripts\setup_windows.ps1` (in PowerShell) | Android, and the [Windows app](#windows-app-experimental) once Visual Studio is installed |

Add `--check` (Mac) or `-Check` (Windows) to only see what is missing without installing anything. Both scripts are safe to run again. They install Flutter, JDK 17 and Android Studio (plus CocoaPods on a Mac), set Flutter up to use JDK 17, accept the Android licenses, run `flutter pub get` and finish with `flutter doctor`.

> The Mac script has been tested. The Windows script follows the same steps but has not been run on a Windows PC yet. If it fails, the manual steps below do the same thing.

**Manual install, if you prefer**
1. Install [Flutter](https://docs.flutter.dev/get-started/install) (3.41 or newer) and make sure `flutter` works in a new terminal.
2. Install JDK 17 and tell Flutter to use it: `flutter config --jdk-dir <path to JDK 17>`.
3. Install [Android Studio](https://developer.android.com/studio), open it once to finish its setup wizard, then run `flutter doctor --android-licenses` and answer `y`.
4. Mac and iPhone only: install Xcode from the App Store, then `brew install cocoapods`.
5. Run `flutter doctor` and fix anything it marks with a cross.

### 2. Get the code

```bash
git clone https://github.com/HardikKotangale/Dockwise.git
cd Dockwise
```

### 3. Connect your phone

- **Android:** Settings > About phone, tap *Build number* 7 times, then Settings > Developer options > turn on *USB debugging*. Plug the phone in and accept the prompt. `flutter devices` should list it.
- **iPhone:** Settings > Privacy & Security > turn on *Developer Mode* and restart. Plug in the iPhone and tap *Trust*. Then open `app/ios/Runner.xcworkspace` in Xcode once, pick your Apple ID under *Signing & Capabilities > Team*, and close Xcode.

An Android emulator from Android Studio also works.

### 4. Run it

```bash
cd app
flutter pub get
flutter devices                       # find your phone's id
flutter run                           # Android (add -d <id> if you have several devices)
flutter run -d <iphone-id> --release  # iPhone
```

Always open `ios/Runner.xcworkspace`, never `Runner.xcodeproj`, or Xcode will say a plugin module was not found.

### 5. First run on the phone

- Allow **location** when asked (weather and your city name). You can say no; the clock still works.
- Optional, Android only: Settings > All settings > **Auto-start** to open Hushdock when you dock the phone. A checklist there shows what still needs to be allowed.
- Tap any panel to change clock style, colors and layout. Pinch with two fingers to switch between one and two panels.

### 6. Spotify (optional)

1. Create an app at <https://developer.spotify.com/dashboard> and add the redirect URI `hushdock://spotify-callback` (and `http://127.0.0.1:43823/callback` if you use the Windows app).
2. Copy `app/lib/src/services/spotify_config.example.dart` to `app/lib/src/services/spotify_config.dart` and paste your Client ID. That file is git-ignored, so your Spotify app is never committed. (The setup scripts create the file for you.)
3. Or pass it at build time: `flutter run --dart-define=SPOTIFY_CLIENT_ID=your_id`.
4. In the app, open the music card's settings and tap **Connect Spotify**. Spotify Premium is needed to control playback.

### 7. Tests

```bash
cd app
flutter test
flutter analyze
cd android && ./gradlew :app:testDebugUnitTest   # tilt-detection unit tests (Windows: gradlew.bat)
```

### Troubleshooting

| Problem | Fix |
|---|---|
| `flutter doctor` shows Android licenses not accepted | `flutter doctor --android-licenses` and answer `y` |
| Gradle fails with "Unsupported class file" or a Java version error | Flutter is using the wrong JDK: `flutter config --jdk-dir <path to JDK 17>` |
| No devices listed | Check the cable and *USB debugging*, accept the prompt on the phone, then `adb kill-server` and try again |
| Xcode: `Module 'flutter_web_auth_2' not found` | Open `ios/Runner.xcworkspace`, not the `.xcodeproj` |
| iPhone says the developer is not trusted | Settings > General > VPN & Device Management > trust your Apple ID |
| iPhone app stops opening after 7 days | A free Apple ID expires after 7 days; run it from Xcode or `flutter run` again |
| Spotify login opens but does not come back | The redirect URI in the Spotify dashboard must be exactly `hushdock://spotify-callback` |
| Spotify says it needs a Client ID | Create `spotify_config.dart` as described above |

## Project Layout

- `app/lib/src/domain`: settings, themes, presets and the data shown on the cards.
- `app/lib/src/core`: pinch gesture, night-mode policy, clock cadence and burn-in policy, and `motion/` (springs, press feedback, glass, the page indicator, the clock morph).
- `app/lib/src/features/standby`: the main screen and dashboard, `settings/` pages, `widgets/` (one file per clock style under `clock/`, weather, calendar, music and Summary cards, battery, keyboard).
- `app/lib/src/services`: Spotify, weather, city search and the native bridge.
- `app/android/.../standbypro`: auto-start service, posture (tilt) logic, media session bridge.
- `app/ios/Runner`: small Swift bridge for keep-awake and brightness.
- `app/windows`: the Windows runner (generated by Flutter; only the name and icon were changed).
- `scripts`: one-command setup for macOS and Windows. `requirements.txt` lists everything the project needs.
- `spec`: formal models (PlusCal, checked with the TLC model checker) of the posture detection and the auto-launch logic, with the bugs they found. See [spec/README.md](spec/README.md).
- `docs`: screenshots and animations used in this README, and [ARCHITECTURE.md](docs/ARCHITECTURE.md).
- `app/tool`: records the README animations (`flutter test tool/readme_gifs_test.dart`, then `python3 tool/frames_to_gif.py`).

## License

MIT. See [LICENSE](LICENSE).
