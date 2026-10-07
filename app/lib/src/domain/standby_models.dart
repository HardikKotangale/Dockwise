import 'dart:typed_data';
import 'package:flutter/material.dart';

enum StandbyLayoutMode { duo, single }

// Apple StandBy styles (digital, analog, world, float, mono) plus flip, text
// and frame (the time in a square whose border counts the seconds).
enum ClockStyle { digital, analog, float, mono, frame, flip, text, world }

enum CalendarStyle { day, month }

/// The separately colorable parts of a clock face.
enum ClockPart { hours, colon, minutes, detail, label }

/// What each clock style actually shows, so settings only offer what applies.
extension ClockStyleInfo on ClockStyle {
  /// Styles that can display seconds (digits, or a second hand).
  bool get supportsSeconds =>
      this == ClockStyle.digital ||
      this == ClockStyle.mono ||
      this == ClockStyle.analog ||
      this == ClockStyle.flip; // a third tile

  /// Styles that print a time in digits/words (so 12/24-hour matters).
  bool get showsDigits => this != ClockStyle.analog;

  /// Colorable parts this style draws.
  List<ClockPart> get parts => switch (this) {
    ClockStyle.digital ||
    ClockStyle.mono ||
    ClockStyle.flip ||
    ClockStyle.analog => const [
      ClockPart.hours,
      ClockPart.colon,
      ClockPart.minutes,
      ClockPart.detail,
    ],
    // + the city names (world) / the seconds ticks (frame)
    ClockStyle.world || ClockStyle.frame => ClockPart.values,
    ClockStyle.text || ClockStyle.float => const [
      ClockPart.hours,
      ClockPart.minutes,
      ClockPart.detail,
    ],
  };

  /// Human name of [part] in this style, e.g. "Hour hand" on the analog clock.
  String partLabel(ClockPart part) => switch (this) {
    ClockStyle.analog => switch (part) {
      ClockPart.hours => 'Hour hand',
      ClockPart.minutes => 'Minute hand',
      ClockPart.colon => 'Dial marks',
      ClockPart.detail => 'Second hand',
      ClockPart.label => 'Labels',
    },
    ClockStyle.text => switch (part) {
      ClockPart.hours => 'Hour word',
      ClockPart.minutes => 'Minute word',
      ClockPart.label => 'Labels',
      _ => 'AM/PM',
    },
    ClockStyle.float => switch (part) {
      ClockPart.hours => 'Top row (hours)',
      ClockPart.minutes => 'Bottom row (minutes)',
      ClockPart.label => 'Labels',
      _ => 'AM/PM',
    },
    ClockStyle.flip => switch (part) {
      ClockPart.hours => 'Hours tile',
      ClockPart.minutes => 'Minutes tile',
      ClockPart.colon => 'Colon dots',
      ClockPart.detail => 'AM/PM & seconds',
      ClockPart.label => 'Labels',
    },
    ClockStyle.frame => switch (part) {
      ClockPart.hours => 'Hours',
      ClockPart.colon => 'Colon',
      ClockPart.minutes => 'Minutes',
      ClockPart.detail => 'AM/PM',
      ClockPart.label => 'Tick color',
    },
    ClockStyle.world => switch (part) {
      ClockPart.hours => 'Hours',
      ClockPart.minutes => 'Minutes',
      ClockPart.colon => 'Colon',
      ClockPart.detail => 'AM/PM',
      ClockPart.label => 'City names',
    },
    _ => switch (part) {
      ClockPart.hours => 'Hours',
      ClockPart.minutes => 'Minutes',
      ClockPart.colon => 'Colon',
      ClockPart.detail => 'AM/PM & seconds',
      ClockPart.label => 'Labels',
    },
  };
}

enum StandbyWidgetType { clock, weather, calendar, music }

T _enumFromName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.name,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.secondary,
    required this.glow,
    required this.weight,
    this.panel,
    this.ink,
  });

  /// Color-block themes fill the clock panel with [panel] and draw digits in [ink].
  final int? panel;
  final int? ink;
  final String id;
  final String name;
  final int background;
  final int foreground;
  final int accent;
  final int secondary;
  final double glow;
  final int weight;

  Color get backgroundColor => Color(background);
  Color get foregroundColor => Color(foreground);
  Color get accentColor => Color(accent);
  Color get secondaryColor => Color(secondary);
  Color? get panelColor => panel == null ? null : Color(panel!);
  Color get clockColor => Color(ink ?? foreground);
  Color get clockAccent => Color(ink ?? accent);
  Color get clockSecondary =>
      panel == null ? Color(secondary) : clockColor.withValues(alpha: 0.6);
}

