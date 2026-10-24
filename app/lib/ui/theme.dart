/// Painted-card design tokens (docs/design/painted-card-direction.md §3).
///
/// Painted art carries the charm; the UI layer is flat, outlined and opaque,
/// and text never sits on paint.
library;

import 'package:flutter/material.dart';

abstract final class LtColors {
  static const ink = Color(0xFF4A2F25);
  static const paper = Color(0xFFFFFDF8);
  static const cream = Color(0xFFFBF4EA);
  static const mint = Color(0xFF9FD9C3);
  static const mintLip = Color(0xFF5FAF93);
  static const lavender = Color(0xFFB9B4F0);
  static const peach = Color(0xFFF8B9A0);
  static const peachLip = Color(0xFFE8957A);
  static const night = Color(0xFF1E2547);
  static const nightDeep = Color(0xFF121731);
  static const nightLine = Color(0xFF0B0F26);
  static const gold = Color(0xFFE8B64C);
  static const goldRule = Color(0xFFE2B357);
  static const brace = Color(0xFFB4532F);

  /// Cream lip under secondary buttons.
  static const creamLip = Color(0xFFE9DFD0);

  /// Controls (buttons, chips, tiles, switches): 2px, 4.7:1 on paper.
  static const control = Color(0xFF8C6B5D);

  /// Control outline on mint.
  static const controlOnMint = Color(0xFF7A5B4E);

  /// Containers (window line, panels, sheets, banner, bubbles): 1.5px.
  static const container = Color(0xFFA88B7D);

  /// Read-back value card fill.
  static const mintWash = Color(0xFFEEF8F3);

  /// Switch track when off.
  static const trackOff = Color(0xFFEFE6D8);
}

abstract final class LtRadii {
  static const double panel = 28;
  static const double window = 30;
  static const double plate = 24;
  static const double tile = 22;
  static const double chip = 26;
}

abstract final class LtBorders {
  static const double control = 2;
  static const double container = 1.5;
}

abstract final class LtShadows {
  /// `BoxShadow(color: 0x24 ink, offset: (0, 6), blur 16)`.
  static const soft = [BoxShadow(color: Color(0x244A2F25), offset: Offset(0, 6), blurRadius: 16)];
  static const small = [BoxShadow(color: Color(0x1A4A2F25), offset: Offset(0, 3), blurRadius: 10)];
  static const night = [BoxShadow(color: Color(0x59050819), offset: Offset(0, 6), blurRadius: 16)];
}

/// The light behind the panels. Layout stays put; only the light changes.
enum LtMode {
  room(Color(0xFFF0ECFD), Color(0xFFE6E0FA)),
  onboarding(Color(0xFFE3F5EC), Color(0xFFD3EEE2)),
  customize(Color(0xFFFDEBE1), Color(0xFFFBE0D2)),
  fortune(Color(0xFF1B2245), Color(0xFF121731));

  const LtMode(this.inner, this.outer);
  final Color inner;
  final Color outer;

  bool get isNight => this == LtMode.fortune;

  /// Flat mode tint (no textures): the mockups' soft radial wash.
  Gradient get gradient => RadialGradient(
    center: const Alignment(0, -0.64),
    radius: 1.4,
    colors: [inner, outer],
    stops: const [0, 0.72],
  );
}

/// Bundled under assets/fonts/ (SIL Open Font License 1.1; the OFL texts sit
/// beside the TTFs). Fredoka is one variable font, so its weight is set
/// through the `wght` axis in [LtText.display].
abstract final class LtFonts {
  static const display = 'Fredoka';
  static const body = 'Atkinson Hyperlegible';
}

abstract final class LtText {
  /// Fredoka 600 (or 500): titles, bubbles, buttons. The variable font's
  /// `wght` axis is set explicitly; `fontWeight` alone does not drive it.
  static TextStyle display(double size, {Color color = LtColors.ink, FontWeight weight = FontWeight.w600}) =>
      TextStyle(
        fontFamily: LtFonts.display,
        fontSize: size,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', weight == FontWeight.w500 ? 500 : 600)],
        height: 1.18,
        color: color,
      );

  /// Atkinson Hyperlegible body, 17pt or larger.
  static TextStyle body({double size = 17, Color color = LtColors.ink, FontWeight weight = FontWeight.w400}) =>
      TextStyle(fontFamily: LtFonts.body, fontSize: size, fontWeight: weight, height: 1.35, color: color);
}

ThemeData lifeTwinTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: LtColors.mint,
    onPrimary: LtColors.ink,
    primaryContainer: LtColors.mintWash,
    onPrimaryContainer: LtColors.ink,
    secondary: LtColors.peach,
    onSecondary: LtColors.ink,
    secondaryContainer: LtColors.cream,
    onSecondaryContainer: LtColors.ink,
    tertiary: LtColors.lavender,
    onTertiary: LtColors.ink,
    surface: LtColors.paper,
    onSurface: LtColors.ink,
    surfaceContainerHighest: LtColors.cream,
    onSurfaceVariant: LtColors.ink,
    outline: LtColors.control,
    error: LtColors.brace,
    onError: LtColors.paper,
  );
  final text = TextTheme(
    headlineLarge: LtText.display(34),
    headlineMedium: LtText.display(28),
    headlineSmall: LtText.display(24),
    titleLarge: LtText.body(size: 20),
    titleMedium: LtText.body(size: 18, weight: FontWeight.w700),
    titleSmall: LtText.body(size: 17, weight: FontWeight.w700),
    bodyLarge: LtText.body(size: 18),
    bodyMedium: LtText.body(),
    bodySmall: LtText.body(size: 15),
    labelLarge: LtText.body(size: 18, weight: FontWeight.w700),
    labelMedium: LtText.body(size: 17, weight: FontWeight.w700),
    labelSmall: LtText.body(size: 15, weight: FontWeight.w700),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LtColors.cream,
    fontFamily: LtFonts.body,
    textTheme: text,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LtColors.paper,
      labelStyle: LtText.body(),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: LtColors.control, width: LtBorders.control),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: LtColors.control, width: LtBorders.control),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: LtColors.ink, width: 2.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: LtColors.ink, minimumSize: const Size(48, 48)),
    ),
  );
}
