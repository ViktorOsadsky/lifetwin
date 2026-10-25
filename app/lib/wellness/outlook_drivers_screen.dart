import 'package:flutter/material.dart';

import '../widgets/whole_word_text.dart';

import '../ui/theme.dart';
import '../ui/widgets/widgets.dart';
import 'widgets.dart';

enum DriverDirection { higher, lower, flat, unavailable }

class OutlookDriver {
  const OutlookDriver({
    required this.label,
    required this.direction,
    required this.reason,
  });
  final String label;
  final DriverDirection direction;
  final String reason;

  /// Effect magnitudes stay outside this directions-only surface, including text
  /// received from an older adapter that embeds point values in its reason.
  String get displayReason =>
      RegExp(
        r'%|\b(percent(?:age)?|points?|pp|years? gained)\b',
        caseSensitive: false,
      ).hasMatch(reason)
      ? 'A model association, not a promised benefit.'
      : reason;
  // Deliberately no points, years, percentages or numerical model effect.
}

class OutlookDriversScreen extends StatelessWidget {
  const OutlookDriversScreen({
    super.key,
    required this.drivers,
    required this.onBack,
    required this.onExperiment,
    this.onIdeas,
  });
  final List<OutlookDriver> drivers;
  final VoidCallback onBack;

  /// The Experiment screen belongs to codex/c-agentic-ui.
  final VoidCallback onExperiment;

  /// "See ideas": the Ideas for you list (null hides it: under 18).
  final VoidCallback? onIdeas;

  @override
  Widget build(BuildContext context) => WellnessPage(
    title: 'What moves it',
    subtitle: 'Explore the patterns behind your outlook.',
    onBack: onBack,
    children: [
      if (drivers.isEmpty)
        const MochiMessage(
          message: 'We need a few more answers to explore this.',
        ),
      for (final driver in drivers)
        WellnessCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WholeWordText(driver.label, style: LtText.display(24)),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(switch (driver.direction) {
                    DriverDirection.higher => Icons.north_east_rounded,
                    DriverDirection.lower => Icons.south_east_rounded,
                    DriverDirection.flat => Icons.east_rounded,
                    DriverDirection.unavailable => Icons.help_outline_rounded,
                  }, color: LtColors.ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: WholeWordText(switch (driver.direction) {
                      DriverDirection.higher =>
                        'Linked with a higher modeled outlook',
                      DriverDirection.lower =>
                        'Linked with a lower modeled outlook',
                      DriverDirection.flat => 'Little modeled difference',
                      DriverDirection.unavailable =>
                        'Not enough support to compare',
                    }, style: LtText.body(weight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              WholeWordText(driver.displayReason, style: LtText.body()),
            ],
          ),
        ),
      WholeWordText(
        'Modeled differences are links in the data, not proof that changing a habit causes an outcome.',
        style: LtText.body(),
      ),
      const SizedBox(height: 18),
      LipButton(label: 'Explore an experiment', onTap: onExperiment),
      if (onIdeas != null) ...[
        const SizedBox(height: 12),
        LipButton(label: 'See ideas', kind: LipKind.secondary, height: 56, fontSize: 20, onTap: onIdeas),
      ],
    ],
  );
}
