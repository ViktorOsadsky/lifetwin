import 'package:flutter/material.dart';

import 'lt_colors.dart';

/// Cosmetic-only palettes for the Twin. These mirror the Figma **Character**
/// collection. They are avatar art, not UI colour, and never feed any number.
/// Top colours reuse brand tokens.
class LtCosmetics {
  const LtCosmetics._();

  /// `char/skin/1..5`: realistic, inclusive skin tones, light to deep.
  static const skin = <Color>[
    Color(0xFFF6D7C3),
    Color(0xFFE8B894),
    Color(0xFFC98E64),
    Color(0xFF8D5A3B),
    Color(0xFF5A3825),
  ];

  /// `char/hair/black|brown|auburn|blonde|silver`, in that order.
  static const hair = <Color>[
    Color(0xFF2B1B12),
    Color(0xFF5B3A24),
    Color(0xFFA0522D),
    Color(0xFFD9B26F),
    Color(0xFFB8BCC6),
  ];

  static const hairNames = <String>[
    'Black',
    'Brown',
    'Auburn',
    'Blonde',
    'Silver',
  ];

  /// `char/cheek`.
  static const cheek = Color(0xFFF5A3A3);

  /// `char/line` (= ink).
  static const line = Color(0xFF0E1B3D);

  /// `char/eye-shine`.
  static const eyeShine = Color(0xFFFFFFFF);

  static List<Color> tops(LtColors c) => [
    c.actionPrimary,
    c.vizExperiment,
    c.sun,
    c.skyHighlight,
    c.vizBaseline,
  ];

  static const topNames = <String>['Blue', 'Green', 'Sun', 'Sky', 'Slate'];
}
