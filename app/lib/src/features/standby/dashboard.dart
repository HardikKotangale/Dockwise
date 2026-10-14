import 'package:flutter/gestures.dart'
    show PointerPanZoomUpdateEvent, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../core/apple.dart';
import '../../core/pinch_layout.dart';
import '../../domain/standby_models.dart';
import '../../state/standby_controller.dart';
import 'settings/all_settings.dart';
import 'settings/city_page.dart';
import 'settings/clock_settings.dart';
import 'settings/controls.dart' show clockLabel, widgetLabel;
import 'settings/simple_settings.dart';
import 'settings/summary_add.dart';
import 'widgets/clock_faces.dart';
import 'widgets/integration_cards.dart';
import 'widgets/music_sources_sheet.dart';
import 'widgets/spotify_queue.dart';
import 'widgets/spotify_search.dart';
import 'widgets/summary_card.dart';
import 'widgets/timer_card.dart';
import 'widgets/timer_entry.dart';
import 'widgets/timer_tile.dart';

const cardColor = Color(0xFF1C1C1E); // iOS secondary system background

const swipeVelocity = 300.0; // px/s: below this a drag is not a swipe

/// Opens a settings dock with [title]; [build] runs on every settings change
/// so the panels behind it update live.
typedef OpenDock = void Function(
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
  DateTime wheelAt = DateTime(0); // last mouse-wheel step (one step per flick)
  Offset swipeDir = Offset.zero; // which way the last swipe travelled
  Offset get center => points.length < 2
      ? Offset.zero
      : (points.values.first + points.values.last) / 2;

  double get distance => points.length < 2
      ? 0
      : (points.values.first - points.values.last).distance;
}

