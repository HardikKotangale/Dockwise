import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/burn_in_protection.dart';
import '../../core/pinch_layout.dart';
import '../../core/night_mode_policy.dart';
import '../../domain/standby_models.dart';
import '../../services/city_search.dart';
import '../../services/standby_system_service.dart';
import '../../services/weather_service.dart';
import '../../state/standby_controller.dart';
import 'widgets/battery_badge.dart';
import 'widgets/clock_faces.dart';
import 'widgets/integration_cards.dart';
import 'widgets/mini_keyboard.dart';
import 'widgets/music_sources_sheet.dart';

const _cardColor = Color(0xFF1C1C1E); // iOS secondary system background
const _swipeVelocity = 300.0; // px/s: below this a drag is not a swipe

/// Opens a settings dock with [title]; [build] runs on every settings change
/// so the panels behind it update live.
typedef OpenDock =
    void Function(String title, Widget Function() build, {bool tall});

/// Tracks the fingers on screen so a two-finger pinch can be told apart from
/// a one-finger swipe.
class _Touch {
  final points = <int, Offset>{};
  double? startDistance; // between the two fingers when the second one landed
  bool fired = false; // this pinch already switched the layout
  bool multi = false; // two or more fingers were down: not a card swipe

  Offset get center => points.length < 2
      ? Offset.zero
      : (points.values.first + points.values.last) / 2;

  double get distance => points.length < 2
      ? 0
      : (points.values.first - points.values.last).distance;
}

class StandbyScreen extends StatefulWidget {
  const StandbyScreen({
    super.key,
    this.initialSettings,
    this.systemService,
    this.battery,
  });

  final StandbySettings? initialSettings;
  final StandbySystemService? systemService;

  /// Battery source; tests pass a fake one.
  final BatteryMonitor? battery;

  @override
  State<StandbyScreen> createState() => _StandbyScreenState();
}

class _StandbyScreenState extends State<StandbyScreen> {
  late final StandbyController _controller;
  late final BatteryMonitor _battery = widget.battery ?? BatteryMonitor();
  String _dockTitle = '';
  Widget Function()? _dockBuild;
  bool _dockTall = false; // portrait: use the whole screen (e.g. city search)
  // Which clock part was tapped on screen; the Clock dock jumps to its color.
  final _clockPart = ValueNotifier<ClockPart?>(null);
  final _touch = _Touch();
  // a short dark pop-up confirming a layout change ("One panel")
  ({IconData icon, String text})? _hud;
  bool _hudVisible = false;
  Timer? _hudTimer;

  void _showHud(IconData icon, String text) {
    _hudTimer?.cancel();
    setState(() {
      _hud = (icon: icon, text: text);
      _hudVisible = true;
    });
    _hudTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _hudVisible = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = StandbyController(
      initialSettings: widget.initialSettings,
      systemService: widget.systemService,
      autostartTicker: widget.initialSettings == null,
    );
    if (widget.initialSettings == null) {
      _controller.initialize();
    } else {
      _controller.initializeForTest();
    }
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _clockPart.dispose();
    _controller.dispose();
    if (widget.battery == null) _battery.dispose();
    super.dispose();
  }

  void _openDock(String title, Widget Function() build, {bool tall = false}) {
    setState(() {
      _dockTitle = title;
      _dockBuild = build;
      _dockTall = tall;
    });
  }