/// Colors offered for each part of the clock (white first).
const clockPalette = <({String name, int argb})>[
  (name: 'White', argb: 0xFFFFFFFF),
  (name: 'Silver', argb: 0xFFC7C7CC),
  (name: 'Red', argb: 0xFFFF453A),
  (name: 'Orange', argb: 0xFFFF9F0A),
  (name: 'Yellow', argb: 0xFFFFD60A),
  (name: 'Green', argb: 0xFF30D158),
  (name: 'Mint', argb: 0xFF63E6BE),
  (name: 'Cyan', argb: 0xFF64D2FF),
  (name: 'Blue', argb: 0xFF0A84FF),
  (name: 'Purple', argb: 0xFFBF5AF2),
  (name: 'Pink', argb: 0xFFFF375F),
];

/// A ready-made look: a theme (for the single color / color-block panel) plus
/// colors for the four clock parts (0 = follow the theme).
class ClockPreset {
  const ClockPreset(
    this.name,
    this.themeId, {
    this.hours = 0,
    this.minutes = 0,
    this.colon = 0,
    this.detail = 0,
    this.label = 0,
  });

  final String name;
  final String themeId;
  final int hours;
  final int minutes;
  final int colon;
  final int detail;
  final int label; // World clock city names (0 = auto)

  bool matches(StandbySettings s) =>
      s.activeThemeId == themeId &&
      s.hoursColor == hours &&
      s.minutesColor == minutes &&
      s.colonColor == colon &&
      s.detailColor == detail &&
      s.labelColor == label;

  StandbySettings apply(StandbySettings s) => s.copyWith(
    activeThemeId: themeId,
    hoursColor: hours,
    minutesColor: minutes,
    colonColor: colon,
    detailColor: detail,
    labelColor: label,
  );
}

const _white = 0xFFFFFFFF;
const _red = 0xFFFF453A;
const _blue = 0xFF0A84FF;

/// Looks offered in the clock settings (Apple-style red & white first).
const clockPresets = <ClockPreset>[
  ClockPreset('White', 'aurora'),
  ClockPreset(
    'Red & white',
    'aurora',
    hours: _white,
    minutes: _red,
    detail: _red,
  ),
  ClockPreset('Night red', 'night-red'),
  ClockPreset(
    'Blue & white',
    'aurora',
    hours: _white,
    minutes: _blue,
    colon: _white,
  ),
  ClockPreset('Orange', 'solar'),
  ClockPreset('Yellow', 'yellow'),
  ClockPreset('Green', 'matrix'),
  ClockPreset('Blue', 'blue'),
  ClockPreset('Purple', 'purple'),
  ClockPreset('Pink', 'pink'),
  ClockPreset('Coral', 'coral'),
  ClockPreset('Mint', 'mint'),
  ClockPreset('Lime', 'lime'),
  ClockPreset('Sand', 'sand'),
  ClockPreset('Teal', 'teal'),
];

