import 'package:flutter/material.dart';
import '../../../domain/standby_models.dart';

// A titled block of settings with a divider line above it, so Style, Presets,
// Colors, Options... read as separate sections.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.first = false,
    this.nested = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool first; // the very first section sits a little closer to the top
  final bool nested; // a sub-section inside another one: lighter heading

  @override
  Widget build(BuildContext context) {
    // Like iOS Settings: a small heading, then the content in a rounded,
    // slightly lighter group. Sub-sections stay inside their parent group.
    final heading = Padding(
      padding: EdgeInsets.fromLTRB(nested ? 0 : 6, 0, 0, 6),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: nested ? 15 : 14,
          letterSpacing: -0.15,
          color: nested ? Colors.white70 : Colors.white54,
        ),
      ),
    );
    final note = subtitle == null
        ? null
        : Padding(
            padding: EdgeInsets.fromLTRB(nested ? 0 : 6, 0, 0, 8),
            child: Text(
              subtitle!,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          );
    return Padding(
      padding: EdgeInsets.only(top: first ? 4 : (nested ? 18 : 28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          ?note,
          if (nested)
            child
          else
            // Material (not a decorated box) so list tiles can paint ink inside.
            Material(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: child,
              ),
            ),
        ],
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