  void _closeDock() {
    _clockPart.value = null;
    setState(() => _dockBuild = null);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final settings = _controller.settings;
        final offset = BurnInProtection.offsetForTick(
          _controller.burnInTick,
          settings,
        );
        return Scaffold(
          backgroundColor: Colors.black,
          // the low-battery prompt covers the whole screen, above everything
          body: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                minimum: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, c) {
                    // Landscape: dock on the right; portrait: dock at the bottom.
                    final landscape = c.maxWidth >= 700;
                    final dashboard = Stack(
                      children: [
                        // glide to the next burn-in position (once a minute)
                        TweenAnimationBuilder<Offset>(
                          tween: Tween(end: Offset(offset.dx, offset.dy)),
                          duration: const Duration(milliseconds: 1500),
                          curve: Curves.easeInOutCubic,
                          builder: (context, o, child) {
                            final moved = Transform.translate(
                              offset: o,
                              child: child,
                            );
                            return NightModePolicy.shouldTint(
                                  _controller.now,
                                  settings,
                                )
                                ? ColorFiltered(
                                    colorFilter: NightModePolicy.filter(
                                      settings,
                                    ),
                                    child: moved,
                                  )
                                : moved;
                          },
                          // a thin strip on top is always reserved for the battery
                          // badge, so cards never resize when it appears or hides
                          child: Column(
                            children: [
                              SizedBox(
                                height: 22,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: BatteryBadge(
                                      monitor: _battery,
                                      lowAt: settings.lowBatteryLevel,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _Dashboard(
                                  controller: _controller,
                                  settings: settings,
                                  stacked: !landscape,
                                  openDock: _openDock,
                                  clockPart: _clockPart,
                                  touch: _touch,
                                  onPinch: (mode, center) {
                                    if (mode == settings.layoutMode) return;
                                    // zooming into a panel keeps that panel, not always the left one
                                    final size = MediaQuery.sizeOf(context);
                                    final onSecond = landscape
                                        ? center.dx > size.width / 2
                                        : center.dy > size.height / 2;
                                    _controller.setLayout(
                                      mode,
                                      soloSecond: onSecond,
                                    );
                                    _showHud(
                                      mode == StandbyLayoutMode.single
                                          ? Icons.crop_square_rounded
                                          : Icons.vertical_split_rounded,
                                      mode == StandbyLayoutMode.single
                                          ? 'One panel'
                                          : 'Two panels',
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_hud != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: AnimatedOpacity(
                                  opacity: _hudVisible ? 1 : 0,
                                  duration: const Duration(milliseconds: 220),
                                  child: _Hud(
                                    icon: _hud!.icon,
                                    text: _hud!.text,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                    final build = _dockBuild;
                    if (build == null) return dashboard;
                    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
                    final dock = _Dock(
                      title: _dockTitle,
                      onClose: _closeDock,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) => build(),
                      ),
                    );
                    // Keyboard up in portrait: give the dock all the visible space so
                    // what you type is never hidden behind it.
                    if ((typing || _dockTall) && !landscape) return dock;
                    return landscape
                        ? Row(
                            children: [
                              Expanded(child: dashboard),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: (c.maxWidth * 0.42).clamp(320.0, 460.0),
                                child: dock,
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(child: dashboard),
                              const SizedBox(height: 12),
                              SizedBox(height: c.maxHeight * 0.46, child: dock),
                            ],
                          );
                  },
                ),
              ),
              Positioned.fill(
                child: LowBatteryAlert(
                  monitor: _battery,
                  enabled: settings.lowBatteryAlert,
                  lowAt: settings.lowBatteryLevel,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Dark, rounded pop-up (like the iOS volume HUD) confirming a layout change.
class _Hud extends StatelessWidget {
  const _Hud({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xF21C1C1E),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: Colors.white),
          const SizedBox(width: 14),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material (not a decorated box) so list tiles can paint ink inside.
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Done',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.controller,
    required this.settings,
    required this.stacked,
    required this.openDock,
    required this.clockPart,
    required this.touch,
    required this.onPinch,
  });

  final StandbyController controller;
  final StandbySettings settings;
  final bool stacked; // portrait: panels stacked vertically
  final OpenDock openDock;
  final ValueNotifier<ClockPart?> clockPart;
  final _Touch touch;
  final void Function(StandbyLayoutMode mode, Offset center) onPinch;

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
    if (settings.layoutMode == StandbyLayoutMode.single) {
      return _panel(context, settings.leftWidget, isLeft: true);
    }
    final children = [
      Expanded(child: _panel(context, settings.leftWidget, isLeft: true)),
      const SizedBox(width: 12, height: 12),
      Expanded(child: _panel(context, settings.rightWidget, isLeft: false)),
    ];
    return stacked ? Column(children: children) : Row(children: children);
  }

  // Tap a panel to customize it live (clock, music, weather) or open all settings.
  void _open(StandbyWidgetType type, {bool fromPart = false}) {
    late void Function() all;
    void city(VoidCallback back) => openDock(
      'Choose a city',
      () => _CityPage(controller: controller, onDone: back),
      tall: true,
    );
    void clock() => openDock(
      'Clock',
      () => _ClockSettings(
        controller: controller,
        selected: clockPart,
        onAll: all,
        onCity: () => city(clock),
      ),
    );
    late void Function() music;
    all = () => openDock(
      'Settings',
      () => _AllSettings(
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
          () => _WeatherSettings(controller: controller, onAll: all),
        );
      case StandbyWidgetType.calendar:
        openDock(
          'Calendar',
          () => _CalendarSettings(controller: controller, onAll: all),
        );
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
    if (velocity.abs() < _swipeVelocity || touch.multi) return;
    final step = velocity < 0 ? 1 : -1; // swipe left/up = next
    if (axis == Axis.horizontal) {
      controller.cyclePanelWidget(left: isLeft, step: step);
    } else if (type == StandbyWidgetType.clock) {
      controller.cycleClockStyle(step);
    } else if (type == StandbyWidgetType.calendar) {
      controller.toggleCalendarStyle();
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isClock
                  ? (settings.theme.panelColor ?? Colors.transparent)
                  : _cardColor,
              borderRadius: BorderRadius.circular(32),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: KeyedSubtree(
                  key: ValueKey(
                    '${type.name}-${isClock
                        ? settings.clockStyle.name
                        : type == StandbyWidgetType.calendar
                        ? settings.calendarStyle.name
                        : ''}',
                  ),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, StandbyWidgetType type) {
    return switch (type) {
      StandbyWidgetType.clock => const SizedBox.shrink(),
      StandbyWidgetType.weather => WeatherCard(
        snapshot: controller.snapshots.weather,
        settings: settings,
        problem: controller.weatherProblem,
      ),
      StandbyWidgetType.calendar => CalendarCard(
        settings: settings,
        now: controller.now,
      ),
      StandbyWidgetType.music => MusicCard(
        snapshot: controller.snapshots.nowPlaying,
        settings: settings,
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
      ),
    };
  }
}

const _dockPadding = EdgeInsets.fromLTRB(20, 4, 20, 24);

// A titled block of settings with a divider line above it, so Style, Presets,
// Colors, Options... read as separate sections.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
    this.first = false,
    this.nested = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool first; // no divider above the very first section
  final bool nested; // a sub-section inside another one: smaller heading

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first)
          Divider(
            height: nested ? 34 : 48,
            thickness: 1,
            color: Colors.white.withValues(alpha: nested ? 0.08 : 0.14),
          ),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: nested ? 15 : 19,
            color: nested ? Colors.white70 : Colors.white,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

// Settings for the clock panel only.
class _ClockSettings extends StatelessWidget {
  const _ClockSettings({
    required this.controller,
    required this.selected,
    required this.onAll,
    required this.onCity,
  });

  final StandbyController controller;
  final ValueNotifier<ClockPart?> selected;
  final VoidCallback onAll;
  final VoidCallback onCity;

  @override
  Widget build(BuildContext context) {
    // A plain scroll view + Column (not a lazy list) so every color row
    // exists to scroll to when a digit on the clock is tapped.
    return SingleChildScrollView(
      padding: _dockPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ClockBody(
            controller: controller,
            selected: selected,
            onCity: onCity,
          ),
          const Divider(height: 40, color: Colors.white12),
          TextButton(onPressed: onAll, child: const Text('All settings')),
        ],
      ),
    );
  }
}

/// Everything about the clock, in sections: Style, Presets, Clock colors,
/// (World clock), Options. Shared by the Clock panel and All settings, so both
/// offer exactly the same choices.
class _ClockBody extends StatefulWidget {
  const _ClockBody({
    required this.controller,
    required this.selected,
    required this.onCity,
    this.nested = false,
  });

  final StandbyController controller;
  final ValueNotifier<ClockPart?> selected;
  final VoidCallback onCity;
  final bool nested; // inside All settings: smaller section headings

  @override
  State<_ClockBody> createState() => _ClockBodyState();
}

class _ClockBodyState extends State<_ClockBody> {
  // one key per color row so a tap on the clock can scroll straight to it
  final _rowKeys = {for (final p in ClockPart.values) p: GlobalKey()};

  void _jump() {
    if (mounted) setState(() {}); // refresh the highlighted row
    final part = widget.selected.value;
    if (part == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKeys[part]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    widget.selected.addListener(_jump);
    _jump(); // opened by tapping a digit: start at its color
  }

  @override
  void dispose() {
    widget.selected.removeListener(_jump);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    void set(StandbySettings v) => widget.controller.updateSettings(v);
    final style = settings.clockStyle;
    final n = widget.nested;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'Style',
          first: true,
          nested: n,
          child: _StylePicker(settings: settings, onChanged: set),
        ),
        _Section(
          title: 'Presets',
          subtitle: 'Ready-made looks, shown on the style you picked',
          nested: n,
          child: _Presets(settings: settings, onChanged: set),
        ),
        _Section(
          title: 'Clock colors',
          subtitle:
              'Auto uses the preset\'s own color. Tip: tap the clock itself to jump to a color.',
          nested: n,
          child: _ClockColors(
            settings: settings,
            onChanged: set,
            rowKeys: _rowKeys,
            selected: widget.selected.value,
          ),
        ),
        if (style == ClockStyle.world)
          _Section(
            title: 'World clock',
            nested: n,
            child: _CityRow(settings: settings, onTap: widget.onCity),
          ),
        _Section(
          title: 'Options',
          nested: n,
          child: Column(
            children: [
              if (style.showsDigits)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.use24HourTime,
                  onChanged: (v) => set(settings.copyWith(use24HourTime: v)),
                  title: const Text('24-hour time'),
                ),
              // only styles that can show seconds (digits or a second hand)
              if (style.supportsSeconds)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.showSeconds,
                  onChanged: (v) => set(settings.copyWith(showSeconds: v)),
                  title: const Text('Show seconds'),
                ),
              _SliderRow(
                label: 'Size',
                value: settings.fontScale,
                min: 0.4,
                max: 1,
                onChanged: (v) => set(settings.copyWith(fontScale: v)),
              ),
              if (style == ClockStyle.frame)
                _SliderRow(
                  label: 'Tick size',
                  value: settings.tickScale,
                  min: 0.5,
                  max: 1.6,
                  onChanged: (v) => set(settings.copyWith(tickScale: v)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Row showing the chosen second city; opens the city search page.
class _CityRow extends StatelessWidget {
  const _CityRow({required this.settings, required this.onTap});

  final StandbySettings settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = settings.worldCity.isNotEmpty
        ? settings.worldCity
        : (settings.worldZone.isEmpty
              ? 'Not set'
              : zoneLabel(settings.worldZone));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'Second city',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(name),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Search any city in the world. The field stays pinned at the top so the
/// keyboard never hides what you type.
class _CityPage extends StatefulWidget {
  const _CityPage({required this.controller, required this.onDone});

  final StandbyController controller;
  final VoidCallback onDone;

  @override
  State<_CityPage> createState() => _CityPageState();
}

class _CityPageState extends State<_CityPage> {
  final _text = TextEditingController();
  Timer? _debounce;
  List<CityResult> _results = const [];
  bool _loading = false;
  bool _offline = false;
  bool _keyboard = true;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    List<CityResult> found;
    var offline = false;
    try {
      found = await searchCities(q);
    } catch (_) {
      // no internet: fall back to the built-in list of major cities
      offline = true;
      found = [
        for (final id in searchZones(q))
          CityResult(
            name: zoneLabel(id),
            region: id.split('/').first,
            timezone: id,
          ),
      ];
    }
    if (!mounted || _text.text != q) return;
    setState(() {
      _results = found;
      _offline = offline;
      _loading = false;
    });
  }

  void _type(String ch) {
    _text.text += ch;
    _changed(_text.text);
  }

  void _backspace() {
    if (_text.text.isEmpty) return;
    _text.text = _text.text.substring(0, _text.text.length - 1);
    _changed(_text.text);
  }

  void _pick(CityResult r) {
    final c = widget.controller;
    c.updateSettings(
      c.settings.copyWith(worldZone: r.timezone, worldCity: r.name),
    );
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          // readOnly: typing uses our own keyboard, never the system one
          TextField(
            controller: _text,
            readOnly: true,
            showCursor: true,
            enableInteractiveSelection: false,
            onTap: () => setState(() => _keyboard = true),
            decoration: InputDecoration(
              hintText: 'Search any city in the world',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_text.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _text.clear();
                              _changed('');
                            },
                          )),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_offline)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Offline: showing major cities only',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final r in _results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.name),
                    subtitle: Text(r.region),
                    onTap: () => _pick(r),
                  ),
                if (c.settings.worldZone.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      c.updateSettings(
                        c.settings.copyWith(worldZone: '', worldCity: ''),
                      );
                      widget.onDone();
                    },
                    child: const Text('Remove second city'),
                  ),
              ],
            ),
          ),
          if (_keyboard)
            SizedBox(
              height: (MediaQuery.sizeOf(context).height * 0.3).clamp(
                130.0,
                230.0,
              ),
              child: MiniKeyboard(
                onChar: _type,
                onBackspace: _backspace,
                onDone: () => setState(() => _keyboard = false),
              ),
            ),
        ],
      ),
    );
  }
}

/// Calendar settings: today's date or the whole month.
class _CalendarSettings extends StatelessWidget {
  const _CalendarSettings({required this.controller, required this.onAll});

  final StandbyController controller;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    return ListView(
      padding: _dockPadding,
      children: [
        _EnumPicker<CalendarStyle>(
          label: 'View',
          value: settings.calendarStyle,
          values: CalendarStyle.values,
          display: (v) => v == CalendarStyle.day ? 'Today' : 'Whole month',
          onChanged: (v) =>
              controller.updateSettings(settings.copyWith(calendarStyle: v)),
        ),
        const Text(
          'Tip: swipe up or down on the calendar to switch.',
          style: TextStyle(color: Colors.white54),
        ),
        TextButton(onPressed: onAll, child: const Text('All settings')),
      ],
    );
  }
}

/// Weather settings: unit, refresh, and a way to fix location permission.
class _WeatherSettings extends StatelessWidget {
  const _WeatherSettings({required this.controller, required this.onAll});

  final StandbyController controller;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final problem = controller.weatherProblem;
    return ListView(
      padding: _dockPadding,
      children: [
        const Text(
          'Weather uses this phone\'s location.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.fahrenheit,
          onChanged: (v) =>
              controller.updateSettings(settings.copyWith(fahrenheit: v)),
          title: const Text('Temperature in °F'),
        ),
        FilledButton(
          onPressed: controller.refreshWeather,
          child: const Text('Refresh weather'),
        ),
        if (problem == WeatherProblem.permission ||
            problem == WeatherProblem.locationOff) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: problem == WeatherProblem.permission
                ? Geolocator.openAppSettings
                : Geolocator.openLocationSettings,
            child: Text(
              problem == WeatherProblem.permission
                  ? 'Allow location in app settings'
                  : 'Turn on location',
            ),
          ),
        ],
        TextButton(onPressed: onAll, child: const Text('All settings')),
      ],
    );
  }
}