// iOS StandBy palette: pure black (OLED) with a single vivid accent.
const standbyThemes = <ThemePreset>[
  ThemePreset(
    id: 'aurora',
    name: 'Midnight',
    background: 0xFF000000,
    foreground: 0xFFFFFFFF,
    accent: 0xFF64D2FF,
    secondary: 0xFF5E5CE6,
    glow: 0.0,
    weight: 700,
  ),
  ThemePreset(
    id: 'night-red',
    name: 'Night Red',
    background: 0xFF000000,
    foreground: 0xFFFF453A,
    accent: 0xFFFF453A,
    secondary: 0xFF7F1D1D,
    glow: 0.0,
    weight: 650,
  ),
  ThemePreset(
    id: 'solar',
    name: 'Orange',
    background: 0xFF000000,
    foreground: 0xFFFF9F0A,
    accent: 0xFFFF9F0A,
    secondary: 0xFFFF453A,
    glow: 0.0,
    weight: 700,
  ),
  ThemePreset(
    id: 'matrix',
    name: 'Green',
    background: 0xFF000000,
    foreground: 0xFF30D158,
    accent: 0xFF30D158,
    secondary: 0xFF0A84FF,
    glow: 0.0,
    weight: 700,
  ),
  ThemePreset(
    id: 'pink',
    name: 'Pink',
    background: 0xFF000000,
    foreground: 0xFFFF375F,
    accent: 0xFFFF375F,
    secondary: 0xFFBF5AF2,
    glow: 0.0,
    weight: 700,
  ),
  ThemePreset(
    id: 'purple',
    name: 'Purple',
    background: 0xFF000000,
    foreground: 0xFFBF5AF2,
    accent: 0xFFBF5AF2,
    secondary: 0xFF5E5CE6,
    glow: 0.0,
    weight: 700,
  ),
  ThemePreset(
    id: 'yellow',
    name: 'Yellow',
    background: 0xFF000000,
    foreground: 0xFFFFD60A,
    accent: 0xFFFFD60A,
    secondary: 0xFFFF9F0A,
    glow: 0.0,
    weight: 700,
  ),
  ThemePreset(
    id: 'blue',
    name: 'Blue',
    background: 0xFF000000,
    foreground: 0xFF0A84FF,
    accent: 0xFF0A84FF,
    secondary: 0xFF64D2FF,
    glow: 0.0,
    weight: 700,
  ),
  // Color-block styles from the reference screenshots.
  ThemePreset(
    id: 'coral',
    name: 'Coral',
    background: 0xFF000000,
    foreground: 0xFFFFFFFF,
    accent: 0xFFFF6B5E,
    secondary: 0xFFFFB4A8,
    glow: 0.0,
    weight: 800,
    panel: 0xFFF4685C,
    ink: 0xFF000000,
  ),
  ThemePreset(
    id: 'mint',
    name: 'Mint',
    background: 0xFF000000,
    foreground: 0xFFFFFFFF,
    accent: 0xFF2ECC71,
    secondary: 0xFF1E9E55,
    glow: 0.0,
    weight: 800,
    panel: 0xFF2ECC71,
    ink: 0xFFFFFFFF,
  ),
  ThemePreset(
    id: 'lime',
    name: 'Lime',
    background: 0xFF000000,
    foreground: 0xFFFFFFFF,
    accent: 0xFFD4E157,
    secondary: 0xFFAFB42B,
    glow: 0.0,
    weight: 800,
    panel: 0xFFC9D860,
    ink: 0xFF1A1F00,
  ),
  ThemePreset(
    id: 'sand',
    name: 'Sand',
    background: 0xFF000000,
    foreground: 0xFFFFFFFF,
    accent: 0xFFE9C4B3,
    secondary: 0xFFB08B7E,
    glow: 0.0,
    weight: 800,
    panel: 0xFFEBCFC0,
    ink: 0xFF5A4640,
  ),
  ThemePreset(
    id: 'teal',
    name: 'Teal',
    background: 0xFF000000,
    foreground: 0xFFFFFFFF,
    accent: 0xFF4FA3A5,
    secondary: 0xFF2F6F73,
    glow: 0.0,
    weight: 800,
    panel: 0xFF2A6B70,
    ink: 0xFF5BB5B7,
  ),
];

ThemePreset themeById(String id) {
  return standbyThemes.firstWhere(
    (theme) => theme.id == id,
    orElse: () => standbyThemes.first,
  );
}

@immutable
class StandbySettings {
  const StandbySettings({
    this.layoutMode = StandbyLayoutMode.duo,
    this.activeThemeId = 'aurora',
    this.clockStyle = ClockStyle.digital,
    this.leftWidget = StandbyWidgetType.clock,
    this.rightWidget = StandbyWidgetType.weather,
    this.showSeconds = false,
    this.nightModeEnabled = false,
    this.burnInProtection = true,
    this.lowBatteryAlert = true,
    this.lowBatteryLevel = 20,
    this.autoBrightness = true,
    this.idleDimMinutes = 5,
    this.nightByLight = true,
    this.keepAwakeWhileCharging = true,
    this.use24HourTime = true,
    this.worldZone = '',
    this.musicSource = 'auto',
    this.worldCity = '',
    this.calendarStyle = CalendarStyle.day,
    this.hoursColor = 0,
    this.minutesColor = 0,
    this.colonColor = 0,
    this.detailColor = 0,
    this.labelColor = 0,
    this.localCity = '',
    this.tickScale = 1,
    this.appAccent = 0,
    this.autoStart = false,
    this.autoLeanDeg = 40,
    this.autoLandscapeOnly = true,
    this.autoExitOnUnplug = true,
    this.fahrenheit = false,
    this.brightness = 0.72,
    this.nightTintIntensity = 0.65,
    this.nightStartMin = 1200,
    this.nightEndMin = 420,
    this.nightTint = 'red',
    this.animationIntensity = 0.72,
    this.fontScale = 1, // clock size as a share of its panel, 0.4 .. 1.0
    this.fontWeight = 700,
    this.glowIntensity = 0.0,
  });

