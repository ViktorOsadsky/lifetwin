import 'package:flutter/widgets.dart';

import '../theme/lifetwin_theme.dart';

/// "Question 3 of 11" with one segment per question (Question.dc.html): done ones
/// filled ink, the current one mint with an ink outline, the rest lavender. The
/// current one differs by outline as well as color.
class LtStepProgress extends StatelessWidget {
  const LtStepProgress({super.key, required this.step, required this.total, this.trailing});

  /// 1-based number of the question being asked.
  final int step;
  final int total;

  /// Shown at the end of the label row (Settings, a small Pip).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final h = big ? 14.0 : 12.0;
    final done = step - 1;
    final label = Text('Question $step of $total', style: LtText.label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (trailing == null)
          label
        else
          // Side by side when they fit; the trailing part wraps below with large text.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [label, trailing!],
          ),
        SizedBox(height: big ? 12 : 10),
        Semantics(
          label: '$done ${done == 1 ? 'question' : 'questions'} done, ${total - step} to go after this one',
          child: ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: Container(
                      height: h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(h / 2),
                        color: i < done
                            ? LtColors.ink
                            : i == done
                            ? LtColors.mint
                            : LtColors.lavenderTrack,
                        border: i == done ? Border.all(color: LtColors.ink, width: 2.5) : null,
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
