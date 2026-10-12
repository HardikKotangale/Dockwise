import 'package:flutter/material.dart';

import '../../../core/apple.dart';
import '../../../core/palette.dart';
import '../../../domain/standby_models.dart';
import '../../../state/standby_controller.dart';
import '../widgets/clock_faces.dart';
import '../widgets/dock.dart';
import 'city_page.dart';
import 'controls.dart';

// Settings for the clock panel only.
class ClockSettings extends StatelessWidget {
  const ClockSettings({
    super.key,
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
      padding: dockPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClockBody(controller: controller, selected: selected, onCity: onCity),
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
class ClockBody extends StatefulWidget {
  const ClockBody({
    super.key,
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
  State<ClockBody> createState() => _ClockBodyState();
}

class _ClockBodyState extends State<ClockBody> {
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
        SettingsSection(
          title: 'Style',
          first: true,
          nested: n,
          child: StylePicker(settings: settings, onChanged: set),
        ),
        SettingsSection(
          title: 'Presets',
          subtitle: 'Ready-made looks, shown on the style you picked',
          nested: n,
          child: Presets(settings: settings, onChanged: set),
        ),
        SettingsSection(
          title: 'Clock colors',
          subtitle:
              'Auto uses the preset\'s own color. Tip: tap the clock itself to jump to a color.',
          nested: n,
          child: ClockColors(
            settings: settings,
            onChanged: set,
            rowKeys: _rowKeys,
            selected: widget.selected.value,
          ),
        ),
        if (style == ClockStyle.world)
          SettingsSection(
            title: 'World clock',
            nested: n,
            child: CityRow(settings: settings, onTap: widget.onCity),
          ),
        SettingsSection(
          title: 'Options',
          nested: n,
          child: Column(
            children: [
              if (style.showsDigits)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.use24HourTime,
                  onChanged: (v) => set(settings.copyWith(use24HourTime: v)),
                  title: const Text('24-hour time'),
                ),
              // only styles that can show seconds (digits or a second hand)
              if (style.supportsSeconds)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: settings.showSeconds,
                  onChanged: (v) => set(settings.copyWith(showSeconds: v)),
                  title: const Text('Show seconds'),
                ),
              SliderRow(
                label: 'Size',
                value: settings.fontScale,
                min: 0.4,
                max: 1,
                onChanged: (v) => set(settings.copyWith(fontScale: v)),
              ),
              if (style == ClockStyle.frame)
                SliderRow(
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

/// Color pickers for the parts this clock style actually draws, each named
/// for what it colors ("Hour hand", "Minutes tile"...). "Auto" follows the
/// preset; white is included. The part tapped on the clock is highlighted.
class ClockColors extends StatelessWidget {
  const ClockColors({
    super.key,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
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
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
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

/// App-wide accent: Apple red by default, any palette color, or "Match clock"
/// to copy the clock's current accent once. Changing the clock later does not
/// move it.
class AccentPicker extends StatelessWidget {
  const AccentPicker({
    super.key,
    required this.settings,
    required this.onChanged,
  });

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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(c.argb),
                  border: Border.all(
                    color: current == c.argb
                        ? (c.argb == 0xFFFFFFFF ? Palette.blue : Colors.white)
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
class MiniClock extends StatelessWidget {
  const MiniClock({super.key, required this.settings});

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
class PreviewTile extends StatelessWidget {
  const PreviewTile({
    super.key,
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
      child: Pressable(
        scale: 0.94,
        child: GestureDetector(
          onTap: () {
            tick();
            onTap();
          },
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
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? Colors.white : Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? Palette.blue : Colors.white24,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: MiniClock(settings: settings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every clock style, each drawn as it really looks with your current colors.
class StylePicker extends StatelessWidget {
  const StylePicker({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final StandbySettings settings;
  final ValueChanged<StandbySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: [
        for (final style in ClockStyle.values)
          PreviewTile(
            name: clockLabel(style),
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
class Presets extends StatelessWidget {
  const Presets({super.key, required this.settings, required this.onChanged});

  final StandbySettings settings;
  final ValueChanged<StandbySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: [
        for (final p in clockPresets)
          PreviewTile(
            name: p.name,
            selected: p.matches(settings),
            settings: p.apply(settings),
            onTap: () => onChanged(p.apply(settings)),
          ),
      ],
    );
  }
}