  final StandbyLayoutMode layoutMode;
  final String activeThemeId;
  final ClockStyle clockStyle;
  final StandbyWidgetType leftWidget;
  final StandbyWidgetType rightWidget;
  final bool showSeconds;
  final bool nightModeEnabled;
  final bool burnInProtection;
  final bool lowBatteryAlert; // low and not charging: ask to charge the phone
  final int lowBatteryLevel; // percent at or below which that prompt shows
  final bool
  autoBrightness; // follow the room light (Android); iOS auto-brightness
  final int
  idleDimMinutes; // dim the whole screen after this long untouched; 0 = never
  final bool nightByLight; // night look also when the room is dark
  final bool keepAwakeWhileCharging;
  final bool use24HourTime;

  /// 'auto', 'spotify' (account) or an Android package name to follow.
  final String musicSource;
  final CalendarStyle calendarStyle;

  /// Per-part clock colors as ARGB ints; 0 = follow the theme.
  final int hoursColor;
  final int minutesColor;
  final int colonColor; // the ':' between hours and minutes
  final int detailColor; // AM/PM and seconds
  final int labelColor; // World clock city names

  /// Where this phone is (from the weather lookup), e.g. "Cupertino".
  final String localCity;

  /// Frame clock: size of the border ticks (1 = default, smaller than before).
  final double tickScale;

  /// App-wide accent (date card, month highlight, music card fallback), as an
  /// ARGB int; 0 = Apple red. Independent of the clock's own colors.
  final int appAccent;

  /// Auto-start: open Dockwise by itself when the phone is charging and
  /// propped up (see StandbyService on the Android side).
  final bool autoStart;
  final double autoLeanDeg; // how far from lying flat counts as "propped up"
  final bool autoLandscapeOnly;
  final bool autoExitOnUnplug;
  final String worldCity; // display name of the chosen world-clock city
  final bool fahrenheit;
  final String worldZone; // IANA id of the 2nd world-clock city; '' = not set
  final double brightness;
  final double nightTintIntensity;
  final int nightStartMin; // night mode window, minutes after midnight (8 pm)
  final int nightEndMin; // (7 am)
  final String nightTint; // 'red', 'amber' or 'theme' (the clock's own color)
  final double animationIntensity;
  final double fontScale;
  final int fontWeight;
  final double glowIntensity;

  ThemePreset get theme => themeById(activeThemeId);

  /// Seconds are shown only if turned on, the style can show them, and a
  /// clock is actually on screen (so nothing ticks every second needlessly).
  bool get secondsVisible =>
      (clockStyle == ClockStyle.frame ||
          (showSeconds && clockStyle.supportsSeconds)) &&
      (leftWidget == StandbyWidgetType.clock ||
          (layoutMode == StandbyLayoutMode.duo &&
              rightWidget == StandbyWidgetType.clock));

  /// Color rows worth showing now: this style's parts, with "AM/PM & seconds"
  /// only when there is an AM/PM or a seconds readout to color.
  List<ClockPart> get colorParts => [
    for (final p in clockStyle.parts)
      if (p != ClockPart.detail ||
          (clockStyle == ClockStyle.analog
              ? showSeconds
              : (!use24HourTime ||
                    (clockStyle.supportsSeconds && showSeconds))))
        p,
  ];

  /// Accent for everything that is not the clock (the date card, today's
  /// circle, the music card's fallback): the one set under Theme in All
  /// settings. Changing the clock never changes it.
  Color get appAccentInk =>
      appAccent != 0 ? Color(appAccent) : const Color(0xFFFF453A);

  /// Accent derived from the clock's own look (used only by clock parts such as
  /// the World clock's city names): the minutes color if picked, else the
  /// theme's accent (Apple red on the default white look).
  Color get clockAccentInk => minutesColor != 0
      ? Color(minutesColor)
      : (theme.id == 'aurora' ? const Color(0xFFFF453A) : theme.accentColor);

