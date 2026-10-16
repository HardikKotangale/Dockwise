import 'package:flutter/material.dart';

import '../../../core/apple.dart';

import '../../../domain/standby_models.dart';

// A titled block of settings with a divider line above it, so Style, Presets,
// Colors, Options... read as separate sections.
/// A settings group that opens and closes, like a disclosure group in Apple's
/// own Settings: one quiet row with a chevron; the content slides open below.
/// The first group starts open, the rest closed, and each remembers what you
/// last chose (even after the settings are closed and opened again).
class SettingsSection extends StatefulWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.first = false,
    this.nested = false,
    this.scope = '',
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool first; // the very first section sits a little closer to the top
  /// names the card a nested section belongs to, so two cards can each have
  /// their own "Style" that opens and closes on its own
  final String scope;
  final bool nested; // a sub-section inside another one: lighter heading

  /// A small coloured badge per group (like Apple's Settings) so each one is
  /// found by its picture before it is read. By title.
  static const _badges = <String, (IconData, Color)>{
    'Layout': (Icons.dashboard_customize_rounded, Color(0xFF5E5CE6)),
    'Music': (Icons.music_note_rounded, Color(0xFFFF375F)),
    'Auto-start': (Icons.bolt_rounded, Color(0xFFFF9F0A)),
    'Theme': (Icons.palette_rounded, Color(0xFFBF5AF2)),
    'Clock': (Icons.schedule_rounded, Color(0xFF0A84FF)),
    'Weather': (Icons.cloud_rounded, Color(0xFF32ADE6)),
    'Calendar': (Icons.calendar_month_rounded, Color(0xFFFF453A)),
    'Timer': (Icons.timer_rounded, Color(0xFF30D158)),
    'Display & battery': (Icons.brightness_6_rounded, Color(0xFF5AC8FA)),
    'Window & keyboard': (Icons.keyboard_rounded, Color(0xFF8E8E93)),
    'Summary clocks': (Icons.watch_later_rounded, Color(0xFF64D2FF)),
    'Style': (Icons.text_fields_rounded, Color(0xFF0A84FF)),
    'Presets': (Icons.auto_awesome_rounded, Color(0xFFFFB800)),
    'Clock colors': (Icons.color_lens_rounded, Color(0xFFFF375F)),
    'World clock': (Icons.public_rounded, Color(0xFF32ADE6)),
    'Options': (Icons.tune_rounded, Color(0xFF8E8E93)),
    'Colors': (Icons.color_lens_rounded, Color(0xFFFF375F)),
  };

  /// which groups are open, by title; kept for the life of the app
  static final Map<String, bool> _open = {};

  /// Opens the group with this title the next time it is built (a tap on a
  /// Summary clock lands on its own group).
  static void requestOpen(String title) => _open[title] = true;

  /// the same for a part inside a group (a nested section of a card)
  static void requestOpenNested(String scope, String title) =>
      _open['n:$scope/$title'] = true;

  /// tests drive the controls inside every group, so they ask for all open
  static bool debugOpenAll = false;

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  String get _id =>
      widget.nested ? 'n:${widget.scope}/${widget.title}' : widget.title;
  late bool _isOpen =
      SettingsSection.debugOpenAll ||
      (SettingsSection._open[_id] ?? widget.first);

  void _toggle() {
    tick();
    setState(() => _isOpen = !_isOpen);
    SettingsSection._open[_id] = _isOpen;
  }

  @override
  Widget build(BuildContext context) {
    final nested = widget.nested;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final header = Semantics(
      button: true,
      expanded: _isOpen,
      label: widget.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(nested ? 10 : 18),
        splashFactory: NoSplash.splashFactory,
        onTap: _toggle,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            nested ? 2 : 16,
            12,
            nested ? 2 : 12,
            12,
          ),
          child: Row(
            children: [
              if (SettingsSection._badges[widget.title] case (
                final IconData icon,
                final Color color,
              )) ...[
                Container(
                  width: nested ? 24 : 30,
                  height: nested ? 24 : 30,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(nested ? 7 : 9),
                  ),
                  child: Icon(
                    icon,
                    size: nested ? 15 : 19,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: nested ? 10 : 12),
              ],
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: nested ? 15 : 17,
                    letterSpacing: -0.3,
                    color: nested ? Colors.white70 : Colors.white,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: _isOpen ? 0.25 : 0,
                duration: reduce ? Duration.zero : Motion.fast,
                curve: easeOutStrong,
                child: const Icon(
                  Icons.chevron_right_rounded,
                  size: 24,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final body = AnimatedSize(
      duration: reduce ? Duration.zero : Motion.medium,
      curve: easeOutStrong,
      alignment: Alignment.topCenter,
      child: _isOpen
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                nested ? 0 : 12,
                0,
                nested ? 0 : 12,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.subtitle != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                      child: Text(
                        widget.subtitle!,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  widget.child,
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
    return Padding(
      padding: EdgeInsets.only(top: widget.first ? 4 : (nested ? 6 : 12)),
      child: nested
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, body],
            )
          : Material(
              // Material (not a decorated box) so list tiles can paint ink inside
              color: Colors.white.withValues(alpha: _isOpen ? 0.07 : 0.05),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, body],
              ),
            ),
    );
  }
}

class EnumPicker<T> extends StatelessWidget {
  const EnumPicker({
    super.key,
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
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
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
      ),
    );
  }
}

class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
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

String widgetLabel(StandbyWidgetType type) {
  return switch (type) {
    StandbyWidgetType.clock => 'Clock',
    StandbyWidgetType.weather => 'Weather',
    StandbyWidgetType.calendar => 'Calendar',
    StandbyWidgetType.music => 'Music',
    StandbyWidgetType.summary => 'Summary',
    StandbyWidgetType.timer => 'Timer',
  };
}

String clockLabel(ClockStyle style) {
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

/// The icon for a panel type, shown beside its name in the page strip.
IconData widgetIcon(StandbyWidgetType type) => switch (type) {
  StandbyWidgetType.clock => Icons.schedule_rounded,
  StandbyWidgetType.weather => Icons.wb_sunny_rounded,
  StandbyWidgetType.calendar => Icons.calendar_today_rounded,
  StandbyWidgetType.music => Icons.music_note_rounded,
  StandbyWidgetType.summary => Icons.dashboard_rounded,
  StandbyWidgetType.timer => Icons.timer_rounded,
};

/// The way into All settings from a card's own settings. It is not a special
/// button: it is the same row as every group in All settings (a coloured
/// badge, the name, a chevron), because that is where it leads. What looks
/// the same behaves the same, so nobody has to learn it.
class AllSettingsButton extends StatelessWidget {
  const AllSettingsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // room above and below, so it never sits flush against the control before it
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Semantics(
        button: true,
        label: 'All settings',
        child: Pressable(
          scale: 0.98,
          child: Material(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              splashFactory: NoSplash.splashFactory,
              onTap: () {
                tick();
                onPressed();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8E8E93),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.settings_rounded,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'All settings',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 24,
                      color: Colors.white38,
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
}
