import 'package:flutter/material.dart';

import '../../core/apple.dart';
import '../../core/pinch_layout.dart';
import '../../domain/standby_models.dart';
import '../../state/standby_controller.dart';
import 'settings/all_settings.dart';
import 'settings/city_page.dart';
import 'settings/clock_settings.dart';
import 'settings/controls.dart' show clockLabel;
import 'settings/simple_settings.dart';
import 'widgets/clock_faces.dart';
import 'widgets/integration_cards.dart';
import 'widgets/music_sources_sheet.dart';
import 'widgets/spotify_queue.dart';
import 'widgets/spotify_search.dart';
import 'widgets/summary_card.dart';
import 'widgets/timer_card.dart';
import 'widgets/timer_entry.dart';

const cardColor = Color(0xFF1C1C1E); // iOS secondary system background

const swipeVelocity = 300.0; // px/s: below this a drag is not a swipe

/// Opens a settings dock with [title]; [build] runs on every settings change
/// so the panels behind it update live.
typedef OpenDock =
    void Function(
      String title,
      Widget Function() build, {
      bool tall,
      bool fill,
    });

/// Tracks the fingers on screen so a two-finger pinch can be told apart from
/// a one-finger swipe.
class PanelTouches {
  final points = <int, Offset>{};
  double? startDistance; // between the two fingers when the second one landed
  bool fired = false; // this pinch already switched the layout
  bool multi = false; // two or more fingers were down: not a card swipe
  bool locked = false; // a tile is being dragged: no card swipes
  Offset swipeDir = Offset.zero; // which way the last swipe travelled
  Offset get center => points.length < 2
      ? Offset.zero
      : (points.values.first + points.values.last) / 2;

  double get distance => points.length < 2
      ? 0
      : (points.values.first - points.values.last).distance;
}

class Dashboard extends StatelessWidget {
  const Dashboard({
    super.key,
    required this.controller,
    required this.settings,
    required this.stacked,
    required this.openDock,
    required this.clockPart,
    required this.touch,
    required this.onPinch,
    required this.closeDock,
  });

  final StandbyController controller;
  final StandbySettings settings;
  final bool stacked; // portrait: panels stacked vertically
  final OpenDock openDock;
  final ValueNotifier<ClockPart?> clockPart;
  final PanelTouches touch;
  final void Function(StandbyLayoutMode mode, Offset center) onPinch;

  /// Closes the settings panel (for pages that end by going away).
  final VoidCallback closeDock;

  // Watches raw touches (it never competes with the swipe/tap gestures) to
  // spot a two-finger pinch: spread = one panel, pinch = two panels.
  void _decide() {
    if (touch.fired ||
        touch.points.length != 2 ||
        touch.startDistance == null) {
      return;
    }
    final mode = PinchLayout.layoutFor(touch.startDistance!, touch.distance);
    if (mode == null) return;
    touch.fired =
        true; // once per pinch, as soon as the fingers have moved enough
    onPinch(mode, touch.center);
  }

  void _release(PointerEvent e, {required bool decide}) {
    if (decide) _decide();
    touch.points.remove(e.pointer);
    touch.startDistance = null;
    if (touch.points.isEmpty) {
      // after this frame, so the swipe handlers (same moment) still see it
      WidgetsBinding.instance.addPostFrameCallback((_) => touch.multi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        touch.points[e.pointer] = e.position;
        if (touch.points.length >= 2) {
          touch.multi = true; // a pinch, never a card swipe
          if (touch.points.length == 2) {
            touch.startDistance = touch.distance;
            touch.fired = false;
          }
        }
      },
      onPointerMove: (e) {
        if (touch.points.containsKey(e.pointer)) {
          touch.points[e.pointer] = e.position;
          _decide();
        }
      },
      onPointerUp: (e) => _release(e, decide: true),
      onPointerCancel: (e) => _release(e, decide: false),
      child: _layout(context),
    );
  }

  Widget _layout(BuildContext context) {
    return SplitPanels(
      duo: settings.layoutMode == StandbyLayoutMode.duo,
      vertical: stacked,
      first: _panel(context, settings.leftWidget, isLeft: true),
      second: _panel(context, settings.rightWidget, isLeft: false),
    );
  }

