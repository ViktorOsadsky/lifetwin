import 'package:flutter/widgets.dart';

/// Spacing scale, radii and layout constants (design brief section 2).
class LtSpace {
  const LtSpace._();

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;

  /// Screen side padding.
  static const double gutter = 20;

  /// Minimum touch target.
  static const double touch = 44;

  /// Tab bar content height, excluding the bottom inset.
  static const double tabBar = 49;
}

class LtRadius {
  const LtRadius._();

  static const double card = 24;
  static const double sheet = 28;
  static const double control = 22;
  static const double chip = 999;
  static const double small = 12;

  static const cardAll = BorderRadius.all(Radius.circular(card));
  static const controlAll = BorderRadius.all(Radius.circular(control));
  static const chipAll = BorderRadius.all(Radius.circular(chip));
  static const smallAll = BorderRadius.all(Radius.circular(small));
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
}
