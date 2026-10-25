import 'package:flutter/material.dart';

import '../twin/twin_model.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart' hide TwinMood;
import '../widgets/whole_word_text.dart';
import '../twin/twin_state.dart';
import 'answers.dart';
import 'experiment_copy.dart';
import 'experiment_page.dart';
import 'still_learning_screen.dart';
import 'wellness_panel.dart';
import 'widgets/widgets.dart';

/// "Outside my range" (Y-9): the age is under 30 or over 85, so there is no number anywhere.
/// The wellness cards still show what is going well, with their CDC links: guidance, not model output.
class OutsideRangeScreen extends StatelessWidget {
  const OutsideRangeScreen({
    super.key,
    required this.appearance,
    required this.cards,
    required this.onBack,
    this.open = defaultOpenUrl,
  });

  final TwinAppearance appearance;
  final List<WellnessCard> cards;
  final VoidCallback onBack;
  final OpenUrl open;

  @override
  Widget build(BuildContext context) => ExperimentPage(
    mode: LtMode.room,
    onBack: onBack,
    backLabel: ExperimentCopy.backToRoom,
    dock: _RoomDock(onTap: onBack),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExperimentPlate(
          appearance: appearance,
          twins: const [
            TwinSlot(
              state: TwinState(mood: TwinMood.content, pose: TwinPose.wave, reason: TwinStateReason.needsInput),
              x: 0.3,
            ),
          ],
          bubble: 'So glad you’re here!',
        ),
        const SizedBox(height: 14),
        Sheet(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(ExperimentCopy.outsideRange, style: LtText.display(28))),
              const SizedBox(height: 8),
              const NoNumberBox(
                icon: Icons.info_outline_rounded,
                title: ExperimentCopy.beyondNumbers,
                body: ExperimentCopy.ageRange,
              ),
              WellnessPanel(cards: cards, strengthsOnly: true, open: open),
            ],
          ),
        ),
      ],
    ),
  );
}

/// "Rare answers" (Y-10): the model withholds a number because an answer is rarer than almost
/// anyone in its survey. The person's own answer is echoed (not a model number) so a typo can be
/// fixed: "Change" opens a short talk with Mochi, never an edit field.
class RareAnswersScreen extends StatelessWidget {
  const RareAnswersScreen({
    super.key,
    required this.appearance,
    required this.assessment,
    required this.onBack,
    this.onChange,
  });

  final TwinAppearance appearance;
  final TwinAssessment assessment;
  final VoidCallback onBack;
  final void Function(String? field)? onChange;

  @override
  Widget build(BuildContext context) {
    final field = Answers.issueField(assessment.supportIssues) ?? assessment.invalidInput;
    final value = field == null ? null : Answers.text(field, assessment.profileUsed[field]);
    return ExperimentPage(
      mode: LtMode.room,
      onBack: onBack,
      backLabel: ExperimentCopy.backToRoom,
      dock: _RoomDock(onTap: onBack),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: appearance,
            twins: const [
              TwinSlot(
                state: TwinState(mood: TwinMood.cheerful, pose: TwinPose.jump, reason: TwinStateReason.active),
                x: 0.3,
              ),
            ],
            bubble: 'Wow, you’re super active!',
          ),
          const SizedBox(height: 14),
          Sheet(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: Text(ExperimentCopy.rareAnswers, style: LtText.display(28))),
                const SizedBox(height: 8),
                const NoNumberBox(
                  icon: Icons.star_border_rounded,
                  title: ExperimentCopy.tooRareToEstimate,
                  body: ExperimentCopy.rareBody,
                ),
                if (field != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                    decoration: BoxDecoration(
                      color: LtColors.paper,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: LtColors.container, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const LeverIcon(Icons.directions_run_rounded, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              WholeWordText(
                                Answers.label(field).replaceAll(' each week', ''),
                                style: LtText.body(weight: FontWeight.w700),
                              ),
                              if (value != null) WholeWordText(value, style: LtText.body(color: LtColors.secondary)),
                            ],
                          ),
                        ),
                        if (onChange != null)
                          ChangeButton(
                            label: 'Change ${Answers.label(field).toLowerCase()} answer with Mochi',
                            onTap: () => onChange!(Answers.changeField(field)),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomDock extends StatelessWidget {
  const _RoomDock({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
    child: LipButton(label: ExperimentCopy.backToRoom, icon: Icons.home_rounded, fontSize: 24, onTap: onTap),
  );
}
