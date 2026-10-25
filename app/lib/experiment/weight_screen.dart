import 'package:flutter/material.dart';

import '../twin/twin_model.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import 'experiment_copy.dart';
import 'experiment_page.dart';
import 'experiment_twins.dart';
import 'widgets/widgets.dart';

/// "About weight" (Y-6): an information card, never a lever. The engine's `bmi` card (CDC
/// guidance, not model output) is shown in short plain words with its source, with no BMI and
/// no number. Height and weight are model inputs and count in today's number; they are left
/// out of what-ifs because the survey cannot show that changing weight helps.
class WeightInfoScreen extends StatelessWidget {
  const WeightInfoScreen({
    super.key,
    required this.appearance,
    required this.card,
    required this.onBack,
    this.onAskMochi,
    this.open = defaultOpenUrl,
  });

  final TwinAppearance appearance;
  final WellnessCard card;
  final VoidCallback onBack;

  /// Opens a short talk with Mochi about weight.
  final VoidCallback? onAskMochi;
  final OpenUrl open;

  @override
  Widget build(BuildContext context) => ExperimentPage(
    mode: LtMode.room,
    onBack: onBack,
    backLabel: ExperimentCopy.backToRoom,
    dock: Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
      child: LipButton(
        label: ExperimentCopy.askMochi,
        icon: Icons.chat_bubble_outline_rounded,
        fontSize: 24,
        onTap: onAskMochi,
      ),
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExperimentPlate(
          appearance: appearance,
          twins: const [TwinSlot(state: steadyTwin, x: 0.3)],
          bubble: 'I can’t test weight changes.',
        ),
        const SizedBox(height: 14),
        Sheet(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(header: true, child: Text(ExperimentCopy.aboutWeight, style: LtText.display(28))),
                  ),
                  Container(
                    constraints: const BoxConstraints(minHeight: 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: LtColors.paper,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: LtColors.control, width: 1.5),
                    ),
                    child: Text(ExperimentCopy.cdcGuidance, style: LtText.body(weight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: LtColors.container, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const LeverIcon(Icons.monitor_weight_outlined, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ExperimentCopy.weightClue, style: LtText.body(size: 18, weight: FontWeight.w700)),
                              Text(ExperimentCopy.weightBody, style: LtText.body(color: LtColors.secondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 52),
                      child: SourceLink(label: ExperimentCopy.weightCdc, url: card.sourceUrl, open: open),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              _WhyNot(),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WhyNot extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Why weight changes are not a what-if',
    excludeSemantics: true,
    onTap: () => _open(context),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            const SizedBox(width: 6),
            const Icon(Icons.info_outline_rounded, size: 22, color: LtColors.ink),
            const SizedBox(width: 6),
            Text(
              ExperimentCopy.whyNot,
              style: LtText.body(weight: FontWeight.w700)
                  .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
            ),
          ],
        ),
      ),
    ),
  );

  void _open(BuildContext context) => showInfoSheet(
    context,
    title: ExperimentCopy.weightNotWhatIf,
    body: ExperimentCopy.weightNotWhatIfBody,
    extra: Text(ExperimentCopy.weightWhyNot, style: LtText.body()),
  );
}