  /// Effective clock colors: a picked color, else the theme's.
  Color get hoursInk => hoursColor == 0 ? theme.clockColor : Color(hoursColor);
  Color get minutesInk => minutesColor == 0 ? hoursInk : Color(minutesColor);
  Color get colonInk =>
      colonColor == 0 ? hoursInk.withValues(alpha: 0.75) : Color(colonColor);

  /// Frame clock's tick marks: a picked color, else the same as the hours so
  /// the whole clock is one color (white by default).
  Color get ticksInk => labelColor != 0 ? Color(labelColor) : hoursInk;

  /// City names on the World clock: picked color, else the accent (the
  /// panel's ink on color-block looks so they stay readable).
  Color get labelInk => labelColor != 0
      ? Color(labelColor)
      : (theme.panelColor != null ? theme.clockAccent : clockAccentInk);
  Color get detailInk =>
      detailColor == 0 ? hoursInk.withValues(alpha: 0.7) : Color(detailColor);

  StandbySettings copyWith({
    StandbyLayoutMode? layoutMode,
    String? activeThemeId,
    ClockStyle? clockStyle,
    StandbyWidgetType? leftWidget,
    StandbyWidgetType? rightWidget,
    bool? showSeconds,
    bool? nightModeEnabled,
    bool? burnInProtection,
    bool? lowBatteryAlert,
    int? lowBatteryLevel,
    bool? autoBrightness,
    int? idleDimMinutes,
    bool? nightByLight,
    bool? keepAwakeWhileCharging,
    bool? use24HourTime,
    String? worldZone,
    String? musicSource,
    String? worldCity,
    CalendarStyle? calendarStyle,
    int? hoursColor,
    int? minutesColor,
    int? colonColor,
    int? detailColor,
    int? labelColor,
    String? localCity,
    double? tickScale,
    int? appAccent,
    bool? autoStart,
    double? autoLeanDeg,
    bool? autoLandscapeOnly,
    bool? autoExitOnUnplug,
    bool? fahrenheit,
    double? brightness,
    double? nightTintIntensity,
    int? nightStartMin,
    int? nightEndMin,
    String? nightTint,
    double? animationIntensity,
    double? fontScale,
    int? fontWeight,
    double? glowIntensity,
  }) {
    return StandbySettings(
      layoutMode: layoutMode ?? this.layoutMode,
      activeThemeId: activeThemeId ?? this.activeThemeId,
      clockStyle: clockStyle ?? this.clockStyle,
      leftWidget: leftWidget ?? this.leftWidget,
      rightWidget: rightWidget ?? this.rightWidget,
      showSeconds: showSeconds ?? this.showSeconds,
      nightModeEnabled: nightModeEnabled ?? this.nightModeEnabled,
      burnInProtection: burnInProtection ?? this.burnInProtection,
      lowBatteryAlert: lowBatteryAlert ?? this.lowBatteryAlert,
      lowBatteryLevel: lowBatteryLevel ?? this.lowBatteryLevel,
      autoBrightness: autoBrightness ?? this.autoBrightness,
      idleDimMinutes: idleDimMinutes ?? this.idleDimMinutes,
      nightByLight: nightByLight ?? this.nightByLight,
      keepAwakeWhileCharging:
          keepAwakeWhileCharging ?? this.keepAwakeWhileCharging,
      use24HourTime: use24HourTime ?? this.use24HourTime,
      worldZone: worldZone ?? this.worldZone,
      musicSource: musicSource ?? this.musicSource,
      worldCity: worldCity ?? this.worldCity,
      calendarStyle: calendarStyle ?? this.calendarStyle,
      hoursColor: hoursColor ?? this.hoursColor,
      minutesColor: minutesColor ?? this.minutesColor,
      colonColor: colonColor ?? this.colonColor,
      detailColor: detailColor ?? this.detailColor,
      labelColor: labelColor ?? this.labelColor,
      localCity: localCity ?? this.localCity,
      tickScale: tickScale ?? this.tickScale,
      appAccent: appAccent ?? this.appAccent,
      autoStart: autoStart ?? this.autoStart,
      autoLeanDeg: autoLeanDeg ?? this.autoLeanDeg,
      autoLandscapeOnly: autoLandscapeOnly ?? this.autoLandscapeOnly,
      autoExitOnUnplug: autoExitOnUnplug ?? this.autoExitOnUnplug,
      fahrenheit: fahrenheit ?? this.fahrenheit,
      brightness: brightness ?? this.brightness,
      nightTintIntensity: nightTintIntensity ?? this.nightTintIntensity,
      nightStartMin: nightStartMin ?? this.nightStartMin,
      nightEndMin: nightEndMin ?? this.nightEndMin,
      nightTint: nightTint ?? this.nightTint,
      animationIntensity: animationIntensity ?? this.animationIntensity,
      fontScale: fontScale ?? this.fontScale,
      fontWeight: fontWeight ?? this.fontWeight,
      glowIntensity: glowIntensity ?? this.glowIntensity,
    );
  }

