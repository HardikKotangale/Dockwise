import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/apple.dart';
import '../../core/burn_in_protection.dart';
import '../../core/night_mode_policy.dart';
import '../../domain/standby_models.dart';
import '../../services/standby_system_service.dart';
import '../../state/standby_controller.dart';
import 'dashboard.dart';
import 'settings/controls.dart';
import 'widgets/battery_badge.dart';
import 'widgets/dock.dart';
import 'widgets/idle_dim.dart';
import 'widgets/orientation_hint.dart';

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
  bool _dockFill =
      false; // the whole window, in either orientation (the timer's pad)
  bool _dockTall = false; // portrait: use the whole screen (e.g. city search)
  // Which clock part was tapped on screen; the Clock dock jumps to its color.
  final _clockPart = ValueNotifier<ClockPart?>(null);
  final _touch = PanelTouches();
  final _dockKey = GlobalKey<SpringDockState>();
  // the page dots show for a moment after the widget changes
  bool _dotsVisible = false;
  Timer? _dotsTimer;
  StandbyWidgetType? _dotsFor;

  void _flashDots() {
    final now = _controller.settings.leftWidget;
    if (_dotsFor == null) {
      _dotsFor = now; // first look: nothing changed yet
      return;
    }
    if (_dotsFor == now) return;
    _dotsFor = now;
    _dotsTimer?.cancel();
    setState(() => _dotsVisible = true);
    _dotsTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _dotsVisible = false);
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
    _controller.addListener(_flashDots);
    if (widget.initialSettings == null) {
      _controller.initialize();
    } else {
      _controller.initializeForTest();
    }
  }

  @override
  void dispose() {
    _dotsTimer?.cancel();
    _controller.removeListener(_flashDots);
    _clockPart.dispose();
    _controller.dispose();
    if (widget.battery == null) _battery.dispose();
    super.dispose();
  }

  void _openDock(
    String title,
    Widget Function() build, {
    bool tall = false,
    bool fill = false,
  }) {
    setState(() {
      _dockFill = fill;
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
          // any touch wakes the screen from its idle dim
          body: MediaQuery(
            // "Animations" off: every spring, slide and moving backdrop stops
            data: MediaQuery.of(context).copyWith(
              disableAnimations:
                  MediaQuery.disableAnimationsOf(context) ||
                  !settings.animations,
            ),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _controller.touched(),
              child: Stack(
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
                                      dark: _controller.roomDark,
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
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // page dots (one panel only): tap or
                                        // slide across them to change page
                                        if (settings.layoutMode ==
                                            StandbyLayoutMode.single)
                                          PageDots(
                                            labels: [
                                              for (final t
                                                  in StandbyWidgetType.values)
                                                widgetLabel(t),
                                            ],
                                            icons: [
                                              for (final t
                                                  in StandbyWidgetType.values)
                                                widgetIcon(t),
                                            ],
                                            index: settings.leftWidget.index,
                                            bright: _dotsVisible,
                                            onSelect: (i) {
                                              final to =
                                                  StandbyWidgetType.values[i];
                                              if (to == settings.leftWidget) {
                                                return;
                                              }
                                              _touch.swipeDir = Offset(
                                                i > settings.leftWidget.index
                                                    ? 1
                                                    : -1,
                                                0,
                                              );
                                              _controller.updateSettings(
                                                settings.copyWith(
                                                  leftWidget: to,
                                                ),
                                              );
                                            },
                                          ),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: BatteryBadge(
                                              monitor: _battery,
                                              lowAt: settings.lowBatteryLevel,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Dashboard(
                                      controller: _controller,
                                      settings: settings,
                                      stacked: !landscape,
                                      openDock: _openDock,
                                      clockPart: _clockPart,
                                      touch: _touch,
                                      closeDock: () =>
                                          _dockKey.currentState?.dismiss(),
                                      onPinch: (mode, center) {
                                        if (mode == settings.layoutMode) return;
                                        // zooming into a panel keeps that panel, not always the left one
                                        final size = MediaQuery.sizeOf(context);
                                        final onSecond = landscape
                                            ? center.dx > size.width / 2
                                            : center.dy > size.height / 2;
                                        tick();
                                        _controller.setLayout(
                                          mode,
                                          soloSecond: onSecond,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                        final build = _dockBuild;
                        if (build == null) return dashboard;
                        final typing =
                            MediaQuery.viewInsetsOf(context).bottom > 0;
                        // Keyboard up in portrait: give the dock all the visible space so
                        // what you type is never hidden behind it.
                        // [_dockFill] (the timer's number pad) covers the whole window in
                        // landscape too
                        final full =
                            _dockFill || (typing || _dockTall) && !landscape;
                        final gap = full ? 0.0 : 12.0;
                        final panelExtent = full
                            ? c.maxHeight
                            : landscape
                            ? (c.maxWidth * 0.42).clamp(320.0, 460.0)
                            : c.maxHeight * 0.46;
                        // a window-sized dock rises from the bottom and goes back
                        // down, like a sheet, in either orientation
                        final sideways = landscape && !full;
                        final dock = SpringDock(
                          key: _dockKey,
                          axis: sideways ? Axis.horizontal : Axis.vertical,
                          extent: panelExtent + gap,
                          overlay: full,
                          onClosed: _closeDock,
                          builder: (context, handle) => SpringDockScope(
                            handle: handle,
                            child: Padding(
                              padding: sideways
                                  ? EdgeInsets.only(left: gap)
                                  : EdgeInsets.only(top: gap),
                              child: Dock(
                                title: _dockTitle,
                                handle: handle,
                                horizontal: sideways,
                                solid: full,
                                child: _DockBody(
                                  controller: _controller,
                                  build: build,
                                ),
                              ),
                            ),
                          ),
                        );
                        // a window-sized dock slides over the dashboard (which
                        // stays under it) like a sheet
                        if (full) {
                          return Stack(
                            children: [
                              dashboard,
                              Positioned.fill(child: dock),
                            ],
                          );
                        }
                        return landscape
                            ? Row(
                                children: [
                                  Expanded(child: dashboard),
                                  dock,
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: dashboard),
                                  dock,
                                ],
                              );
                      },
                    ),
                  ),
                  // OLED care: half brightness while nobody touches the screen
                  Positioned.fill(child: IdleDim(idle: _controller.idle)),
                  // small rotate symbol at the bottom when the screen is not turned
                  // the way the phone is held (e.g. rotation lock on)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 4,
                    child: Center(child: OrientationHint(auto: true)),
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
            ),
          ),
        );
      },
    );
  }
}

/// The panel in the dock. It rebuilds when something changes, not on every
/// clock tick or song-position update: the settings are a long list of widgets
/// and rebuilding them each second made opening and scrolling them stutter.
class _DockBody extends StatefulWidget {
  const _DockBody({required this.controller, required this.build});

  final StandbyController controller;
  final Widget Function() build;

  @override
  State<_DockBody> createState() => _DockBodyState();
}

class _DockBodyState extends State<_DockBody> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!widget.controller.backgroundNotify) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.build();
}
