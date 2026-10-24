import 'package:flutter/material.dart';

import 'lt_colors.dart';
import 'lt_type.dart';

extension LtContext on BuildContext {
  LtColors get colors => Theme.of(this).extension<LtColors>()!;
  LtTextStyles get text => LtTextStyles(colors);
}

/// Builds the app ThemeData from the token file.
ThemeData buildLtTheme() {
  const c = LtColors.light;
  final text = const LtTextStyles(c);
  final scheme = ColorScheme.light(
    primary: c.actionPrimary,
    onPrimary: c.bgSurface,
    secondary: c.vizExperiment,
    onSecondary: c.bgSurface,
    surface: c.bgSurface,
    onSurface: c.textPrimary,
    error: c.actionPrimary,
    onError: c.bgSurface,
    outline: c.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bgGround,
    canvasColor: c.bgGround,
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.clear,
    dividerColor: c.line,
    fontFamily: LtFonts.body,
    textTheme: TextTheme(
      displayLarge: text.largeTitle,
      headlineLarge: text.title1,
      headlineMedium: text.title2,
      titleLarge: text.title3,
      titleMedium: text.headline,
      bodyLarge: text.body,
      bodyMedium: text.callout,
      bodySmall: text.footnote,
      labelLarge: text.headline,
      labelSmall: text.caption,
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    extensions: const [LtColors.light],
  );
}
