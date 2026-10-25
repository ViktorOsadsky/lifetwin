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
    this.onDrivers,
    this.stateLine,
    this.compact = false,
  });
  final bool compact;
  final WellnessSnapshot snapshot;
  final VoidCallback? onHistory;

  /// "What moves it": the outlook's drivers.
  final VoidCallback? onDrivers;

  /// A small state line under the score ("Still learning 2").
  final String? stateLine;
  final VoidCallback onEstimate;

  static const tagline = 'Feeling good now, and healthy years ahead.';
  static const underAgeLine =
      'Health tools start at 18. Until then, play, dress up and chat.';

  @override
  Widget build(BuildContext context) => WellnessCard(
    padding: EdgeInsets.all(compact ? 14 : 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthScoreSummary(snapshot: snapshot, compact: compact),
        if (stateLine != null) WholeWordText(stateLine!, style: LtText.body(size: 15)),
        // Under 18 there is no estimate; History stays reachable.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (onHistory != null) TextButton(onPressed: onHistory, child: const WholeWordText('My history')),
            if (!snapshot.underAge && onDrivers != null)
              TextButton(onPressed: onDrivers, child: const WholeWordText('What moves it')),
            if (!snapshot.underAge)
              TextButton(
                onPressed: onEstimate,
                child: const WholeWordText('See your estimate'),
              ),
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
  const HealthScoreSummary({
    super.key,
    required this.snapshot,
    this.compact = false,
    this.emphasis = false,
  });
  final WellnessSnapshot snapshot;
  final bool compact;

  /// The reveal after onboarding: the disc is larger.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    if (snapshot.underAge) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 8),
            child: Icon(
              Icons.info_outline_rounded,
              color: LtColors.ink,
              size: 22,
            ),
          ),
          Expanded(
            child: WholeWordText(
              HomeWellnessPanel.underAgeLine,
              style: LtText.body(),
            ),
          ),
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
          child: WholeWordText(
            'Health score',
            style: LtText.display(compact ? 22 : 25),
          ),
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
        if (score == null)
          WholeWordText(
            snapshot.status == null || snapshot.message == null
                ? 'Getting to know you'
                : snapshot.message!,
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
            children: [
              _ScoreDisc(score: score, emphasis: emphasis),
              const SizedBox(height: 10),
              words,
            ],
          )
        else
          Row(
            children: [
              _ScoreDisc(score: score, emphasis: emphasis),
              const SizedBox(width: 14),
              Expanded(child: words),
            ],
          ),
        if (score != null) ...[
          const SizedBox(height: 10),
          ScoreScale(score: score),
        ],
        if (snapshot.roughGuide)
          const Align(
            alignment: Alignment.centerLeft,
            child: RoughGuideBadge(caveat: extrapolationCaveat),
          ),
      ],
    );
  }
}

/// The score in a mint disc. The number is the repository's as is (higher is better); it is never
/// rescaled, banded or coloured by value.
class _ScoreDisc extends StatelessWidget {
  const _ScoreDisc({required this.score, this.emphasis = false});
  final double score;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final text = formatHealthScore(score);
    final size = emphasis ? 136.0 : 104.0;
    return Semantics(
      label: healthScoreSemantics(score),
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(minWidth: size, minHeight: size),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: LtColors.mint,
          shape: BoxShape.circle,
          border: Border.all(color: LtColors.control, width: LtBorders.control),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: LtText.display(emphasis ? 44 : 36, weight: FontWeight.w700),
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

/// "Higher risk ‹ · Average · › Better health": a bar with the marker where the score falls (clamped
/// to the model's usual -3 to +3), no colour by value.
class ScoreScale extends StatelessWidget {
  const ScoreScale({super.key, required this.score});
  final double score;

  static const range = 3.0;

  /// 0 (far left, higher risk) to 1 (far right, better health); 0.5 is average.
  static double position(double score) =>
      ((score.clamp(-range, range) + range) / (2 * range)).toDouble();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 18,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: LtColors.container,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Positioned(
                  left: box.maxWidth / 2 - 1,
                  child: Container(width: 2, height: 14, color: LtColors.ink),
                ),
                Positioned(
                  key: const ValueKey('score-marker'),
                  left: (box.maxWidth - 16) * position(score),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: LtColors.ink,
                      shape: BoxShape.circle,
                      border: Border.all(color: LtColors.paper, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text('‹ Higher risk', style: LtText.body(size: 15)),
            ),
            Text('Average', style: LtText.body(size: 15)),
            Flexible(
              child: Text(
                'Better health ›',
                style: LtText.body(size: 15),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
