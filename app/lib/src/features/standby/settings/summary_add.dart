import 'package:flutter/material.dart';

import '../../../core/apple.dart';
import '../../../core/palette.dart';
import '../../../domain/summary_layout.dart';
import '../../../state/standby_controller.dart';
import '../widgets/dock.dart';

/// "Add a widget" for the Summary panel: the widgets that are not on it yet,
/// as big, easy cards. Tap one and it is added (and the window closes).
class SummaryAdd extends StatelessWidget {
  const SummaryAdd({super.key, required this.controller, required this.onDone});

  final StandbyController controller;
  final VoidCallback onDone;

  static (String, String, IconData) describe(SummaryTile t) => switch (t) {
    SummaryTile.here => (
      'Time here',
      'The time where you are, big.',
      Icons.schedule_rounded,
    ),
    SummaryTile.there => (
      'Second city',
      'The time in another city. Tap it to choose one.',
      Icons.public_rounded,
    ),
    SummaryTile.date => (
      'Date',
      'The day of the week and the date.',
      Icons.calendar_today_rounded,
    ),
    SummaryTile.weather => (
      'Weather',
      'Now, the forecast and a second city. Swipe up or down.',
      Icons.wb_sunny_rounded,
    ),
    SummaryTile.timer => (
      'Timer',
      'A countdown with a running horse or player, and its buttons.',
      Icons.timer_rounded,
    ),
    SummaryTile.music => (
      'Music',
      'What is playing, with all of its controls.',
      Icons.music_note_rounded,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final layout = SummaryLayout.parse(controller.settings.summaryLayout);
    final missing = layout.missing;
    return ListView(
      padding: dockPadding,
      children: [
        if (missing.isEmpty)
          const Text(
            'Everything is already on the panel.',
            style: TextStyle(color: Colors.white70),
          ),
        for (final t in missing)
          Builder(
            builder: (context) {
              final next = layout.added(t);
              final (name, text, icon) = describe(t);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  button: true,
                  enabled: next != null,
                  label: next == null
                      ? '$name. No room: remove a widget first'
                      : 'Add $name',
                  child: Pressable(
                    scale: 0.97,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: next == null
                          ? null
                          : () {
                              tick();
                              controller.updateSettings(
                                controller.settings.copyWith(
                                  summaryLayout: next.encode(),
                                ),
                              );
                              onDone();
                            },
                      child: AnimatedOpacity(
                        duration: calm(context, Motion.fast),
                        opacity: next == null ? 0.4 : 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(icon, size: 30),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        text,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.white60,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.add_circle_rounded,
                                  color: Palette.green,
                                  size: 28,
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
            },
          ),
        if (missing.isNotEmpty && missing.every((t) => layout.added(t) == null))
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'The panel is full: remove a widget (the - on a tile) to make room.',
              style: TextStyle(color: Colors.white54),
            ),
          ),
      ],
    );
  }
}
