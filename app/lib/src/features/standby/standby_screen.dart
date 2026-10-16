import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;

import '../../core/apple.dart';
import '../../core/burn_in_protection.dart';
import '../../core/key_capture.dart';
import '../../core/motion/aside_glide.dart';
import '../../core/night_mode_policy.dart';
import '../../core/power_mode.dart';
import '../../domain/standby_models.dart';
import '../../domain/summary_layout.dart';
import '../../services/calendar_service.dart';
import '../../services/photo_service.dart';
import '../../services/standby_system_service.dart';
import '../../state/standby_controller.dart';
import 'dashboard.dart';
import 'settings/all_settings.dart' show ShortcutList;
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
    this.calendarService,
    this.photoService,
  });

  final StandbySettings? initialSettings;
  final StandbySystemService? systemService;

  /// Battery source; tests pass a fake one.
  final BatteryMonitor? battery;

  /// Calendar source; tests pass a fake one.
  final CalendarService? calendarService;

  /// Photo source; tests pass a fake one.
  final PhotoService? photoService;

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
  bool _dockClosing = false; // the dock is on its way out
  final _dashboardKey = GlobalKey();
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
      calendarService: widget.calendarService,
      photoService: widget.photoService,
      autostartTicker: widget.initialSettings == null,
    );
    _controller.addListener(_flashDots);
    // after the first frame: load the clock fonts, so a swipe to Float or Frame
    // does not stall on the font the first time
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmClockFonts());
    _controller.addListener(_watchFullscreen);
    _controller.addListener(_followDock);
    if (widget.initialSettings == null) {
      _controller.initialize();
    } else {
      _controller.initializeForTest();
    }
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static void _warmClockFonts() {
    for (final family in const ['Fredoka', 'BebasNeue']) {
      for (final weight in const [
        FontWeight.w400,
        FontWeight.w600,
        FontWeight.w800,
      ]) {
        TextPainter(
            text: TextSpan(
              text: '0123456789:AMP',
              style: TextStyle(
                fontFamily: family,
                fontSize: 120,
                fontWeight: weight,
              ),
            ),
            textDirection: TextDirection.ltr,
          )
          ..layout()
          ..dispose();
      }
    }
  }

  static bool get _windows => const {
    TargetPlatform.windows,
    TargetPlatform.macOS,
  }.contains(defaultTargetPlatform);

  // Keyboard (a PC, or a phone with one): the same things a swipe or a tap
  // does. Typing in a text field always wins. (The city search is read-only:
  // it is fed by our own on-screen keyboard, so the keys stay ours there.)
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // a full-screen page on top (Spotify search, the setup guide) owns the
    // keys, Esc included: nothing here may act on the display underneath
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final field = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    final typing = field != null && !field.widget.readOnly;
    final keys = HardwareKeyboard.instance;
    if (typing ||
        keys.isControlPressed ||
        keys.isAltPressed ||
        keys.isMetaPressed) {
      return false;
    }
    final settings = _controller.settings;
    final dockOpen = _dockBuild != null;
    final key = event.logicalKey;
    // the timer's number pad is typing: only Esc (close) and F11 stay ours
    if (KeyCapture.active &&
        key != LogicalKeyboardKey.escape &&
        key != LogicalKeyboardKey.f11) {
      return false;
    }
    final handled = switch (key) {
      // F (or F11): full screen on or off
      LogicalKeyboardKey.keyF ||
      LogicalKeyboardKey.f11 when _windows => _do(_controller.toggleFullscreen),
      LogicalKeyboardKey.escape when dockOpen => _do(_dismissDock),
      LogicalKeyboardKey.escape when _windows && settings.fullscreen => _do(
        _controller.toggleFullscreen,
      ),
      LogicalKeyboardKey.keyS ||
      LogicalKeyboardKey.enter ||
      LogicalKeyboardKey.numpadEnter => _do(
        dockOpen ? _dismissDock : _openFirstPanel,
      ),
      LogicalKeyboardKey.keyB => _do(_controller.toggleNight),
      // ? (shift + /), or F1: the list of keys; again to close it
      LogicalKeyboardKey.question ||
      LogicalKeyboardKey.slash ||
      LogicalKeyboardKey.f1 => _do(_toggleHelp),
      // Space: the music or the timer that is shown; on any other card it
      // still plays or pauses the music (like N and M, and with Settings open)
      LogicalKeyboardKey.space => _do(() {
        if (!_controller.playPauseShown()) {
          _controller.keyMedia('playPause');
        }
      }),
      // the music, from any card: N back 10 s, M forward 10 s
      LogicalKeyboardKey.keyN => _do(() => _controller.keyMedia('back10')),
      LogicalKeyboardKey.keyM => _do(() => _controller.keyMedia('forward10')),
      LogicalKeyboardKey.period => _do(() => _controller.keyMedia('next')),
      LogicalKeyboardKey.comma => _do(() => _controller.keyMedia('previous')),
      LogicalKeyboardKey.minus ||
      LogicalKeyboardKey.underscore ||
      LogicalKeyboardKey.numpadSubtract => _do(() => _controller.keyVolume(-5)),
      LogicalKeyboardKey.equal ||
      LogicalKeyboardKey.add ||
      LogicalKeyboardKey.numpadAdd => _do(() => _controller.keyVolume(5)),
      // one or two panels (also with Settings or this list open: the cards
      // behind glide to the new layout)
      // O: one card; with two on screen, the one under the pointer stays
      LogicalKeyboardKey.keyO => _do(
        () => _controller.setLayout(
          StandbyLayoutMode.single,
          soloSecond: _touch.hoverLeft == false,
        ),
      ),
      LogicalKeyboardKey.keyT => _do(
        () => _controller.setLayout(StandbyLayoutMode.duo),
      ),
      LogicalKeyboardKey.keyD => _do(
        // two panels -> one: the panel under the pointer is the one kept
        () => _controller.setLayout(
          settings.layoutMode == StandbyLayoutMode.duo
              ? StandbyLayoutMode.single
              : StandbyLayoutMode.duo,
          soloSecond: _touch.hoverLeft == false,
        ),
      ),
      // the rest act on the cards, so not while the dock covers them
      // (two panels with the pointer over one: the arrows still work on it,
      // and the dock follows)
      _ when dockOpen && !(_arrow(key) && _touch.hoverLeft != null) => false,
      // with Shift, the arrows work the second (right or lower) card
      LogicalKeyboardKey.arrowLeft => _do(() => _step(Axis.horizontal, -1)),
      LogicalKeyboardKey.arrowRight => _do(() => _step(Axis.horizontal, 1)),
      LogicalKeyboardKey.arrowUp => _do(() => _step(Axis.vertical, 1)),
      LogicalKeyboardKey.arrowDown => _do(() => _step(Axis.vertical, -1)),
      // one or two panels, like the pinch
      _ => false,
    };
    if (handled) _controller.touched(); // a key wakes the dim screen too
    return handled;
  }

  static bool _arrow(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowRight ||
      k == LogicalKeyboardKey.arrowUp ||
      k == LogicalKeyboardKey.arrowDown;

  bool _do(VoidCallback action) {
    action();
    return true;
  }

  void _dismissDock() => _dockKey.currentState?.dismiss();

  static const _helpTitle = 'Keyboard shortcuts';

  void _toggleHelp() => _dockBuild != null && _dockTitle == _helpTitle
      ? _dismissDock()
      : _openDock(
          _helpTitle,
          () => const SingleChildScrollView(
            padding: dockPadding,
            child: ShortcutList(),
          ),
        );

  // S: the settings of what the pointer is on. On the Summary card, hold a
  // tile's key (Q W E R A) with S to open that tile's own settings; with the
  // pointer over a Summary tile, that tile's. Over a panel, that panel's. Else
  // the first panel's.
  void _openFirstPanel() {
    final tile = _summaryChord() ?? _touch.hoverTile;
    if (tile != null) {
      _touch.dockPanel = null;
      openSummaryTileSettings(
        controller: _controller,
        openDock: _openDock,
        clockPart: _clockPart,
        tile: tile,
      );
      return;
    }
    final s = _controller.settings;
    final left =
        _touch.hoverLeft != false || s.layoutMode != StandbyLayoutMode.duo;
    final type = left ? s.leftWidget : s.rightWidget;
    _touch.dockPanel = (isLeft: left, type: type);
    openPanelSettings(
      controller: _controller,
      openDock: _openDock,
      clockPart: _clockPart,
      type: type,
    );
  }

  static String _panelTitle(StandbyWidgetType t) => switch (t) {
    StandbyWidgetType.clock => 'Clock',
    StandbyWidgetType.music => 'Music',
    StandbyWidgetType.weather => 'Weather',
    StandbyWidgetType.calendar => 'Calendar',
    StandbyWidgetType.timer => 'Timer',
    StandbyWidgetType.photos => 'Photos',
    StandbyWidgetType.summary => 'Settings',
  };

  // The settings in the dock belong to a panel. Swipe that panel to another
  // card and the dock follows it, sliding the way the card went. A sub-page
  // (a city search, all settings, help) is left alone.
  bool _following = false;
  void _followDock() {
    final dp = _touch.dockPanel;
    if (dp == null || _dockBuild == null) return;
    final s = _controller.settings;
    final now = dp.isLeft
        ? s.leftWidget
        : (s.layoutMode == StandbyLayoutMode.duo ? s.rightWidget : null);
    if (now == null || now == dp.type) return;
    if (_dockTitle != _panelTitle(dp.type)) return;
    _touch.dockPanel = (isLeft: dp.isLeft, type: now);
    _following = true;
    openPanelSettings(
      controller: _controller,
      openDock: _openDock,
      clockPart: _clockPart,
      type: now,
      fromPart: true, // no automatic city search on the way
    );
    _following = false;
  }

  // The keys Q W E R A Z are the places on the Summary panel, in the order the
  // tiles are laid out (the left column from the top, then the next column...),
  // so after the tiles are rearranged each key follows the new arrangement.
  static const _chordKeys = [
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyE,
    LogicalKeyboardKey.keyR,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyZ,
  ];

  /// The place (0 = Q) whose key is held, when the Summary panel is on screen.
  int? _chordIndex() {
    final s = _controller.settings;
    final shown =
        s.leftWidget == StandbyWidgetType.summary ||
        (s.layoutMode == StandbyLayoutMode.duo &&
            s.rightWidget == StandbyWidgetType.summary);
    if (!shown) return null;
    final kb = HardwareKeyboard.instance;
    for (var i = 0; i < _chordKeys.length; i++) {
      if (kb.isLogicalKeyPressed(_chordKeys[i])) return i;
    }
    return null;
  }

  /// The tile in the held key's place; null when no key is held or that place
  /// is empty.
  SummaryTile? _summaryChord() {
    final i = _chordIndex();
    if (i == null) return null;
    final tiles = SummaryLayout.parse(_controller.settings.summaryLayout).tiles;
    return i < tiles.length ? tiles[i] : null;
  }

  // Arrows: on the first panel; with Shift (two panels) on the second one.
  // Up and down without Shift go to the clock if one is showing (they change
  // its style), else to the first panel.
  void _step(Axis axis, int step) {
    final s = _controller.settings;
    // Q, W, E, R, A or Z held: a swipe on the Summary tile in that place (Q the
    // first, W the one below it...), in the arrangement as it is now
    final place = _chordIndex();
    if (place != null && axis == Axis.vertical) {
      final tiles = SummaryLayout.parse(s.summaryLayout).tiles;
      if (place < tiles.length) {
        stepSummaryTile(_controller, tiles[place], step);
      } else {
        // nothing is in that place: say so instead of nothing
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('No card ${place + 1} in the Summary panel'),
              duration: const Duration(seconds: 2),
            ),
          );
      }
      return;
    }
    final duo = s.layoutMode == StandbyLayoutMode.duo;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    // with two panels, the panel under the pointer is the one the arrows work
    // on (Shift still means the second one)
    final hover = _touch.hoverLeft;
    final second =
        duo &&
        (shift ||
            hover == false ||
            (hover == null &&
                axis == Axis.vertical &&
                s.leftWidget != StandbyWidgetType.clock &&
                s.rightWidget == StandbyWidgetType.clock));
    stepPanel(
      controller: _controller,
      touch: _touch,
      axis: axis,
      step: step,
      type: second ? s.rightWidget : s.leftWidget,
      isLeft: !second,
    );
  }

  // Full screen on a PC: the pointer hides after a few still seconds
  bool _cursorHidden = false;
  Timer? _cursorTimer;

  // going full screen counts the still seconds from then, mouse moved or not
  bool _wasFullscreen = false;
  void _watchFullscreen() {
    final full = _controller.settings.fullscreen;
    if (full && !_wasFullscreen) _armCursor();
    _wasFullscreen = full;
  }

  void _pointerMoved(PointerEvent _) => _armCursor();

  void _armCursor() {
    _cursorTimer?.cancel();
    if (_cursorHidden) setState(() => _cursorHidden = false);
    if (!_windows || !_controller.settings.fullscreen) return;
    _cursorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.settings.fullscreen) {
        setState(() => _cursorHidden = true);
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _cursorTimer?.cancel();
    _dotsTimer?.cancel();
    _controller.removeListener(_flashDots);
    _controller.removeListener(_watchFullscreen);
    _controller.removeListener(_followDock);
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
    // a page opened by a tap does not slide the way the last swipe went
    if (!_following) _touch.swipeDir = Offset.zero;
    setState(() {
      _dockClosing = false;
      _dockFill = fill;
      _dockTitle = title;
      _dockBuild = build;
      _dockTall = tall;
    });
  }

  void _closeDock() {
    _clockPart.value = null;
    setState(() {
      _dockBuild = null;
      _dockClosing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final settings = _controller.settings;
        // a Mac's screen is not an OLED left on all night: no drifting gap
        final offset = defaultTargetPlatform == TargetPlatform.macOS
            ? OffsetSnapshot.zero
            : BurnInProtection.offsetForTick(_controller.burnInTick, settings);
        final scaffold = Scaffold(
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
                    // a Mac window has no notch: the display runs up under the
                    // (transparent) title bar instead of leaving a black band
                    top: defaultTargetPlatform != TargetPlatform.macOS,
                    minimum: const EdgeInsets.all(8),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        // Landscape: dock on the right; portrait: dock at the bottom.
                        final landscape = c.maxWidth >= 700;
                        // [_dashboardKey] keeps the dashboard (and so a Summary
                        // that is being edited) alive when the dock opens and the
                        // screen around it changes shape; without it everything
                        // under it was rebuilt from scratch.
                        final dashboard = KeyedSubtree(
                          key: _dashboardKey,
                          child: Stack(
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
                                  return _controller.nightNow
                                      ? ColorFiltered(
                                          colorFilter: NightModePolicy.filter(
                                            settings,
                                          ),
                                          child: moved,
                                        )
                                      : moved;
                                },
                                // the cards fill the screen; the page dots (one panel
                                // only) sit over the top edge of the card
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Positioned.fill(
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
                                          if (mode == settings.layoutMode) {
                                            return;
                                          }
                                          // zooming into a panel keeps that panel, not always the left one
                                          final size = MediaQuery.sizeOf(
                                            context,
                                          );
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
                                    if (settings.layoutMode ==
                                        StandbyLayoutMode.single)
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        right: 0,
                                        height: 30,
                                        child: PageDots(
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
                                              settings.copyWith(leftWidget: to),
                                            );
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                        final build = _dockBuild;
                        // the dashboard's room along the split (the dock takes
                        // the rest); AsideGlide keeps the cards from being laid
                        // out again on every frame as the dock moves
                        final total = landscape ? c.maxWidth : c.maxHeight;
                        Widget beside(double room, List<Widget> others) {
                          final kids = [
                            Expanded(
                              child: AsideGlide(
                                axis: landscape
                                    ? Axis.horizontal
                                    : Axis.vertical,
                                finalExtent: room,
                                child: dashboard,
                              ),
                            ),
                            ...others,
                          ];
                          return landscape
                              ? Row(children: kids)
                              : Column(children: kids);
                        }

                        if (build == null) return beside(total, const []);
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
                          onClosing: () => setState(() => _dockClosing = true),
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
                                // a new page (another card's settings) slides in the
                                // way the card was swiped, the old one slides out
                                child: AnimatedSwitcher(
                                  duration: calm(context, Motion.medium),
                                  switchInCurve: easeOutStrong,
                                  switchOutCurve: Curves.easeIn,
                                  layoutBuilder: (current, previous) => Stack(
                                    fit: StackFit.expand,
                                    children: [...previous, ?current],
                                  ),
                                  transitionBuilder: (child, animation) {
                                    final dir = _touch.swipeDir;
                                    final incoming =
                                        child.key == ValueKey(_dockTitle);
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween(
                                          begin: (incoming ? dir : -dir) * 0.12,
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: KeyedSubtree(
                                    key: ValueKey(_dockTitle),
                                    child: _DockBody(
                                      controller: _controller,
                                      build: build,
                                    ),
                                  ),
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
                        return beside(
                          _dockClosing ? total : total - (panelExtent + gap),
                          [dock],
                        );
                      },
                    ),
                  ),
                  // the level, in the room around the cards (never over them)
                  Positioned.fill(
                    child: Builder(
                      builder: (context) {
                        final pad = MediaQuery.paddingOf(context);
                        final beside = pad.top >= 30; // room next to the camera
                        final side = !beside && pad.right >= 30; // or beside it
                        // tucked into the corner, it would sit on an open dock
                        // that reaches the top (sideways or full height)
                        final size = MediaQuery.sizeOf(context);
                        final dockAtTop =
                            _dockBuild != null &&
                            (size.width > size.height ||
                                _dockTall ||
                                _dockFill);
                        if (!beside && !side && dockAtTop) {
                          return const SizedBox.shrink();
                        }
                        final line = BatteryLine(
                          monitor: _battery,
                          lowAt: settings.lowBatteryLevel,
                          column: side,
                        );
                        return Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: beside
                                // in the top margin, right of the camera
                                ? EdgeInsets.only(
                                    top: pad.top / 2 - 8,
                                    right: pad.right + 22,
                                  )
                                : side
                                // sideways: in the side margin
                                ? EdgeInsets.only(
                                    top: 28,
                                    right: math.max(pad.right / 2 - 14, 6),
                                  )
                                // no camera room at all: tucked into the
                                // top-right corner of the card (nothing sits
                                // there, and the card keeps its size)
                                : const EdgeInsets.only(top: 16, right: 34),
                            child: IgnorePointer(child: line),
                          ),
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
        return MouseRegion(
          // (leaving full screen brings it straight back)
          cursor: _cursorHidden && settings.fullscreen
              ? SystemMouseCursors.none
              : MouseCursor.defer,
          onHover: _pointerMoved,
          // a PC on mains power may spend a little more on looks
          child: ListenableBuilder(
            listenable: _battery,
            builder: (context, child) {
              final b = _battery.value;
              return RichGraphics(
                on: RichGraphics.allowed(
                  onBattery: b != null && !b.charging && !b.full,
                ),
                child: child!,
              );
            },
            child: scaffold,
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
