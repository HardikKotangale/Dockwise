import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../../core/palette.dart';
import '../../../domain/standby_models.dart';
import '../../../services/standby_system_service.dart';
import '../../../state/standby_controller.dart';
import '../widgets/dock.dart';
import '../widgets/music_sources_sheet.dart';
import 'clock_settings.dart';
import 'controls.dart';
import 'simple_settings.dart';

/// What the battery prompt calls the device, and when it speaks, by platform:
/// a phone on a dock waits for its charger; a laptop asks to be plugged in.
String get _lowBatteryTitle =>
    _windows ? 'Low battery warning' : 'Low battery prompt';

String get _lowBatteryText => _windows
    ? 'When the laptop is low and not plugged in, ask to plug it in. A desktop PC has no battery, so it never shows.'
    : 'When the phone is low and not charging, ask to put it on its charger before using Hushdock.';

bool get _windows => const {
  TargetPlatform.windows,
  TargetPlatform.macOS,
}.contains(defaultTargetPlatform);

/// One row of the key list: the keys (each drawn as a key; "or" and
/// "+ ..." are plain words between them) and what they do. A second line
/// (after \n) is a quiet hint.
typedef KeyShortcut = ({List<String> keys, String what});

/// The keys a PC understands (see StandbyScreen), in groups, as the ? / F1
/// help and Settings list them. Short words, one idea per line.
const keyboardShortcuts = <(String, List<KeyShortcut>)>[
  (
    'Cards',
    [
      (keys: ['←', '→'], what: 'Previous or next card'),
      (keys: ['↑', '↓'], what: 'Change the look of a card'),
      (
        keys: ['Q', 'W', 'E', 'R', 'A', '+ ↑ ↓'],
        what:
            'Swipe one tile on Summary\n'
            // no break inside a pair: "R weather" never splits across lines
            'Q\u00A0clock\u00A01 · W\u00A0clock\u00A02 · E\u00A0calendar · '
            'R\u00A0weather · A\u00A0timer',
      ),
      (keys: ['Shift', '+ ← →'], what: 'Use the second card'),
    ],
  ),
  (
    'Layout',
    [
      (
        keys: ['O'],
        what:
            'One card\n'
            'With two cards, the card under the pointer stays',
      ),
      (keys: ['T'], what: 'Two cards'),
      (
        keys: ['D'],
        what:
            'Switch between one and two\n'
            'With two cards, the card under the pointer stays',
      ),
    ],
  ),
  (
    'Music',
    [
      (keys: ['Space'], what: 'Play or pause'),
      (keys: ['N', 'M'], what: 'Back or forward 10 seconds'),
      (keys: [',', '.'], what: 'Previous or next song'),
      (keys: ['-', '+'], what: 'Volume down or up'),
    ],
  ),
  (
    'More',
    [
      (keys: ['B'], what: 'Night mode on or off'),
      (
        keys: ['S', 'or', 'Enter'],
        what:
            'Open or close the settings of what the pointer is on\n'
            'On Summary: hold Q W E R or A, then press S',
      ),
      (
        keys: ['0 – 9'],
        what: 'Type a time on the timer\nBackspace deletes. Enter is done.',
      ),
      (keys: ['F', 'or', 'F11'], what: 'Full screen on or off'),
      (keys: ['Esc'], what: 'Close, or leave full screen'),
      (keys: ['?', 'or', 'F1'], what: 'Show or hide this list'),
    ],
  ),
];

/// The [keyboardShortcuts], laid out like iOS settings: a small heading, then
/// one rounded card per group. Each row is a picture, a few words, and the
/// keys drawn as keys (under the words when there are many).
class ShortcutList extends StatelessWidget {
  const ShortcutList({super.key});

  static bool _plain(String token) => token == 'or' || token.startsWith('+');

  // a small picture of what the row does, by its first key
  static const _icons = <String, IconData>{
    '←': Icons.swap_horiz_rounded,
    '↑': Icons.style_rounded,
    'Q': Icons.touch_app_rounded,
    'D': Icons.cached_rounded,
    'Space': Icons.play_arrow_rounded,
    'N': Icons.forward_10_rounded,
    ',': Icons.skip_next_rounded,
    '-': Icons.volume_up_rounded,
    'B': Icons.nightlight_round,
    'S': Icons.settings_rounded,
    '0 – 9': Icons.dialpad_rounded,
    'F': Icons.fullscreen_rounded,
    'Esc': Icons.close_rounded,
    '?': Icons.help_outline_rounded,
  };