  Map<String, Object> toJson() {
    return {
      'layoutMode': layoutMode.name,
      'activeThemeId': activeThemeId,
      'clockStyle': clockStyle.name,
      'leftWidget': leftWidget.name,
      'rightWidget': rightWidget.name,
      'showSeconds': showSeconds,
      'nightModeEnabled': nightModeEnabled,
      'burnInProtection': burnInProtection,
      'lowBatteryAlert': lowBatteryAlert,
      'lowBatteryLevel': lowBatteryLevel,
      'autoBrightness': autoBrightness,
      'idleDimMinutes': idleDimMinutes,
      'nightByLight': nightByLight,
      'keepAwakeWhileCharging': keepAwakeWhileCharging,
      'use24HourTime': use24HourTime,
      'worldZone': worldZone,
      'musicSource': musicSource,
      'worldCity': worldCity,
      'calendarStyle': calendarStyle.name,
      'hoursColor': hoursColor,
      'minutesColor': minutesColor,
      'colonColor': colonColor,
      'detailColor': detailColor,
      'labelColor': labelColor,
      'localCity': localCity,
      'tickScale': tickScale,
      'appAccent': appAccent,
      'autoStart': autoStart,
      'autoLeanDeg': autoLeanDeg,
      'autoLandscapeOnly': autoLandscapeOnly,
      'autoExitOnUnplug': autoExitOnUnplug,
      'fahrenheit': fahrenheit,
      'brightness': brightness,
      'nightTintIntensity': nightTintIntensity,
      'nightStartMin': nightStartMin,
      'nightEndMin': nightEndMin,
      'nightTint': nightTint,
      'animationIntensity': animationIntensity,
      'fontScale': fontScale,
      'fontWeight': fontWeight,
      'glowIntensity': glowIntensity,
    };
  }

