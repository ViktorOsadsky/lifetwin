import 'package:flutter/widgets.dart';

import 'lt_colors.dart';

/// Brand faces. Both are bundled variable fonts; weight is selected through
/// the `wght` axis as well as `fontWeight`.
class LtFonts {
  const LtFonts._();

  static const display = 'Bricolage';
  static const body = 'DMSans';
}

TextStyle _style(String family, double size, double line, double weight) =>
    TextStyle(
      fontFamily: family,
      fontSize: size,
      height: line / size,
      fontWeight: FontWeight.values[((weight / 100).round().clamp(1, 9)) - 1],
      fontVariations: [FontVariation('wght', weight)],
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Text styles from the brief. Sizes are logical px; Flutter's `Text` scales
/// them with `MediaQuery.textScaler`, which follows iOS Dynamic Type.
/// Nothing is smaller than 12.
class LtTextStyles {
  const LtTextStyles(this.colors);

  final LtColors colors;

  TextStyle get largeTitle =>
      _style(LtFonts.display, 34, 41, 800).copyWith(color: colors.textPrimary);
  TextStyle get title1 =>
      _style(LtFonts.display, 28, 34, 700).copyWith(color: colors.textPrimary);
  TextStyle get title2 =>
      _style(LtFonts.display, 22, 28, 700).copyWith(color: colors.textPrimary);
  TextStyle get title3 =>
      _style(LtFonts.body, 20, 25, 600).copyWith(color: colors.textPrimary);
  TextStyle get headline =>
      _style(LtFonts.body, 17, 22, 600).copyWith(color: colors.textPrimary);
  TextStyle get body =>
      _style(LtFonts.body, 17, 22, 400).copyWith(color: colors.textPrimary);
  TextStyle get callout =>
      _style(LtFonts.body, 16, 21, 400).copyWith(color: colors.textPrimary);
  TextStyle get subhead =>
      _style(LtFonts.body, 15, 20, 400).copyWith(color: colors.textPrimary);
  TextStyle get footnote =>
      _style(LtFonts.body, 13, 18, 400).copyWith(color: colors.textSecondary);
  TextStyle get caption =>
      _style(LtFonts.body, 12, 16, 500).copyWith(color: colors.textSecondary);
  TextStyle get statXl =>
      _style(LtFonts.display, 56, 60, 800).copyWith(color: colors.textPrimary);
}
