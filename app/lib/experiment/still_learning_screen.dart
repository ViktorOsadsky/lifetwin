import 'package:flutter/material.dart';

import '../onboarding/missing_answers.dart';
import '../twin/twin_model.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import '../widgets/whole_word_text.dart';
import 'answers.dart';
import 'experiment_copy.dart';
import 'experiment_page.dart';
import 'experiment_twins.dart';
import 'widgets/widgets.dart';

/// "Still learning" (Y-13, from the Room) and "Almost ready" (Y-8, from the Experiment): the
/// answers the model still needs, from `missingInputs` in plain words (never a default, never an
/// input field). "Tell Mochi" opens a short conversation with Mochi (ask, read back, save).
/// "What I know" lists the answers already kept, each with "Change", which opens the same
/// conversation for that one answer.
class StillLearningScreen extends StatefulWidget {
  const StillLearningScreen({
    super.key,
    required this.appearance,
    required this.assessment,
    required this.known,
    required this.onBack,
    this.onTellMochi,
    this.onAnswerMissing,
    this.questionCount,
    this.almostReady = false,
  });

  /// The questions [onAnswerMissing] asks (height and weight are two); the missing inputs when null.
  final int? questionCount;

  /// "Answer N more questions": Mochi asks only the missing answers. When set and something is
  /// missing, it is the dock's one primary action (instead of the open "Tell Mochi").
  final VoidCallback? onAnswerMissing;

  final TwinAppearance appearance;

  /// The person's own result; its `missingInputs` are the rows. With no profile at all every
  /// model input is still needed.
  final TwinAssessment assessment;

  /// (model input, answer in words) pairs already known, for "What I know".
  final List<(String, String)> known;
  final VoidCallback onBack;

  /// `field` null: Mochi asks what is still needed.
  final void Function(String? field)? onTellMochi;

  /// Y-8: shown from the Experiment, without "What I know".
  final bool almostReady;

  @override
  State<StillLearningScreen> createState() => _StillLearningScreenState();
}

class _StillLearningScreenState extends State<StillLearningScreen> {
  bool _knownOpen = false;

  @override
  Widget build(BuildContext context) {
    final missing = widget.assessment.missingInputs;
    final n = missing.length;
    final almost = widget.almostReady;
    return ExperimentPage(
      mode: LtMode.room,
      onBack: widget.onBack,
      backLabel: almost ? 'Back to Experiment' : 'Back to room',
      dock: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
        child: n > 0 && widget.onAnswerMissing != null
            ? LipButton(
                label: answerMoreLabel(widget.questionCount ?? n),
                icon: Icons.mic_none_rounded,
                fontSize: 24,
                onTap: widget.onAnswerMissing,
              )
            : LipButton(
                label: ExperimentCopy.tellMochi,
                icon: Icons.mic_none_rounded,
                fontSize: 24,
                onTap: widget.onTellMochi == null ? null : () => widget.onTellMochi!(null),
              ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: widget.appearance,
            twins: const [TwinSlot(state: curiousTwin, x: 0.3)],
            bubble: n == 0
                ? 'Ask me anything!'
                : almost
                ? (n == 1 ? 'One answer, then let’s go!' : 'Two answers, then let’s go!')
                : (n == 1 ? 'One more thing about you?' : 'Two more things about you?'),
          ),
          const SizedBox(height: 14),
          Sheet(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          almost ? ExperimentCopy.almostReady : ExperimentCopy.stillLearning,
                          style: LtText.display(28),
                        ),
                      ),
                    ),
                    DashedBox(
                      color: LtColors.control,
                      radius: 16,
                      fill: LtColors.paper,
                      constraints: const BoxConstraints(minHeight: 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          almost ? ExperimentCopy.stillLearning : ExperimentCopy.toGo(n),
                          style: LtText.body(weight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                WholeWordText(
                  almost ? ExperimentCopy.firstINeed : ExperimentCopy.onceIKnow,
                  style: almost ? LtText.body(weight: FontWeight.w700) : LtText.body(color: LtColors.secondary),
                ),
                const SizedBox(height: 8),
                for (final m in missing) ...[
                  NoNumberBox(icon: Icons.help_outline_rounded, title: Answers.label(m)),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded, size: 20, color: LtColors.ink),
                    const SizedBox(width: 8),
                    Expanded(child: WholeWordText(ExperimentCopy.notSure, style: LtText.body())),
                  ],
                ),
                if (!almost && widget.known.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _KnownRow(
                    count: widget.known.length,
                    open: _knownOpen,
                    onTap: () => setState(() => _knownOpen = !_knownOpen),
                  ),
                  if (_knownOpen)
                    for (final (key, text) in widget.known)
                      _KnownAnswer(
                        label: Answers.label(key),
                        text: text,
                        onChange: widget.onTellMochi == null
                            ? null
                            : () => widget.onTellMochi!(Answers.changeField(key)),
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

class _KnownRow extends StatelessWidget {
  const _KnownRow({required this.count, required this.open, required this.onTap});
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    expanded: open,
    label: 'What I already know, $count answers. Each has a Change button that talks it through with Mochi.',
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: LtColors.control, width: LtBorders.control),
        ),
        child: Row(
          children: [
            const LeverIcon(Icons.check_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(ExperimentCopy.whatIKnow(count), style: LtText.body(size: 18, weight: FontWeight.w700)),
            ),
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 28, color: LtColors.ink),
          ],
        ),
      ),
    ),
  );
}

class _KnownAnswer extends StatelessWidget {
  const _KnownAnswer({required this.label, required this.text, required this.onChange});
  final String label;
  final String text;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WholeWordText(label, style: LtText.body(weight: FontWeight.w700)),
              if (text.isNotEmpty) WholeWordText(text, style: LtText.body(color: LtColors.secondary)),
            ],
          ),
        ),
        if (onChange != null) ChangeButton(label: 'Change $label with Mochi', onTap: onChange!),
      ],
    ),
  );
}

/// "Change": there is no edit field; this opens a short talk with Mochi (ask, read back, save).
class ChangeButton extends StatelessWidget {
  const ChangeButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: LtColors.control, width: LtBorders.control),
          boxShadow: LtShadows.small,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 20, color: LtColors.ink),
            const SizedBox(width: 6),
            Text(ExperimentCopy.change, style: LtText.body(weight: FontWeight.w700)),
          ],
        ),
      ),
    ),
  );
}