  // Tap a panel to customize it live (clock, music, weather) or open all settings.
  void _open(StandbyWidgetType type, {bool fromPart = false}) {
    late void Function() all;
    void city(VoidCallback back) => openDock(
      'Choose a city',
      () => CityPage(controller: controller, onDone: back),
      tall: true,
    );
    void clock() => openDock(
      'Clock',
      () => ClockSettings(
        controller: controller,
        selected: clockPart,
        onAll: all,
        onCity: () => city(clock),
      ),
    );
    late void Function() music;
    all = () => openDock(
      'Settings',
      () => AllSettings(
        controller: controller,
        selected: clockPart,
        onCity: () => city(all),
        onMusic: () => music(),
      ),
    );
    music = () => openDock(
      'Music',
      () => MusicSourcesPanel(controller: controller, onAllSettings: all),
    );
    switch (type) {
      case StandbyWidgetType.clock:
        // World clock with no second city yet: go straight to the search, keyboard up
        if (!fromPart &&
            controller.settings.clockStyle == ClockStyle.world &&
            controller.settings.worldZone.isEmpty) {
          city(clock);
        } else {
          clock();
        }
      case StandbyWidgetType.music:
        openDock(
          'Music',
          () => MusicSourcesPanel(controller: controller, onAllSettings: all),
        );
      case StandbyWidgetType.weather:
        openDock(
          'Weather',
          () => WeatherSettings(controller: controller, onAll: all),
        );
      case StandbyWidgetType.calendar:
        openDock(
          'Calendar',
          () => CalendarSettings(controller: controller, onAll: all),
        );
      case StandbyWidgetType.timer:
        openDock(
          'Timer',
          () => TimerSettings(controller: controller, onAll: all),
        );
      case StandbyWidgetType.summary:
        all();
    }
  }

  // Swipe sideways: next/previous widget. Swipe up/down: next/previous clock
  // style (clock panel only).
  void _swiped(
    BuildContext context,
    Axis axis,
    double velocity,
    StandbyWidgetType type,
    bool isLeft,
  ) {
    if (velocity.abs() < swipeVelocity || touch.multi || touch.locked) {
      return;
    }
    final step = velocity < 0 ? 1 : -1; // swipe left/up = next
    // the new card arrives from the side the finger moved towards
    touch.swipeDir = axis == Axis.horizontal
        ? Offset(step.toDouble(), 0)
        : Offset(0, step.toDouble());
    if (axis == Axis.horizontal) {
      controller.cyclePanelWidget(left: isLeft, step: step);
    } else if (type == StandbyWidgetType.clock) {
      controller.cycleClockStyle(step);
    } else if (type == StandbyWidgetType.calendar) {
      controller.toggleCalendarStyle();
    } else if (type == StandbyWidgetType.timer) {
      controller.toggleTimerStyle();
    } else if (type == StandbyWidgetType.weather) {
      // up: the next page (now, forecast, second city); down: the one before
      controller.cycleWeatherPage(step);
    }
  }