  Widget _keys(List<String> keys) => Wrap(
    spacing: 5,
    runSpacing: 5,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final k in keys)
        _plain(k)
            ? Text(k, style: const TextStyle(color: Colors.white54))
            : _KeyCap(k),
    ],
  );

  Widget _row(KeyShortcut row) {
    final lines = row.what.split('\n');
    // many keys go under the words, so the words keep their room
    final below = row.keys.length > 3;
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lines.first,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        if (lines.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              lines[1],
              style: const TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ),
        if (below)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _keys(row.keys),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: switch (row.keys.first) {
              // the layout rows are drawn as the cards they name
              'O' => const _CardsGlyph(cards: 1),
              'T' => const _CardsGlyph(cards: 2),
              'Shift' => const _CardsGlyph(cards: 2, lit: 1),
              _ => Icon(
                _icons[row.keys.first] ?? Icons.keyboard_rounded,
                size: 18,
                color: Colors.white70,
              ),
            },
          ),
          Expanded(child: words),
          if (!below) ...[const SizedBox(width: 10), _keys(row.keys)],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (group, rows) in keyboardShortcuts) ...[
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 16, bottom: 8),
          child: Text(
            group.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 56,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                _row(rows[i]),
              ],
            ],
          ),
        ),
      ],
    ],
  );
}

/// [cards] rounded boxes side by side, as many as the row speaks of, with one
/// of them lit when the row is about that one (the second card).
class _CardsGlyph extends StatelessWidget {
  const _CardsGlyph({required this.cards, this.lit});

  final int cards;
  final int? lit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 19,
        height: 15,
        child: Row(
          // stretch: a box with no child would otherwise have no height
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards; i++) ...[
              if (i > 0) const SizedBox(width: 2.5),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: lit == i ? Colors.white : null,
                    border: Border.all(color: Colors.white70, width: 1.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One key, drawn like a key on the keyboard.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 28),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    ),
  );
}

// Every setting, in sections. Changes show live on the panels beside/above.
class AllSettings extends StatelessWidget {
  const AllSettings({
    super.key,
    required this.controller,
    required this.onCity,
    required this.onMusic,
    required this.selected,
    this.focus,
  });

  final StandbyController controller;
  final VoidCallback onCity;
  final VoidCallback onMusic; // opens the Music dock
  final ValueNotifier<ClockPart?> selected;

