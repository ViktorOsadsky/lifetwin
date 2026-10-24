import 'package:flutter/material.dart';

/// LifeTwin design tokens, taken from the Claude Design proposal "LifeTwin Pip Screens"
/// (see lib/widgets/README.md). Every color, size and radius used by lib/widgets lives
/// here, so a design change is an edit to this file.

/// Palette. Names follow the design's own: Paper, Ink, Lavender, Mint, Coral.
abstract final class LtColors {
  static const paper = Color(0xFFF6F6FC); // screen background
  static const ink = Color(0xFF313C61); // text, outlines, filled progress
  static const inkMuted = Color(0xFF7A82A3); // empty-dot outline
  static const white = Color(0xFFFFFFFF); // cards, bubbles, secondary buttons

  static const lavender = Color(0xFFA8A9F0); // squiggles, magic ball, sound waves
  static const lavenderLip = Color(0xFFC9CAF5); // secondary button lip
  static const lavenderTrack = Color(0xFFDCDDF5); // progress segments still to come
  static const lavenderWash = Color(0xFFE9E9FB); // scene background wave

  static const mint = Color(0xFFB3E4D7); // primary buttons, Pip's body, ground
  static const mintDeep = Color(0xFF86CDB8); // primary lip, Pip's leaves, filled dots

  static const coral = Color(0xFFFF9F8B); // cheeks, sparkle
  static const listening = Color(0xFFFFE6E0); // "Listening…" button face
  static const listeningLip = Color(0xFFF2B6A8);
  static const recording = Color(0xFFD7402B); // the red recording dot

  // The twin.
  static const skin = Color(0xFFF1C7A6);
  static const skinDeep = Color(0xFFEDBE99);
  static const hair = Color(0xFFDADBEF);
}

/// Font families bundled in assets/fonts (pubspec.yaml).
abstract final class LtFonts {
  /// Headings, button labels, numbers.
  static const heading = 'Fredoka';

  /// Questions, captions, body.
  static const body = 'AtkinsonHyperlegible';
}

/// Fredoka ships as one variable font, so its weight is set through the 'wght' axis.
TextStyle _fredoka(double size, {FontWeight weight = FontWeight.w600, double height = 1.15}) => TextStyle(
  fontFamily: LtFonts.heading,
  fontSize: size,
  fontWeight: weight,
  fontVariations: [FontVariation.weight(weight.value.toDouble())],
  height: height,
  color: LtColors.ink,
);

TextStyle _atkinson(double size, {bool bold = false, double height = 1.35}) => TextStyle(
  fontFamily: LtFonts.body,
  fontSize: size,
  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
  height: height,
  color: LtColors.ink,
);

/// Text styles at the design's sizes (390 pt wide artboards).
abstract final class LtText {
  static final display = _fredoka(38, height: 1.1); // "Your room"
  static final title = _fredoka(32); // "Your forecast"
  static final sectionTitle = _fredoka(25, height: 1.2);

  static final question = _atkinson(28, bold: true, height: 1.2);
  static final body = _atkinson(22, height: 1.36);
  static final bodyStrong = _atkinson(22, bold: true, height: 1.36);
  static final bodySmall = _atkinson(20, height: 1.4);
  static final bubble = _atkinson(24, bold: true, height: 1.25);
  static final label = _atkinson(20, bold: true, height: 1.25); // "Question 3 of 11"
  static final caption = _atkinson(18, bold: true, height: 1.3); // smallest text anywhere
  static final link = _atkinson(21, bold: true, height: 1.2).copyWith(
    decoration: TextDecoration.underline,
    decorationThickness: 2,
    decorationColor: LtColors.ink,
  );

  static final primaryButton = _fredoka(30, height: 1.2);
  static final secondaryButton = _fredoka(25, height: 1.2);
  static final pillButton = _fredoka(21, height: 1.2); // Back
  static final stat = _fredoka(32, height: 1.1); // numbers on the forecast tiles
}

/// Spacing used on the artboards.
abstract final class LtSpace {
  static const gutter = 24.0; // screen side padding
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 22.0;
  static const xxl = 32.0;
  static const buttonGap = 18.0; // between stacked buttons
}

/// Outline widths.
abstract final class LtOutline {
  static const width = 3.0;
  static const selected = 4.5; // a selected tile also gets a check mark, never color alone
  static const focusRing = 4.0;
  static const focusOffset = 5.0;
  static const side = BorderSide(color: LtColors.ink, width: width);
}