/// Opens the settings for a panel of [type], as a tap on it does: live
/// settings for that card (clock, music, weather...) or all settings.
void openPanelSettings({
  required StandbyController controller,
  required OpenDock openDock,
  required ValueNotifier<ClockPart?> clockPart,
  required StandbyWidgetType type,
  bool fromPart = false,
}) {
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

/// One step of a panel, as a swipe makes it (and the arrow keys): sideways
/// = next/previous widget; up/down = next/previous clock style, calendar
/// look, timer look or weather page. [step] 1 = next (a swipe left or up).
void stepPanel({
  required StandbyController controller,
  required PanelTouches touch,
  required Axis axis,
  required int step,
  required StandbyWidgetType type,
  required bool isLeft,
}) {
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
      onPointerSignal: (e) => _wheel(context, e),
      // a laptop trackpad's pinch: the same switch as two fingers on a screen
      onPointerPanZoomStart: (_) => touch.fired = false,
      onPointerPanZoomUpdate: _trackpadPinch,
      child: _layout(context),
    );
  }

  void _trackpadPinch(PointerPanZoomUpdateEvent e) {
    if (touch.fired || touch.multi || touch.locked) return;
    final ratio = e.scale; // 1 = fingers where they started
    final mode = ratio >= 1.3
        ? StandbyLayoutMode.single
        : ratio <= 0.77
        ? StandbyLayoutMode.duo
        : null;
    if (mode == null) return;
    touch.fired = true;
    onPinch(mode, e.position);
  }

  // A mouse wheel over a card is a swipe (vertical scroll = swipe up/down,
  // sideways scroll = swipe left/right). A trackpad's two-finger swipe arrives
  // as a pan and the card's own drag handlers already take it.
  // ponytail: one step per 400 ms, so a free-spinning wheel does not race through.
  void _wheel(BuildContext context, PointerEvent e) {
    if (e is! PointerScrollEvent || touch.locked) return;
    final d = e.scrollDelta;
    if (d.distance < 4) return;
    final now = DateTime.now();
    if (now.difference(touch.wheelAt) < const Duration(milliseconds: 400)) {
      return;
    }
    touch.wheelAt = now;
    final size = context.size ?? Size.zero;
    final duo = settings.layoutMode == StandbyLayoutMode.duo;
    final isLeft = !duo ||
        (stacked
            ? e.localPosition.dy < size.height / 2
            : e.localPosition.dx < size.width / 2);
    final horizontal = d.dx.abs() > d.dy.abs();
    stepPanel(
      controller: controller,
      touch: touch,
      axis: horizontal ? Axis.horizontal : Axis.vertical,
      step: (horizontal ? d.dx : d.dy) > 0 ? 1 : -1,
      type: isLeft ? settings.leftWidget : settings.rightWidget,
      isLeft: isLeft,
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

  void _open(StandbyWidgetType type, {bool fromPart = false}) =>
      openPanelSettings(
        controller: controller,
        openDock: openDock,
        clockPart: clockPart,
        type: type,
        fromPart: fromPart,
      );

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
    stepPanel(
      controller: controller,
      touch: touch,
      axis: axis,
      step: velocity < 0 ? 1 : -1, // swipe left/up = next
      type: type,
      isLeft: isLeft,
    );
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
          // For a screen reader the panel is a button that opens its settings,
          // with the swipes that change the panel as actions (a swipe is
          // hard to make with VoiceOver or TalkBack on).
          child: Semantics(
            container: true,
            label: '${widgetLabel(type)} panel',
            hint: 'Opens its settings',
            onTap: () => _open(type),
            customSemanticsActions: {
              const CustomSemanticsAction(label: 'Next panel'): () =>
                  controller.cyclePanelWidget(left: isLeft, step: 1),
              const CustomSemanticsAction(label: 'Previous panel'): () =>
                  controller.cyclePanelWidget(left: isLeft, step: -1),
            },
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
                    : Motion.medium,
                curve: easeOutStrong,
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
                            : Motion.slow,
                        // leaving is quicker than arriving
                        reverseDuration: calm(context, Motion.fast),
                        switchInCurve: easeOutStrong,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [...previous, ?current],
                        ),
                        // A swipe slides the new card in from the side you swiped
                        // toward while the old one eases away; anything else fades.
                        // Slide and fade move a snapshot of each card (see
                        // _Snapshotted), never rebuild or redraw it per frame
                        transitionBuilder: (child, animation) {
                          final dir = touch.swipeDir;
                          final incoming = child.key == _currentKey(type);
                          final travel = incoming ? dir : -dir;
                          return SlideTransition(
                            position: animation.drive(
                              Tween(begin: travel * 0.18, end: Offset.zero),
                            ),
                            child: FadeTransition(
                              opacity: animation,
                              child: _Snapshotted(
                                animation: animation,
                                child: child,
                              ),
                            ),
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

  // The timer as a Summary tile.
  Widget _timerTile() => TimerTile(
    settings: settings,
    leftMs: controller.timerLeftMs,
    totalMs: controller.timerTotalMs,
    running: controller.timerRunning,
    started: controller.timerStarted,
    done: controller.timerDone,
    onStart: controller.timerStart,
    onPause: controller.timerPause,
    onReset: controller.timerReset,
    onAddMinute: () => controller.timerAdd(const Duration(minutes: 1)),
    // not started: the set-timer window; running: the timer's settings
    onOpen: controller.timerStarted
        ? () => _open(StandbyWidgetType.timer)
        : _typeTimer,
    onSwipe: controller.toggleTimerStyle,
  );

  // The "+" on the Summary panel: choose a widget to add.
  void _addTile() => openDock(
    'Add a widget',
    () => SummaryAdd(controller: controller, onDone: closeDock),
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
        onDateSwipe: controller.toggleCalendarStyle,
        music: _musicCard(context),
        timer: _timerTile(),
        onAddTile: _addTile,
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
                // no Spotify app on this PC: offer it, rather than a dead end
                action: controller.spotifyMissing
                    ? SnackBarAction(
                        label: 'Get Spotify',
                        onPressed: controller.getSpotify,
                      )
                    : null,
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

/// While a card slides in or out it is drawn once into a picture, and the
/// picture is what slides and fades. The renderer keeps no cache between
/// frames, so the frosted glass (Summary), the blurred cover (music) and the
/// soft weather clouds were otherwise drawn again on every frame of the move,
/// and switching to those cards stuttered on a big screen. Once it has
/// arrived the card is live again.
class _Snapshotted extends StatefulWidget {
  const _Snapshotted({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_Snapshotted> createState() => _SnapshottedState();
}

class _SnapshottedState extends State<_Snapshotted> {
  final _snapshot = SnapshotController();

  void _status(AnimationStatus status) =>
      _snapshot.allowSnapshotting = status.isAnimating;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_status);
    _status(widget.animation.status);
  }

  @override
  void didUpdateWidget(_Snapshotted old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      old.animation.removeStatusListener(_status);
      widget.animation.addStatusListener(_status);
      _status(widget.animation.status);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_status);
    _snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: _snapshot,
    // anything that cannot be pictured is simply drawn live
    mode: SnapshotMode.permissive,
    child: widget.child,
  );
}
