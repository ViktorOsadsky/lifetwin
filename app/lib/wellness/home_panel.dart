import 'package:flutter/material.dart';

import '../twin/twin_model.dart' show extrapolationCaveat;
import '../widgets/whole_word_text.dart';

import '../ui/theme.dart';
import '../ui/widgets/rough_guide_badge.dart';
import 'models.dart';
import 'widgets.dart';

/// Home's health score card (design K-4). The score leads: it sits above any outlook,
/// which stays behind "See your estimate". The check-in entry is #58's `CheckInEntry`,
/// mounted by the Room, never a second one here. No day-dots or weekly counts sit
/// near the score.
class HomeWellnessPanel extends StatelessWidget {
  const HomeWellnessPanel({
    super.key,
    required this.snapshot,
    required this.onEstimate,
    this.onHistory,
    this.compact = false,
  });
  final bool compact;
  final WellnessSnapshot snapshot;
  final VoidCallback? onHistory;
  final VoidCallback onEstimate;

  static const tagline = 'Feeling good now, and healthy years ahead.';
  static const scale = 'Lower is better. 0 is the survey average.';
  static const underAgeLine = 'Health tools start at 18. Until then, play, dress up and chat.';

  @override
  Widget build(BuildContext context) => WellnessCard(
    padding: EdgeInsets.all(compact ? 14 : 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthScoreSummary(snapshot: snapshot, compact: compact),
        // Under 18 there is no estimate; History stays reachable.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (onHistory != null) TextButton(onPressed: onHistory, child: const WholeWordText('My history')),
            if (!snapshot.underAge)
              TextButton(onPressed: onEstimate, child: const WholeWordText('See your estimate')),
          ],
        ),
      ],
    ),
  );
}

/// The score, its tagline and age-group line, and a "Rough guide" badge when the model
/// extrapolated; under 18 only a quiet info line. Shared by Home and the estimate
/// screen, where it sits above the outlook.
class HealthScoreSummary extends StatelessWidget {
  const HealthScoreSummary({super.key, required this.snapshot, this.compact = false});
  final WellnessSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (snapshot.underAge) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 8),
            child: Icon(Icons.info_outline_rounded, color: LtColors.ink, size: 22),
          ),
          Expanded(child: WholeWordText(HomeWellnessPanel.underAgeLine, style: LtText.body())),
        ],
      );
    }
    final big = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final score = snapshot.displayScore;
    final percentile = score == null ? null : snapshot.ageGroupPercentile;
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: WholeWordText('Health score', style: LtText.display(compact ? 22 : 25)),
        ),
        if (!big) ...[
          const SizedBox(height: 4),
          WholeWordText(HomeWellnessPanel.tagline, style: LtText.body()),
        ],
        if (percentile != null) ...[
          const SizedBox(height: 6),
          WholeWordText(
            'Healthier than ${percentile.round()} of 100 people your age',
            style: LtText.body(weight: FontWeight.w700),
          ),
        ],
        const SizedBox(height: 4),
        if (score != null)
          WholeWordText(HomeWellnessPanel.scale, style: LtText.body())
        else
          WholeWordText(
            snapshot.status == null || snapshot.message == null ? 'Getting to know you' : snapshot.message!,
            style: LtText.body(weight: FontWeight.w700),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (score == null)
          words
        else if (big)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_ScoreDisc(score: score), const SizedBox(height: 10), words],
          )
        else
          Row(children: [_ScoreDisc(score: score), const SizedBox(width: 14), Expanded(child: words)]),
        if (snapshot.roughGuide)
          const Align(alignment: Alignment.centerLeft, child: RoughGuideBadge(caveat: extrapolationCaveat)),
      ],
    );
  }
}

/// The score in a mint disc. The number is the model's as is; it is never rescaled,
/// banded or coloured by value.
class _ScoreDisc extends StatelessWidget {
  const _ScoreDisc({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final text = formatHealthScore(score);
    return Semantics(
      label: 'Health score $text',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 104, minHeight: 104),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: LtColors.mint,
          shape: BoxShape.circle,
          border: Border.all(color: LtColors.control, width: LtBorders.control),
        ),
        alignment: Alignment.center,
        child: Text(text, style: LtText.display(36, weight: FontWeight.w700), maxLines: 1, softWrap: false),
      ),
    );
  }
}
