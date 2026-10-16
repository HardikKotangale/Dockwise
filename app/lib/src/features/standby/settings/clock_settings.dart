import 'package:flutter/material.dart';

import '../../../core/apple.dart';
import '../../../core/palette.dart';
import '../../../domain/standby_models.dart';
import '../../../state/standby_controller.dart';
import '../widgets/clock_faces.dart';
import '../widgets/dock.dart';
import 'city_page.dart';
import 'controls.dart';
import 'simple_settings.dart' show ColorRow;

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
          AllSettingsButton(onPressed: onAll),
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
        duration: calm(context, Motion.fast),
        curve: easeOutStrong,
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
            child: CityRow(
              settings: settings,
              onTap: widget.onCity,
              onChanged: set,
            ),
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

  Widget _row(BuildContext context, ClockPart part) {
    final label = settings.clockStyle.partLabel(part);
    final value = _value(part);
    final active = selected == part;
    return KeyedSubtree(
      key: rowKeys[part],
      child: AnimatedContainer(
        duration: calm(context, Motion.fast),
        curve: easeOutStrong,
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
        child: ColorRow(
          label: label,
          value: value,
          focus: active,
          icon: switch (part) {
            ClockPart.hours => Icons.hourglass_top_rounded,
            ClockPart.minutes => Icons.timelapse_rounded,
            ClockPart.colon => Icons.more_vert_rounded,
            ClockPart.detail => Icons.text_fields_rounded,
            ClockPart.label => Icons.label_rounded,
          },
          onChanged: (c) => onChanged(_apply(part, c)),
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
      children: [for (final p in parts) _row(context, p)],
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
                duration: calm(context, Motion.fast),
                curve: easeOutStrong,
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
                  duration: calm(context, Motion.fast),
                  curve: easeOutStrong,
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

/// One option of a [LookPicker]: a name over a small picture of the result.
class LookTile extends StatelessWidget {
  const LookTile({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  /// drawn into a 96 x 66 frame
  final Widget preview;

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
                  duration: calm(context, Motion.fast),
                  curve: easeOutStrong,
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? Palette.blue : Colors.white24,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: Container(
                    width: 96,
                    height: 66,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    clipBehavior: Clip.antiAlias,
                    // a full-size picture scaled down, so nothing can overflow
                    child: MediaQuery(
                      // a picture, not text: it does not grow with the text size
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.noScaling),
                      child: IgnorePointer(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: 160,
                            height: 110,
                            child: preview,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A "Style" row for a card: every option drawn as it really looks, so you
/// can see what is next before you pick it.
class LookPicker<T> extends StatefulWidget {
  const LookPicker({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.name,
    required this.preview,
    required this.onChanged,
    this.id,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) name;
  final Widget Function(T) preview;
  final ValueChanged<T> onChanged;

  /// With an [id] (and a [label]) the picker is a dropdown: one line with the
  /// current choice, and the pictures only when you open it.
  final String? id;

  static final Set<String> _open = {};

  /// Opens the dropdown with this id the next time it is built.
  static void requestOpen(String id) => _open.add(id);

  @override
  State<LookPicker<T>> createState() => _LookPickerState<T>();
}

class _LookPickerState<T> extends State<LookPicker<T>> {
  late bool _isOpen = widget.id == null || LookPicker._open.contains(widget.id);

  Widget _tiles() => Wrap(
    spacing: 10,
    runSpacing: 12,
    children: [
      for (final v in widget.values)
        LookTile(
          name: widget.name(v),
          selected: v == widget.value,
          onTap: () => widget.onChanged(v),
          preview: widget.preview(v),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final drop = widget.id != null && widget.label.isNotEmpty;
    if (!drop) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        // full width, so it sits at the left like the rows around it
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.label.isNotEmpty) ...[
                Text(
                  widget.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
              ],
              _tiles(),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              tick();
              setState(() => _isOpen = !_isOpen);
              _isOpen
                  ? LookPicker._open.add(widget.id!)
                  : LookPicker._open.remove(widget.id!);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  // a small picture of the current choice, at the right
                  if (widget.values.contains(widget.value)) ...[
                    Container(
                      width: 48,
                      height: 33,
                      margin: const EdgeInsets.only(right: 10),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.noScaling),
                        child: IgnorePointer(
                          child: FittedBox(
                            child: SizedBox(
                              width: 160,
                              height: 110,
                              child: widget.preview(widget.value),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  Flexible(
                    child: Text(
                      widget.name(widget.value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _isOpen ? 0.5 : 0,
                    duration: calm(context, Motion.fast),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: calm(context, Motion.fast),
            curve: easeOutStrong,
            alignment: Alignment.topCenter,
            child: _isOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: _tiles(),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
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