// Every setting, in sections. Changes show live on the panels beside/above.
class _AllSettings extends StatelessWidget {
  const _AllSettings({
    required this.controller,
    required this.onCity,
    required this.onMusic,
    required this.selected,
  });

  final StandbyController controller;
  final VoidCallback onCity;
  final VoidCallback onMusic; // opens the Music dock
  final ValueNotifier<ClockPart?> selected;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    void set(StandbySettings v) => controller.updateSettings(v);
    // a plain scroll view + Column so nothing is built lazily (see _ClockSettings)
    return SingleChildScrollView(
      padding: _dockPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            title: 'Layout',
            subtitle:
                'Tip: pinch with two fingers on the screen. Spread = one panel, pinch together = two.',
            first: true,
            child: Column(
              children: [
                _EnumPicker<StandbyLayoutMode>(
                  label: 'Panels',
                  value: settings.layoutMode,
                  values: StandbyLayoutMode.values,
                  display: (v) =>
                      v == StandbyLayoutMode.duo ? 'Two panels' : 'Single',
                  onChanged: (v) => set(settings.copyWith(layoutMode: v)),
                ),
                _EnumPicker<StandbyWidgetType>(
                  label: 'Left widget',
                  value: settings.leftWidget,
                  values: StandbyWidgetType.values,
                  display: _widgetLabel,
                  onChanged: (v) => set(settings.copyWith(leftWidget: v)),
                ),
                _EnumPicker<StandbyWidgetType>(
                  label: 'Right widget',
                  value: settings.rightWidget,
                  values: StandbyWidgetType.values,
                  display: _widgetLabel,
                  onChanged: (v) => set(settings.copyWith(rightWidget: v)),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Music',
            subtitle: 'Where the music comes from, and Spotify volume.',
            child: Column(
              children: [
                SpotifyVolume(controller: controller),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.library_music_outlined),
                  title: const Text('Music source & Spotify'),
                  subtitle: Text(
                    controller.spotifyConnected
                        ? 'Spotify connected'
                        : 'Spotify not connected',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onMusic,
                ),
              ],
            ),
          ),
          // iOS does not let an app open itself, so auto-start is Android only
          if (defaultTargetPlatform != TargetPlatform.iOS)
            _Section(
              title: 'Auto-start',
              subtitle:
                  'Open Dockwise by itself when the phone is charging and propped up.',
              child: _AutoStartSection(controller: controller),
            ),
          _Section(
            title: 'Theme',
            subtitle:
                'Accent color for the date card and highlights. The clock keeps its own colors under Clock.',
            child: _AccentPicker(settings: settings, onChanged: set),
          ),
          _Section(
            title: 'Clock',
            child: _ClockBody(
              controller: controller,
              selected: selected,
              onCity: onCity,
              nested: true,
            ),
          ),
          _Section(
            title: 'Weather',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.fahrenheit,
              onChanged: (v) => set(settings.copyWith(fahrenheit: v)),
              title: const Text('Temperature in °F'),
            ),
          ),
          _Section(
            title: 'Calendar',
            child: _EnumPicker<CalendarStyle>(
              label: 'View',
              value: settings.calendarStyle,
              values: CalendarStyle.values,
              display: (v) => v == CalendarStyle.day ? 'Today' : 'Whole month',
              onChanged: (v) => set(settings.copyWith(calendarStyle: v)),
            ),
          ),
          _Section(
            title: 'Display & battery',
            child: Column(
              children: [
                _SliderRow(
                  label: 'Dim',
                  value: settings.brightness,
                  min: 0.08,
                  max: 1,
                  onChanged: (v) => set(settings.copyWith(brightness: v)),
                ),
                _SliderRow(
                  label: 'Glow',
                  value: settings.glowIntensity,
                  min: 0,
                  max: 0.9,
                  onChanged: (v) => set(settings.copyWith(glowIntensity: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.nightModeEnabled,
                  onChanged: (v) => set(settings.copyWith(nightModeEnabled: v)),
                  title: const Text('Night mode'),
                  subtitle: const Text(
                    'Dims and warms the colors at night, no blue light',
                  ),
                ),
                if (settings.nightModeEnabled) ...[
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in const [
                        ('red', 'Red'),
                        ('amber', 'Amber'),
                        ('theme', 'Theme color'),
                      ])
                        ChoiceChip(
                          label: Text(t.$2),
                          selected: settings.nightTint == t.$1,
                          onSelected: (_) =>
                              set(settings.copyWith(nightTint: t.$1)),
                        ),
                    ],
                  ),
                  for (final w in [
                    ('From', settings.nightStartMin, true),
                    ('Until', settings.nightEndMin, false),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(w.$1),
                      trailing: Text(
                        TimeOfDay(
                          hour: w.$2 ~/ 60,
                          minute: w.$2 % 60,
                        ).format(context),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: w.$2 ~/ 60,
                            minute: w.$2 % 60,
                          ),
                        );
                        if (t == null) return;
                        final m = t.hour * 60 + t.minute;
                        set(
                          w.$3
                              ? settings.copyWith(nightStartMin: m)
                              : settings.copyWith(nightEndMin: m),
                        );
                      },
                    ),
                  _SliderRow(
                    label: 'Night strength',
                    value: settings.nightTintIntensity,
                    min: 0,
                    max: 1,
                    onChanged: (v) =>
                        set(settings.copyWith(nightTintIntensity: v)),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.burnInProtection,
                  onChanged: (v) => set(settings.copyWith(burnInProtection: v)),
                  title: const Text('OLED burn-in protection'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.lowBatteryAlert,
                  onChanged: (v) => set(settings.copyWith(lowBatteryAlert: v)),
                  title: const Text('Low battery prompt'),
                  subtitle: const Text(
                    'When low and not charging, ask to charge the phone before using Dockwise',
                  ),
                ),
                if (settings.lowBatteryAlert)
                  Row(
                    children: [
                      const SizedBox(
                        width: 92,
                        child: Text(
                          'Alert at',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: settings.lowBatteryLevel.toDouble().clamp(
                            5.0,
                            50.0,
                          ),
                          min: 5,
                          max: 50,
                          divisions: 9, // steps of 5%
                          label: '${settings.lowBatteryLevel}%',
                          onChanged: (v) => set(
                            settings.copyWith(lowBatteryLevel: v.round()),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${settings.lowBatteryLevel}%',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.keepAwakeWhileCharging,
                  onChanged: (v) =>
                      set(settings.copyWith(keepAwakeWhileCharging: v)),
                  title: const Text('Keep awake while charging'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Color pickers for the parts this clock style actually draws, each named
/// for what it colors ("Hour hand", "Minutes tile"...). "Auto" follows the
/// preset; white is included. The part tapped on the clock is highlighted.
class _ClockColors extends StatelessWidget {
  const _ClockColors({
    required this.settings,
    required this.onChanged,
    required this.rowKeys,
    required this.selected,
  });

  final StandbySettings settings;
  final ValueChanged<StandbySettings> onChanged;
  final Map<ClockPart, GlobalKey> rowKeys;
  final ClockPart? selected;

  static const _white = 0xFFFFFFFF;
  static const _blue = 0xFF0A84FF;

  int _value(ClockPart p) => switch (p) {
    ClockPart.hours => settings.hoursColor,
    ClockPart.colon => settings.colonColor,
    ClockPart.minutes => settings.minutesColor,
    ClockPart.detail => settings.detailColor,
    ClockPart.label => settings.labelColor,
  };

  StandbySettings _apply(ClockPart p, int c) => switch (p) {
    ClockPart.hours => settings.copyWith(hoursColor: c),
    ClockPart.colon => settings.copyWith(colonColor: c),
    ClockPart.minutes => settings.copyWith(minutesColor: c),
    ClockPart.detail => settings.copyWith(detailColor: c),
    ClockPart.label => settings.copyWith(labelColor: c),
  };

  Widget _row(ClockPart part) {
    final label = settings.clockStyle.partLabel(part);
    final value = _value(part);
    final active = selected == part;
    return KeyedSubtree(
      key: rowKeys[part],
      child: Container(
        key: ValueKey('row-${part.name}${active ? '-active' : ''}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? Colors.white.withValues(alpha: 0.07) : null,
          borderRadius: BorderRadius.circular(14),
          border: active
              ? Border.all(color: const Color(_blue), width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Auto'),
                  selected: value == 0,
                  onSelected: (_) => onChanged(_apply(part, 0)),
                ),
                for (final c in clockPalette)
                  Semantics(
                    button: true,
                    selected: value == c.argb,
                    label: '$label ${c.name}',
                    child: GestureDetector(
                      onTap: () => onChanged(_apply(part, c.argb)),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(c.argb),
                          border: Border.all(
                            // ring contrasts with the swatch (white gets blue)
                            color: value == c.argb
                                ? (c.argb == _white
                                      ? const Color(_blue)
                                      : Colors.white)
                                : Colors.white24,
                            width: value == c.argb ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Frame: the tick color comes first (it is the thing people look for)
    final all = settings.colorParts;
    final parts = settings.clockStyle == ClockStyle.frame
        ? [ClockPart.label, ...all.where((p) => p != ClockPart.label)]
        : all;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final p in parts) _row(p)],
    );
  }
}

/// Auto-start settings: the switch, the tilt it needs, a live tilt readout for
/// tuning, and a checklist of the Android permissions it depends on.
class _AutoStartSection extends StatefulWidget {
  const _AutoStartSection({required this.controller});

  final StandbyController controller;

  @override
  State<_AutoStartSection> createState() => _AutoStartSectionState();
}

class _AutoStartSectionState extends State<_AutoStartSection> {
  Timer? _poll;
  PostureNow? _now;
  AutoStartStatus? _status;
  int _ticks = 0;

  StandbyController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshStatus());
    unawaited(c.postureProbe(true)); // start reading the tilt sensor
    _poll = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      final now = await c.postureNow();
      // permissions rarely change: check every ~2 s (and when you come back
      // from the system settings screen)
      if (++_ticks % 3 == 0) await _refreshStatus();
      if (mounted) setState(() => _now = now);
    });
  }

  Future<void> _refreshStatus() async {
    final status = await c.autoStartStatus();
    if (mounted) setState(() => _status = status);
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(c.postureProbe(false)); // stop the sensor: no battery use
    super.dispose();
  }

  Widget _need(String title, String why, bool ok, Future<bool> Function() fix) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        ok ? Icons.check_circle : Icons.error_outline,
        color: ok ? const Color(0xFF30D158) : const Color(0xFFFF9F0A),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(why, style: const TextStyle(fontSize: 12)),
      trailing: ok
          ? null
          : FilledButton.tonal(
              onPressed: () async {
                await fix();
                await _refreshStatus();
              },
              child: const Text('Allow'),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = c.settings;
    void set(StandbySettings v) => c.updateSettings(v);
    final st = _status;
    final now = _now;
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.autoStart,
          onChanged: (v) => set(s.copyWith(autoStart: v)),
          title: const Text('Open when charging and propped up'),
        ),
        if (s.autoStart) ...[
          _SliderRow(
            label: 'Lean',
            value: s.autoLeanDeg.clamp(15, 80),
            min: 15,
            max: 80,
            onChanged: (v) => set(s.copyWith(autoLeanDeg: v.roundToDouble())),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Starts when the screen leans at least ${s.autoLeanDeg.round()}° up from lying flat.',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.autoLandscapeOnly,
            onChanged: (v) => set(s.copyWith(autoLandscapeOnly: v)),
            title: const Text('Landscape only'),
            subtitle: const Text('Turn on its side, like a bedside clock'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.autoExitOnUnplug,
            onChanged: (v) => set(s.copyWith(autoExitOnUnplug: v)),
            title: const Text('Close when unplugged'),
          ),
          // live tilt, so you can find the right angle by trying it
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  now?.matches == true
                      ? Icons.check_circle
                      : Icons.screen_rotation_alt_outlined,
                  color: now?.matches == true
                      ? const Color(0xFF30D158)
                      : Colors.white54,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    now == null
                        ? 'Reading the tilt sensor…'
                        : 'Now: leaning ${now.lean.round()}° · '
                              '${now.roll >= 45 ? 'landscape' : 'portrait'}\n'
                              '${now.matches ? 'This would start Dockwise (while charging)' : 'Not propped up enough yet'}',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Needed so it can open by itself',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          if (st != null) ...[
            _need(
              'Display over other apps',
              'Lets it open from the background. Without it you only get a notification to tap.',
              st.overlay,
              c.openOverlaySettings,
            ),
            _need(
              'Notifications',
              'For the tap-to-open fallback and the small "ready" notice.',
              st.notifications,
              c.requestNotifications,
            ),
            _need(
              'Battery: Unrestricted',
              'Stops the phone from putting the watcher to sleep (important on Realme).',
              st.battery,
              c.openBatterySettings,
            ),
          ],
        ],
      ],
    );
  }
}

/// App-wide accent: Apple red by default, any palette color, or "Match clock"
/// to copy the clock's current accent once. Changing the clock later does not
/// move it.
class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.settings, required this.onChanged});

  final StandbySettings settings;
  final ValueChanged<StandbySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = settings.appAccent;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Apple red'),
          selected: current == 0,
          onSelected: (_) => onChanged(settings.copyWith(appAccent: 0)),
        ),
        ActionChip(
          avatar: const Icon(Icons.link, size: 18),
          label: const Text('Match clock'),
          onPressed: () => onChanged(
            settings.copyWith(appAccent: settings.clockAccentInk.toARGB32()),
          ),
        ),
        for (final c in clockPalette)
          Semantics(
            button: true,
            selected: current == c.argb,
            label: 'Accent ${c.name}',
            child: GestureDetector(
              onTap: () => onChanged(settings.copyWith(appAccent: c.argb)),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(c.argb),
                  border: Border.all(
                    color: current == c.argb
                        ? (c.argb == 0xFFFFFFFF
                              ? const Color(0xFF0A84FF)
                              : Colors.white)
                        : Colors.white24,
                    width: current == c.argb ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A small, non-interactive render of the real clock face in [settings], so
/// every tile shows exactly what that choice looks like.
class _MiniClock extends StatelessWidget {
  const _MiniClock({required this.settings});

  final StandbySettings settings;

  static final _time = DateTime(2026, 1, 1, 10, 9, 30);

  @override
  Widget build(BuildContext context) {
    // static, full-size preview; World gets sample cities if none are set yet
    final preview = settings.copyWith(
      fontScale: 1,
      showSeconds: false,
      worldZone: settings.worldZone.isEmpty ? 'Asia/Tokyo' : settings.worldZone,
      worldCity: settings.worldZone.isEmpty ? 'Tokyo' : settings.worldCity,
    );
    return Container(
      width: 96,
      height: 66,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: preview.theme.panelColor ?? Colors.black,
        borderRadius: BorderRadius.circular(11),
      ),
      child: IgnorePointer(
        child: ClockFace(time: _time, settings: preview),
      ),
    );
  }
}

/// Name on top, preview below, a blue ring when selected.
class _PreviewTile extends StatelessWidget {
  const _PreviewTile({
    required this.name,
    required this.selected,
    required this.onTap,
    required this.settings,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;
  final StandbySettings settings;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 96,
          child: Column(
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? Colors.white : Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
              DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? const Color(0xFF0A84FF) : Colors.white24,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: _MiniClock(settings: settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every clock style, each drawn as it really looks with your current colors.
class _StylePicker extends StatelessWidget {
  const _StylePicker({required this.settings, required this.onChanged});

  final StandbySettings settings;
  final ValueChanged<StandbySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: [
        for (final style in ClockStyle.values)
          _PreviewTile(
            name: _clockLabel(style),
            selected: style == settings.clockStyle,
            settings: settings.copyWith(clockStyle: style),
            onTap: () => onChanged(settings.copyWith(clockStyle: style)),
          ),
      ],
    );
  }
}

/// Ready-made looks (Apple-style red & white first). Each sets the theme and
/// all clock-part colors at once, and previews on the style you have chosen.
class _Presets extends StatelessWidget {
  const _Presets({required this.settings, required this.onChanged});

  final StandbySettings settings;
  final ValueChanged<StandbySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: [
        for (final p in clockPresets)
          _PreviewTile(
            name: p.name,
            selected: p.matches(settings),
            settings: p.apply(settings),
            onTap: () => onChanged(p.apply(settings)),
          ),
      ],
    );
  }
}

class _EnumPicker<T> extends StatelessWidget {
  const _EnumPicker({
    required this.label,
    required this.value,
    required this.values,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) display;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in values)
                ChoiceChip(
                  label: Text(display(option)),
                  selected: option == value,
                  onSelected: (_) => onChanged(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

String _widgetLabel(StandbyWidgetType type) {
  return switch (type) {
    StandbyWidgetType.clock => 'Clock',
    StandbyWidgetType.weather => 'Weather',
    StandbyWidgetType.calendar => 'Calendar',
    StandbyWidgetType.music => 'Audio',
  };
}

String _clockLabel(ClockStyle style) {
  return switch (style) {
    ClockStyle.digital => 'Digital',
    ClockStyle.analog => 'Analog',
    ClockStyle.flip => 'Flip',
    ClockStyle.text => 'Text',
    ClockStyle.frame => 'Frame',
    ClockStyle.float => 'Float',
    ClockStyle.mono => 'Mono',
    ClockStyle.world => 'World',
  };
}