  factory StandbySettings.fromJson(Map<String, Object?> json) {
    const defaults = StandbySettings();
    return StandbySettings(
      layoutMode: _enumFromName(
        StandbyLayoutMode.values,
        json['layoutMode'],
        defaults.layoutMode,
      ),
      activeThemeId: json['activeThemeId'] as String? ?? defaults.activeThemeId,
      clockStyle: _enumFromName(
        ClockStyle.values,
        json['clockStyle'],
        defaults.clockStyle,
      ),
      leftWidget: _enumFromName(
        StandbyWidgetType.values,
        json['leftWidget'],
        defaults.leftWidget,
      ),
      rightWidget: _enumFromName(
        StandbyWidgetType.values,
        json['rightWidget'],
        defaults.rightWidget,
      ),
      showSeconds: json['showSeconds'] as bool? ?? defaults.showSeconds,
      nightModeEnabled:
          json['nightModeEnabled'] as bool? ?? defaults.nightModeEnabled,
      burnInProtection:
          json['burnInProtection'] as bool? ?? defaults.burnInProtection,
      lowBatteryAlert:
          json['lowBatteryAlert'] as bool? ?? defaults.lowBatteryAlert,
      lowBatteryLevel:
          json['lowBatteryLevel'] as int? ?? defaults.lowBatteryLevel,
      autoBrightness:
          json['autoBrightness'] as bool? ?? defaults.autoBrightness,
      idleDimMinutes: json['idleDimMinutes'] as int? ?? defaults.idleDimMinutes,
      nightByLight: json['nightByLight'] as bool? ?? defaults.nightByLight,
      keepAwakeWhileCharging:
          json['keepAwakeWhileCharging'] as bool? ??
          defaults.keepAwakeWhileCharging,
      use24HourTime: json['use24HourTime'] as bool? ?? defaults.use24HourTime,
      worldZone: json['worldZone'] as String? ?? defaults.worldZone,
      musicSource: json['musicSource'] as String? ?? defaults.musicSource,
      worldCity: json['worldCity'] as String? ?? defaults.worldCity,
      hoursColor: (json['hoursColor'] as num?)?.toInt() ?? 0,
      minutesColor: (json['minutesColor'] as num?)?.toInt() ?? 0,
      colonColor: (json['colonColor'] as num?)?.toInt() ?? 0,
      detailColor: (json['detailColor'] as num?)?.toInt() ?? 0,
      labelColor: (json['labelColor'] as num?)?.toInt() ?? 0,
      localCity: json['localCity'] as String? ?? '',
      tickScale: (json['tickScale'] as num?)?.toDouble() ?? 1,
      appAccent: (json['appAccent'] as num?)?.toInt() ?? 0,
      autoStart: json['autoStart'] as bool? ?? false,
      autoLeanDeg: (json['autoLeanDeg'] as num?)?.toDouble() ?? 40,
      autoLandscapeOnly: json['autoLandscapeOnly'] as bool? ?? true,
      autoExitOnUnplug: json['autoExitOnUnplug'] as bool? ?? true,
      calendarStyle: _enumFromName(
        CalendarStyle.values,
        json['calendarStyle'],
        defaults.calendarStyle,
      ),
      fahrenheit: json['fahrenheit'] as bool? ?? defaults.fahrenheit,
      brightness:
          (json['brightness'] as num?)?.toDouble() ?? defaults.brightness,
      nightTintIntensity:
          (json['nightTintIntensity'] as num?)?.toDouble() ??
          defaults.nightTintIntensity,
      nightStartMin: json['nightStartMin'] as int? ?? defaults.nightStartMin,
      nightEndMin: json['nightEndMin'] as int? ?? defaults.nightEndMin,
      nightTint: json['nightTint'] as String? ?? defaults.nightTint,
      animationIntensity:
          (json['animationIntensity'] as num?)?.toDouble() ??
          defaults.animationIntensity,
      fontScale: (json['fontScale'] as num?)?.toDouble() ?? defaults.fontScale,
      fontWeight: (json['fontWeight'] as num?)?.round() ?? defaults.fontWeight,
      glowIntensity:
          (json['glowIntensity'] as num?)?.toDouble() ?? defaults.glowIntensity,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StandbySettings &&
        other.layoutMode == layoutMode &&
        other.activeThemeId == activeThemeId &&
        other.clockStyle == clockStyle &&
        other.leftWidget == leftWidget &&
        other.rightWidget == rightWidget &&
        other.showSeconds == showSeconds &&
        other.nightModeEnabled == nightModeEnabled &&
        other.burnInProtection == burnInProtection &&
        other.lowBatteryAlert == lowBatteryAlert &&
        other.lowBatteryLevel == lowBatteryLevel &&
        other.autoBrightness == autoBrightness &&
        other.idleDimMinutes == idleDimMinutes &&
        other.nightByLight == nightByLight &&
        other.keepAwakeWhileCharging == keepAwakeWhileCharging &&
        other.use24HourTime == use24HourTime &&
        other.worldZone == worldZone &&
        other.musicSource == musicSource &&
        other.worldCity == worldCity &&
        other.calendarStyle == calendarStyle &&
        other.hoursColor == hoursColor &&
        other.minutesColor == minutesColor &&
        other.colonColor == colonColor &&
        other.detailColor == detailColor &&
        other.labelColor == labelColor &&
        other.localCity == localCity &&
        _sameDouble(other.tickScale, tickScale) &&
        other.appAccent == appAccent &&
        other.autoStart == autoStart &&
        _sameDouble(other.autoLeanDeg, autoLeanDeg) &&
        other.autoLandscapeOnly == autoLandscapeOnly &&
        other.autoExitOnUnplug == autoExitOnUnplug &&
        other.fahrenheit == fahrenheit &&
        _sameDouble(other.brightness, brightness) &&
        _sameDouble(other.nightTintIntensity, nightTintIntensity) &&
        other.nightStartMin == nightStartMin &&
        other.nightEndMin == nightEndMin &&
        other.nightTint == nightTint &&
        _sameDouble(other.animationIntensity, animationIntensity) &&
        _sameDouble(other.fontScale, fontScale) &&
        other.fontWeight == fontWeight &&
        _sameDouble(other.glowIntensity, glowIntensity);
  }

  @override
  int get hashCode => Object.hashAll([
    layoutMode,
    activeThemeId,
    clockStyle,
    leftWidget,
    rightWidget,
    showSeconds,
    nightModeEnabled,
    burnInProtection,
    lowBatteryAlert,
    lowBatteryLevel,
    autoBrightness,
    idleDimMinutes,
    nightByLight,
    keepAwakeWhileCharging,
    use24HourTime,
    worldZone,
    musicSource,
    worldCity,
    fahrenheit,
    brightness,
    nightTintIntensity,
    nightStartMin,
    nightEndMin,
    nightTint,
    animationIntensity,
    fontScale,
    fontWeight,
    glowIntensity,
    calendarStyle,
    hoursColor,
    minutesColor,
    colonColor,
    detailColor,
    labelColor,
    localCity,
    tickScale,
    appAccent,
    autoStart,
    autoLeanDeg,
    autoLandscapeOnly,
    autoExitOnUnplug,
  ]);
}

bool _sameDouble(double a, double b) => (a - b).abs() < 0.000001;

class StandbyWidgetConfig {
  const StandbyWidgetConfig({
    required this.type,
    required this.slot,
    required this.refreshCadence,
  });

