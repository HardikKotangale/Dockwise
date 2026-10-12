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

// Every setting, in sections. Changes show live on the panels beside/above.
class AllSettings extends StatelessWidget {
  const AllSettings({
    super.key,
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
                EnumPicker<StandbyLayoutMode>(
                  label: 'Panels',
                  value: settings.layoutMode,
                  values: StandbyLayoutMode.values,
                  display: (v) =>
                      v == StandbyLayoutMode.duo ? 'Two panels' : 'Single',
                  onChanged: (v) => set(settings.copyWith(layoutMode: v)),
                ),
                // One panel: there is only the one to choose; no left or right.
                if (settings.layoutMode == StandbyLayoutMode.single)
                  EnumPicker<StandbyWidgetType>(
                    label: 'Widget',
                    value: settings.leftWidget,
                    values: StandbyWidgetType.values,
                    display: widgetLabel,
                    onChanged: (v) => set(settings.copyWith(leftWidget: v)),
                  )
                else ...[
                  EnumPicker<StandbyWidgetType>(
                    label: 'Left widget',
                    value: settings.leftWidget,
                    values: [
                      for (final t in StandbyWidgetType.values)
                        if (t != StandbyWidgetType.summary) t,
                    ],
                    display: widgetLabel,
                    onChanged: (v) => set(settings.copyWith(leftWidget: v)),
                  ),
                  EnumPicker<StandbyWidgetType>(
                    label: 'Right widget',
                    value: settings.rightWidget,
                    values: [
                      for (final t in StandbyWidgetType.values)
                        if (t != StandbyWidgetType.summary) t,
                    ],
                    display: widgetLabel,
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
            SettingsSection(
              title: 'Auto-start',
              subtitle:
                  'Open Dockwise by itself when the phone is charging and propped up.',
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
          SettingsSection(
            title: 'Weather',
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: settings.fahrenheit,
              onChanged: (v) => set(settings.copyWith(fahrenheit: v)),
              title: const Text('Temperature in °F'),
            ),
          ),
          SettingsSection(
            title: 'Calendar',
            child: EnumPicker<CalendarStyle>(
              label: 'View',
              value: settings.calendarStyle,
              values: CalendarStyle.values,
              display: (v) => v == CalendarStyle.day ? 'Today' : 'Whole month',
              onChanged: (v) => set(settings.copyWith(calendarStyle: v)),
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
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in const [0, 2, 5, 10])
                      ChoiceChip(
                        label: Text(m == 0 ? 'Off' : '$m min'),
                        selected: settings.idleDimMinutes == m,
                        onSelected: (_) =>
                            set(settings.copyWith(idleDimMinutes: m)),
                      ),
                  ],
                ),
                SwitchListTile.adaptive(
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
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                SwitchListTile.adaptive(
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
