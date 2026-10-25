import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../widgets/whole_word_text.dart';
import '../theme.dart';

/// "Question 3 of 12" with one segment per question: done ones filled ink, the
/// current one a wide mint pill, the rest outlined. Stays put until the answer
/// is confirmed.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.step, required this.total});

  /// 1-based number of the question being asked.
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final done = step - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WholeWordText('Question $step of $total', style: LtText.body(size: 18, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Semantics(
          label: '$done ${done == 1 ? 'question' : 'questions'} done, ${total - step} to go after this one',
          child: ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    flex: i == done ? 3 : 1,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: i < done ? LtColors.ink : (i == done ? LtColors.mint : LtColors.paper),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: i < done ? LtColors.ink : (i == done ? LtColors.controlOnMint : LtColors.control),
                          width: LtBorders.control,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "✓ Question 3 saved": the question just answered, shown as done from the moment the
/// answer is sent until the next one, so the person sees it was taken before moving on.
class SavedMark extends StatelessWidget {
  const SavedMark({super.key, required this.number, this.word = 'saved'});

  final int number;

  /// "saved" (onboarding keeps it now) or "done" (a check-in keeps it once finished).
  final String word;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Question $number $word',
      child: ExcludeSemantics(
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 28, color: LtColors.ink),
            const SizedBox(width: 8),
            Flexible(
              child: WholeWordText('Question $number $word', style: LtText.body(size: 20, weight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