/// Corner radii. The design's buttons are slightly uneven ("30px 26px 30px 28px").
abstract final class LtRadii {
  static const primary = BorderRadius.only(
    topLeft: Radius.circular(30),
    topRight: Radius.circular(26),
    bottomRight: Radius.circular(30),
    bottomLeft: Radius.circular(28),
  );
  static const secondary = BorderRadius.only(
    topLeft: Radius.circular(26),
    topRight: Radius.circular(22),
    bottomRight: Radius.circular(26),
    bottomLeft: Radius.circular(24),
  );
  static const pill = BorderRadius.all(Radius.circular(28));
  static const tile = BorderRadius.all(Radius.circular(22));
  static const bubble = BorderRadius.all(Radius.circular(28));
  static const card = BorderRadius.all(Radius.circular(26));
}

/// Button "lip": a solid shadow straight below the face. Pressing drops the face onto it.
abstract final class LtLip {
  static const primary = 7.0;
  static const secondary = 6.0;
  static const small = 5.0; // Back pill, tiles
}

/// Minimum tap heights (face only, lip excluded).
abstract final class LtSize {
  static const primaryButton = 96.0; // design: 96–128
  static const secondaryButton = 78.0; // design: 76–96
  static const minButton = 72.0; // nothing that is a "button" is shorter
  static const smallTap = 56.0; // Back pill, text links: the design's floor
  static const tile = 84.0;
  static const icon = 34.0;
}

/// Material 3 theme with the tokens above and large defaults for readers 65+.
ThemeData lifeTwinTheme() {
  const scheme = ColorScheme.light(
    primary: LtColors.ink,
    onPrimary: LtColors.white,
    primaryContainer: LtColors.mint,
    onPrimaryContainer: LtColors.ink,
    secondary: LtColors.lavender,
    onSecondary: LtColors.ink,
    secondaryContainer: LtColors.lavenderWash,
    onSecondaryContainer: LtColors.ink,
    tertiary: LtColors.coral,
    onTertiary: LtColors.ink,
    error: LtColors.recording,
    onError: LtColors.white,
    surface: LtColors.paper,
    onSurface: LtColors.ink,
    surfaceContainerLowest: LtColors.white,
    surfaceContainerHighest: LtColors.lavenderWash,
    onSurfaceVariant: LtColors.ink,
    outline: LtColors.ink,
    outlineVariant: LtColors.inkMuted,
  );

  final text = TextTheme(
    displayLarge: _fredoka(48, height: 1.1),
    displayMedium: _fredoka(42, height: 1.1),
    displaySmall: LtText.display,
    headlineLarge: _fredoka(34),
    headlineMedium: LtText.title,
    headlineSmall: _fredoka(28),
    titleLarge: _atkinson(24, bold: true, height: 1.3),
    titleMedium: _atkinson(22, bold: true, height: 1.3),
    titleSmall: _atkinson(20, bold: true, height: 1.3),
    bodyLarge: LtText.body,
    bodyMedium: _atkinson(20),
    bodySmall: _atkinson(18),
    labelLarge: LtText.secondaryButton,
    labelMedium: _atkinson(20, bold: true, height: 1.2),
    labelSmall: _atkinson(18, bold: true, height: 1.2),
  );

  const minButton = Size(64, LtSize.minButton);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 14);
  final buttonShape = const RoundedRectangleBorder(borderRadius: LtRadii.secondary, side: LtOutline.side);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: LtFonts.body,
    textTheme: text,
    scaffoldBackgroundColor: LtColors.paper,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: LtColors.paper,
      foregroundColor: LtColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 72,
      titleTextStyle: _fredoka(28),
      iconTheme: const IconThemeData(color: LtColors.ink, size: 32),
    ),
    iconTheme: const IconThemeData(color: LtColors.ink, size: 32),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minButton,
        padding: buttonPadding,
        backgroundColor: LtColors.mint,
        foregroundColor: LtColors.ink,
        disabledBackgroundColor: LtColors.lavenderTrack,
        disabledForegroundColor: LtColors.inkMuted,
        textStyle: LtText.secondaryButton,
        shape: buttonShape,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: minButton,
        padding: buttonPadding,
        backgroundColor: LtColors.mint,
        foregroundColor: LtColors.ink,
        textStyle: LtText.secondaryButton,
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minButton,
        padding: buttonPadding,
        backgroundColor: LtColors.white,
        foregroundColor: LtColors.ink,
        textStyle: LtText.secondaryButton,
        side: LtOutline.side,
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(64, LtSize.smallTap),
        foregroundColor: LtColors.ink,
        textStyle: LtText.link,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LtColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      hintStyle: _atkinson(22).copyWith(color: LtColors.inkMuted),
      border: const OutlineInputBorder(borderRadius: LtRadii.tile, borderSide: LtOutline.side),
      enabledBorder: const OutlineInputBorder(borderRadius: LtRadii.tile, borderSide: LtOutline.side),
      focusedBorder: const OutlineInputBorder(
        borderRadius: LtRadii.tile,
        borderSide: BorderSide(color: LtColors.ink, width: LtOutline.selected),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: LtColors.ink,
      linearTrackColor: LtColors.lavenderTrack,
    ),
  );
}