  Widget _panel(
    BuildContext context,
    StandbyWidgetType type, {
    required bool isLeft,
  }) {
    final isClock = type == StandbyWidgetType.clock;
    // Music, weather and date cards fill the whole panel and size themselves.
    final Widget content = isClock
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ClockFace(
                time: controller.now,
                settings: settings,
                // tap hours / minutes... -> open Clock settings at that color
                onPartTap: (part) {
                  clockPart.value = null;
                  clockPart.value = part;
                  _open(StandbyWidgetType.clock, fromPart: true);
                },
              ),
            ),
          )
        : _card(context, type);
    return SizedBox.expand(
      child: RepaintBoundary(
        child: Pressable(
          scale: 0.985,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(type),
            onHorizontalDragEnd: (d) => _swiped(
              context,
              Axis.horizontal,
              d.primaryVelocity ?? 0,
              type,
              isLeft,
            ),
            onVerticalDragEnd: (d) => _swiped(
              context,
              Axis.vertical,
              d.primaryVelocity ?? 0,
              type,
              isLeft,
            ),
            // the panel's color eases to a new theme's, instead of jumping
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: isClock || type == StandbyWidgetType.timer
                    ? (settings.theme.panelColor ?? Colors.transparent)
                    : cardColor,
                borderRadius: BorderRadius.circular(32),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 420),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, ?current],
                      ),
                      // A swipe slides the new card in from the side you swiped
                      // toward while the old one eases away; anything else fades.
                      transitionBuilder: (child, animation) {
                        final dir = touch.swipeDir;
                        final incoming = child.key == _currentKey(type);
                        final travel = incoming ? dir : -dir;
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, c) {
                            final gone = 1 - animation.value;
                            return FractionalTranslation(
                              translation: travel * (0.18 * gone),
                              child: Opacity(
                                opacity: animation.value.clamp(0.0, 1.0),
                                child: c,
                              ),
                            );
                          },
                          child: child,
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(
                          '${type.name}-${isClock
                              ? settings.clockStyle.name
                              : type == StandbyWidgetType.calendar
                              ? settings.calendarStyle.name
                              : type == StandbyWidgetType.timer
                              ? settings.timerStyle.name
                              : ''}',
                        ),
                        child: content,
                      ),
                    ),
                    // Up and down swipes: small dots and a name for where it
                    // took you (the clock's styles, the calendar's views)
                    if (type == StandbyWidgetType.clock)
                      SwipeRail(
                        key: const ValueKey('clock-rail'),
                        index: settings.clockStyle.index,
                        labels: [
                          for (final st in ClockStyle.values) clockLabel(st),
                        ],
                      )
                    else if (type == StandbyWidgetType.calendar)
                      SwipeRail(
                        key: const ValueKey('calendar-rail'),
                        index: settings.calendarStyle.index,
                        labels: const ['Today', 'Month'],
                      )
                    else if (type == StandbyWidgetType.timer)
                      SwipeRail(
                        key: const ValueKey('timer-rail'),
                        index: settings.timerStyle.index,
                        labels: const ['Digital', 'Flip'],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // the key of the card shown for [type] right now
  ValueKey<String> _currentKey(StandbyWidgetType type) => ValueKey(
    '${type.name}-${type == StandbyWidgetType.clock
        ? settings.clockStyle.name
        : type == StandbyWidgetType.calendar
        ? settings.calendarStyle.name
        : type == StandbyWidgetType.timer
        ? settings.timerStyle.name
        : ''}',
  );

  // Type a timer length on our number pad.
  void _typeTimer() => openDock(
    'Set timer',
    () => TimerEntry(controller: controller, onDone: closeDock),
    tall: true,
    fill: true,
  );

  // Searching for the second city (the clock's, and the weather's third page).
  void _chooseCity() => openDock(
    'Choose a city',
    () => CityPage(controller: controller, onDone: closeDock),
    tall: true,
  );

  // The weather card; the Summary panel shows this same one in its tile.
  Widget _weatherCard() => WeatherCard(
    snapshot: controller.snapshots.weather,
    settings: settings,
    problem: controller.weatherProblem,
    page: controller.weatherPage,
    secondSnapshot: controller.secondWeather,
    secondFailed: controller.secondWeatherFailed,
    onCityTap: _chooseCity,
  );

  Widget _card(BuildContext context, StandbyWidgetType type) {
    return switch (type) {
      StandbyWidgetType.clock => const SizedBox.shrink(),
      StandbyWidgetType.summary => SummaryCard(
        now: controller.now,
        settings: settings,
        weather: _weatherCard(),
        onWeatherSwipe: controller.cycleWeatherPage,
        music: _musicCard(context),
        onLayout: (encoded) => controller.updateSettings(
          settings.copyWith(summaryLayout: encoded),
        ),
        onEditing: (on) => touch.locked = on,
        // tapping the second city goes straight to choosing another
        onCityTap: _chooseCity,
        onOpenMusic: () => _open(StandbyWidgetType.music),
        onOpenWeather: () => _open(StandbyWidgetType.weather),
      ),
      StandbyWidgetType.weather => _weatherCard(),
      StandbyWidgetType.calendar => CalendarCard(
        settings: settings,
        now: controller.now,
      ),
      StandbyWidgetType.music => _musicCard(context),
      StandbyWidgetType.timer => TimerCard(
        settings: settings,
        leftMs: controller.timerLeftMs,
        totalMs: controller.timerTotalMs,
        running: controller.timerRunning,
        started: controller.timerStarted,
        done: controller.timerDone,
        onStart: controller.timerStart,
        onPause: controller.timerPause,
        onReset: controller.timerReset,
        onAdd: (m) => controller.timerAdd(Duration(minutes: m)),
        onPreset: controller.timerSet,
        onType: _typeTimer,
        roomy: settings.layoutMode == StandbyLayoutMode.single,
        horizontal: settings.layoutMode == StandbyLayoutMode.duo,
      ),
    };
  }

  // The now-playing card. The Summary panel shows the very same one, so it
  // does everything the Music panel does.
  Widget _musicCard(BuildContext context) {
    return MusicCard(
      snapshot: controller.snapshots.nowPlaying,
      settings: settings,
      currentSource: settings.musicSource,
      onSource: controller.setMusicSource,
      // holding Next names the song that is coming
      nextUp: controller.spotifyConnected
          ? () async {
              final next = (await controller.spotifyQueue())?.next;
              final hit = next == null || next.isEmpty ? null : next.first;
              return hit == null
                  ? null
                  : 'Next: ${hit.title} · ${hit.subtitle}';
            }
          : null,
      loadDevices: controller.spotifyConnected
          ? controller.spotifyDevices
          : null,
      onDevice: (id) {
        controller.playOnSpotifyDevice(id);
      },
      // search is offered whenever Spotify is connected, even if nothing plays yet
      queueView: controller.spotifyConnected
          ? (close, keepOpen) => SpotifyQueueView(
              controller: controller,
              onClose: close,
              onTouch: keepOpen,
              // search from the queue to find a song to add
              onSearch: () {
                close();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => SpotifySearchPage(controller: controller),
                  ),
                );
              },
            )
          : null,
      onSearch: controller.spotifyConnected
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => SpotifySearchPage(controller: controller),
              ),
            )
          : null,
      // Spotify volume only when the song is controlled through the Spotify account
      volumeBar:
          controller.snapshots.nowPlaying.viaSpotifyApi &&
              controller.spotifyConnected
          ? (keepOpen) => SpotifyVolume(
              controller: controller,
              compact: true,
              onTouch: keepOpen,
            )
          : null,
      onCommand: (command) async {
        final ok = await controller.sendMediaCommand(command);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(controller.musicError ?? 'Command failed'),
              ),
            );
        }
        return ok;
      },
      onSeek: (ms) async {
        final ok = await controller.seekToMs(ms);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(controller.musicError ?? 'Could not seek'),
              ),
            );
        }
        return ok;
      },
    );
  }
}