  /// the title of a group to open and scroll to (a tap on a Summary clock)
  final String? focus;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    void set(StandbySettings v) => controller.updateSettings(v);
    // a plain scroll view + Column so nothing is built lazily (see ClockSettings)
    return SingleChildScrollView(
      padding: dockPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSection(
            title: 'Layout',
            subtitle:
                'Tip: pinch with two fingers on the screen. Spread = one panel, pinch together = two.',
            first: true,
            child: Column(
              children: [
                LookPicker<StandbyLayoutMode>(
                  label: 'Panels',
                  value: settings.layoutMode,
                  values: StandbyLayoutMode.values,
                  name: (v) =>
                      v == StandbyLayoutMode.duo ? 'Two panels' : 'Single',
                  preview: (v) => PanelsPreview(
                    two: v == StandbyLayoutMode.duo,
                    settings: settings,
                  ),
                  onChanged: (v) => set(settings.copyWith(layoutMode: v)),
                ),
                // One panel: there is only the one to choose; no left or right.
                if (settings.layoutMode == StandbyLayoutMode.single)
                  LookPicker<StandbyWidgetType>(
                    id: 'layout-widget',
                    label: 'Widget',
                    value: settings.leftWidget,
                    values: StandbyWidgetType.values,
                    name: widgetLabel,
                    preview: (t) => WidgetPreview(type: t, settings: settings),
                    onChanged: (v) => set(settings.copyWith(leftWidget: v)),
                  )
                else ...[
                  LookPicker<StandbyWidgetType>(
                    id: 'layout-left',
                    label: 'Left widget',
                    value: settings.leftWidget,
                    values: [
                      for (final t in StandbyWidgetType.values)
                        if (t != StandbyWidgetType.summary) t,
                    ],
                    name: widgetLabel,
                    preview: (t) => WidgetPreview(type: t, settings: settings),
                    onChanged: (v) => set(settings.copyWith(leftWidget: v)),
                  ),
                  LookPicker<StandbyWidgetType>(
                    id: 'layout-right',
                    label: 'Right widget',
                    value: settings.rightWidget,
                    values: [
                      for (final t in StandbyWidgetType.values)
                        if (t != StandbyWidgetType.summary) t,
                    ],
                    name: widgetLabel,
                    preview: (t) => WidgetPreview(type: t, settings: settings),
                    onChanged: (v) => set(settings.copyWith(rightWidget: v)),
                  ),
                ],
              ],
            ),
          ),
          SettingsSection(
            title: 'Music',
            subtitle: 'Where the music comes from, and Spotify volume.',
            child: Column(
              children: [
                SpotifyVolume(controller: controller),
                ColorRow(
                  label: 'Accent color',
                  autoLabel: 'White',
                  value: settings.musicColor,
                  onChanged: (c) => set(settings.copyWith(musicColor: c)),
                ),
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
          // iOS does not let an app open itself, and a PC is not a phone on a
          // charger: auto-start is Android only
          if (defaultTargetPlatform == TargetPlatform.android)
            SettingsSection(
              title: 'Auto-start',
              subtitle:
                  'Open Hushdock by itself when the phone is charging and propped up.',
              child: AutoStartSection(controller: controller),
            ),
          SettingsSection(
            title: 'Theme',
            subtitle:
                'Accent color for the date card and highlights. The clock keeps its own colors under Clock.',
            child: AccentPicker(settings: settings, onChanged: set),
          ),
          SettingsSection(
            title: 'Clock',
            child: ClockBody(
              controller: controller,
              selected: selected,
              onCity: onCity,
              nested: true,
            ),
          ),
          _FocusOnOpen(
            active: focus == 'Summary clocks',
            title: 'Summary clocks',
            child: SettingsSection(
              title: 'Summary clocks',
              subtitle: 'The two time tiles on the Summary panel.',
              child: SummaryClocksBody(
                settings: settings,
                onChanged: set,
                onCity: onCity,
              ),
            ),
          ),
          SettingsSection(
            title: 'Weather',
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: settings.fahrenheit,
              onChanged: (v) => set(settings.copyWith(fahrenheit: v)),
              title: const Text('Temperature in °F'),
            ),
          ),
          _FocusOnOpen(
            active: focus == 'Calendar',
            title: 'Calendar',
            child: SettingsSection(
              title: 'Calendar',
              child: CalendarBody(controller: controller),
            ),
          ),
          SettingsSection(
            title: 'Timer',
            subtitle:
                'Its own colors, separate from the clock, and what happens when it ends.',
            child: TimerBody(controller: controller),
          ),
          SettingsSection(
            title: 'Display & battery',
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.autoBrightness,
                  onChanged: (v) => set(settings.copyWith(autoBrightness: v)),
                  title: const Text('Auto brightness'),
                  subtitle: Text(
                    defaultTargetPlatform == TargetPlatform.iOS
                        ? "Follows the room light through iOS's own auto-brightness"
                        : 'Follows the room light: dimmer in a dark room, up to the level below',
                  ),
                ),
                SliderRow(
                  label: settings.autoBrightness ? 'Brightest' : 'Dim',
                  value: settings.brightness,
                  min: 0.08,
                  max: 1,
                  onChanged: (v) => set(settings.copyWith(brightness: v)),
                ),
                SliderRow(
                  label: 'Glow',
                  value: settings.glowIntensity,
                  min: 0,
                  max: 0.9,
                  onChanged: (v) => set(settings.copyWith(glowIntensity: v)),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.nightModeEnabled,
                  onChanged: (v) => set(settings.copyWith(nightModeEnabled: v)),
                  title: const Text('Night mode'),
                  subtitle: const Text(
                    'Dims and warms the colors at night, no blue light',
                  ),
                ),
                if (settings.nightModeEnabled) ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: settings.nightByLight,
                    onChanged: (v) => set(settings.copyWith(nightByLight: v)),
                    title: const Text('Also when the room is dark'),
                    subtitle: Text(
                      defaultTargetPlatform == TargetPlatform.iOS
                          ? 'Needs a room light sensor, which iPhone does not share with apps'
                          : 'Uses the light sensor, in addition to the hours below',
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in const [
                        ('red', 'Red'),
                        ('amber', 'Amber'),
                        ('theme', 'Accent color'),
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
                          fontWeight: FontWeight.w600,
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
                  SliderRow(
                    label: 'Night strength',
                    value: settings.nightTintIntensity,
                    min: 0,
                    max: 1,
                    onChanged: (v) =>
                        set(settings.copyWith(nightTintIntensity: v)),
                  ),
                ],
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.animations,
                  onChanged: (v) => set(settings.copyWith(animations: v)),
                  title: const Text('Animations'),
                  subtitle: const Text(
                    'Springs, slides, button motion and the moving weather. Turn off to save battery.',
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.burnInProtection,
                  onChanged: (v) => set(settings.copyWith(burnInProtection: v)),
                  title: const Text('OLED burn-in protection'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dim when idle'),
                  subtitle: const Text(
                    'Lowers the screen to about half after this long without a touch. Touch to wake.',
                  ),
                ),
                // one line: shrinks a little rather than wrapping
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final m in const [0, 2, 5, 10])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(m == 0 ? 'Off' : '$m min'),
                            selected: settings.idleDimMinutes == m,
                            onSelected: (_) =>
                                set(settings.copyWith(idleDimMinutes: m)),
                          ),
                        ),
                    ],
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.lowBatteryAlert,
                  onChanged: (v) => set(settings.copyWith(lowBatteryAlert: v)),
                  title: Text(_lowBatteryTitle),
                  subtitle: Text(_lowBatteryText),
                ),
                if (settings.lowBatteryAlert)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Warn me at',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final p in {
                              10,
                              15,
                              20,
                              30,
                              settings.lowBatteryLevel,
                            }.toList()..sort())
                              ChoiceChip(
                                label: Text('$p%'),
                                selected: settings.lowBatteryLevel == p,
                                onSelected: (_) =>
                                    set(settings.copyWith(lowBatteryLevel: p)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.keepAwakeWhileCharging,
                  onChanged: (v) =>
                      set(settings.copyWith(keepAwakeWhileCharging: v)),
                  // a PC has no charger to wait for: it stays awake while open
                  title: Text(
                    _windows
                        ? 'Keep the screen awake'
                        : 'Keep awake while charging',
                  ),
                ),
              ],
            ),
          ),
          if (_windows)
            SettingsSection(
              title: 'Window & keyboard',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: settings.fullscreen,
                    onChanged: (v) => set(settings.copyWith(fullscreen: v)),
                    title: const Text('Full screen'),
                    subtitle: const Text(
                      'Fills the whole screen. F or Esc to leave.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const ShortcutList(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Auto-start settings: the switch, the tilt it needs, a live tilt readout for
/// tuning, and a checklist of the Android permissions it depends on.
class AutoStartSection extends StatefulWidget {
  const AutoStartSection({super.key, required this.controller});

  final StandbyController controller;

  @override
  State<AutoStartSection> createState() => _AutoStartSectionState();
}

class _AutoStartSectionState extends State<AutoStartSection> {
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
        color: ok ? Palette.green : Palette.orange,
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
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: s.autoStart,
          onChanged: (v) => set(s.copyWith(autoStart: v)),
          title: const Text('Open when charging and propped up'),
        ),
        if (s.autoStart) ...[
          SliderRow(
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
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: s.autoLandscapeOnly,
            onChanged: (v) => set(s.copyWith(autoLandscapeOnly: v)),
            title: const Text('Landscape only'),
            subtitle: const Text('Turn on its side, like a bedside clock'),
          ),
          SwitchListTile.adaptive(
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
                  color: now?.matches == true ? Palette.green : Colors.white54,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    now == null
                        ? 'Reading the tilt sensor…'
                        : 'Now: leaning ${now.lean.round()}° · '
                              '${now.roll >= 45 ? 'landscape' : 'portrait'}\n'
                              '${now.matches ? 'This would start Hushdock (while charging)' : 'Not propped up enough yet'}',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Needed so it can open by itself',
            style: TextStyle(fontWeight: FontWeight.w600),
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

/// Opens a settings group and scrolls it into view the first time it is shown.
class _FocusOnOpen extends StatefulWidget {
  const _FocusOnOpen({
    required this.active,
    required this.title,
    required this.child,
  });

  final bool active;
  final String title;
  final Widget child;

  @override
  State<_FocusOnOpen> createState() => _FocusOnOpenState();
}

class _FocusOnOpenState extends State<_FocusOnOpen> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (!widget.active) return;
    SettingsSection.requestOpen(widget.title);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _key.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}