  final StandbyWidgetType type;
  final String slot;
  final Duration refreshCadence;
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.city,
    required this.condition,
    required this.temperatureCelsius,
    required this.highCelsius,
    required this.lowCelsius,
    required this.updatedAt,
    this.code,
    this.isDay = true,
  });

  /// WMO weather code from Open-Meteo (drives the icon and card tint).
  final int? code;
  final bool isDay;
  final String city;
  final String condition;
  final int temperatureCelsius;
  final int highCelsius;
  final int lowCelsius;
  final DateTime updatedAt;
}

class NowPlayingSnapshot {
  const NowPlayingSnapshot({
    required this.title,
    required this.artist,
    required this.source,
    required this.progress,
    required this.isPlaying,
    required this.isControllable,
    this.artUrl,
    this.artBytes,
    this.positionMs = 0,
    this.durationMs = 0,
    this.viaSpotifyApi = false,
    this.fetchedAt,
  });

  /// When [positionMs] was read; lets the UI run the clock between polls.
  final DateTime? fetchedAt;

  /// Same song, jumped to [ms] now (shown instantly while a seek completes).
  NowPlayingSnapshot withPosition(int ms) => NowPlayingSnapshot(
    title: title,
    artist: artist,
    source: source,
    progress: durationMs > 0 ? ms / durationMs : progress,
    isPlaying: isPlaying,
    isControllable: isControllable,
    artUrl: artUrl,
    artBytes: artBytes,
    positionMs: ms,
    durationMs: durationMs,
    viaSpotifyApi: viaSpotifyApi,
    fetchedAt: DateTime.now(),
  );

  /// Song position at [now], advancing in real time while playing.
  int positionAt(DateTime now) {
    final at = fetchedAt;
    if (!isPlaying || at == null) return positionMs;
    final live = positionMs + now.difference(at).inMilliseconds;
    return durationMs > 0 ? live.clamp(0, durationMs) : live;
  }

  /// True when read from the Spotify Web API (commands must go there too).
  final bool viaSpotifyApi;

  final int positionMs;
  final int durationMs;

  final String? artUrl;
  final Uint8List? artBytes;
  final String title;
  final String artist;
  final String source;
  final double progress;
  final bool isPlaying;
  final bool isControllable;
}

class IntegrationSnapshotBundle {
  const IntegrationSnapshotBundle({this.weather, required this.nowPlaying});

  /// Null until real weather for the phone's location has been fetched.
  final WeatherSnapshot? weather;
  final NowPlayingSnapshot nowPlaying;

  factory IntegrationSnapshotBundle.fallback({required DateTime now}) {
    return const IntegrationSnapshotBundle(
      nowPlaying: NowPlayingSnapshot(
        title: 'Nothing playing',
        artist: 'Start music on this phone or Spotify',
        source: 'Idle',
        progress: 0,
        isPlaying: false,
        isControllable: false,
      ),
    );
  }
}
