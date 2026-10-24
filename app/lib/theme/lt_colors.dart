import 'package:flutter/material.dart';

/// The only colours in the app (design brief section 2).
/// Everything reads these through `context.colors`; no raw colour literals
/// are allowed outside `lib/theme/`.
@immutable
class LtColors extends ThemeExtension<LtColors> {
  const LtColors({
    required this.bgSurface,
    required this.bgGround,
    required this.textPrimary,
    required this.textSecondary,
    required this.line,
    required this.actionPrimary,
    required this.skyHighlight,
    required this.chipSelected,
    required this.textPositive,
    required this.vizExperiment,
    required this.fillVitality,
    required this.chipPositive,
    required this.vizBaseline,
    required this.sun,
    required this.calmSurface,
    required this.actionPrimaryPressed,
    required this.clear,
  });

  /// Cards, sheets (`surface` #FFFFFF).
  final Color bgSurface;

  /// App ground (`ground` #F4F8FF).
  final Color bgGround;

  /// Primary text (`ink` #0E1B3D).
  final Color textPrimary;

  /// Secondary text (`ink-2` #4A5878).
  final Color textSecondary;

  /// Dividers and borders, decorative only (`line` #E3EAF5).
  final Color line;

  /// Primary buttons, links, tint, the "You" curve (`blue-600` #2563EB).
  final Color actionPrimary;

  /// Sky and highlights, never text (`blue-400` #5AA9FF).
  final Color skyHighlight;

  /// Chips and selected states (`blue-100` #DCEBFF).
  final Color chipSelected;

  /// Positive delta text and positive chip text (`green-700` #047857).
  final Color textPositive;

  /// Experiment curve, positive fills and icons (`green-600` #0E9F6E).
  final Color vizExperiment;

  /// Vitality and success fills (`green-400` #34D399).
  final Color fillVitality;

  /// Positive chips (`green-100` #D3F7E6).
  final Color chipPositive;

  /// Baseline / similar-people dashed curve (#7A879F).
  final Color vizBaseline;

  /// Sparkles and milestone reactions only (`sun` #FFD66B).
  final Color sun;

  /// Resting tier, calm surfaces (`lavender-100` #ECEBFA).
  final Color calmSurface;

  /// Pressed primary button face (`blue-700` / `action/primary-pressed`
  /// #1D4ED8). White text 6.7:1.
  final Color actionPrimaryPressed;

  /// Fully transparent, for layers that must paint nothing.
  final Color clear;

  static const light = LtColors(
    bgSurface: Color(0xFFFFFFFF),
    bgGround: Color(0xFFF4F8FF),
    textPrimary: Color(0xFF0E1B3D),
    textSecondary: Color(0xFF4A5878),
    line: Color(0xFFE3EAF5),
    actionPrimary: Color(0xFF2563EB),
    skyHighlight: Color(0xFF5AA9FF),
    chipSelected: Color(0xFFDCEBFF),
    textPositive: Color(0xFF047857),
    vizExperiment: Color(0xFF0E9F6E),
    fillVitality: Color(0xFF34D399),
    chipPositive: Color(0xFFD3F7E6),
    vizBaseline: Color(0xFF7A879F),
    sun: Color(0xFFFFD66B),
    calmSurface: Color(0xFFECEBFA),
    actionPrimaryPressed: Color(0xFF1D4ED8),
    clear: Color(0x00000000),
  );

  /// Sheet surface, tinted from the page ground rather than stark white, so a
  /// sheet rising out of a habitat reads as part of the same page (§7b.3).
  Color get bgSheet => Color.lerp(bgSurface, bgGround, 0.5)!;

  /// Faint backdrop behind a row's illustrated icon.
  Color get iconBackdrop => Color.lerp(bgGround, chipSelected, 0.55)!;

  /// Card shadow: 0 8 24 rgba(14,27,61,0.08).
  List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: textPrimary.withValues(alpha: 0.08),
      offset: const Offset(0, 8),
      blurRadius: 24,
    ),
  ];

  /// Sheet shadow: 0 -4 24 rgba(14,27,61,0.10).
  List<BoxShadow> get sheetShadow => [
    BoxShadow(
      color: textPrimary.withValues(alpha: 0.10),
      offset: const Offset(0, -4),
      blurRadius: 24,
    ),
  ];

  @override
  LtColors copyWith() => this;

  @override
  LtColors lerp(ThemeExtension<LtColors>? other, double t) => this;
}
