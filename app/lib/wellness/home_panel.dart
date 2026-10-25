import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../twin/twin_model.dart' show extrapolationCaveat;
import '../widgets/whole_word_text.dart';

import '../ui/theme.dart';
import '../ui/widgets/lip_button.dart';
import '../ui/widgets/mode_scaffold.dart' show Sheet;
import '../ui/widgets/rough_guide_badge.dart';
import 'models.dart';
import 'widgets.dart';

/// Home's health score card (design KN-HZ, K-HZ-1): one number (the health index, two decimals),
/// "Healthier than X of 100 people your age", a Higher risk / Average / Better health scale with
/// the marker at the percentile, a circled i that opens the sheet, and a chip into the estimate.
/// The chevron opens "What moves your score". The check-in entry is #58's `CheckInEntry`, mounted
/// by the Room, never a second one here.
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

  /// "What moves your score": the chevron, top right.
  final VoidCallback? onDrivers;

  /// A small state line under the card ("Still learning 2").
  final String? stateLine;

  /// Opens the estimate (the chip).
  final VoidCallback onEstimate;

  static const tagline = 'Feeling good now, and healthy years ahead.';
  static const underAgeLine = 'Health tools start at 18. Until then, play, dress up and chat.';

  @override
  Widget build(BuildContext context) {
    if (snapshot.underAge) {
      return WellnessCard(
        padding: const EdgeInsets.all(14),
        child: HealthScoreSummary(snapshot: snapshot, compact: compact),
      );
    }
    final score = snapshot.displayScore;
    final big = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final percentile = score == null ? null : snapshot.ageGroupPercentile;
    final lifespan = snapshot.lifespanRevealSeen ? snapshot.lifespan : null;
    final chip = _EstimateChip(lifespan: lifespan, onTap: onEstimate);
    final chevron = onDrivers == null
        ? const SizedBox.shrink()
        : IconButton(
            tooltip: 'What moves your score',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              side: const BorderSide(color: LtColors.control, width: LtBorders.control),
            ),
            icon: const Icon(Icons.chevron_right_rounded, color: LtColors.ink, size: 28),
            onPressed: onDrivers,
          );
    final label = Semantics(
      header: true,
      child: WholeWordText(
        'Health score',
        style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
      ),
    );
    final stat = percentile == null
        ? null
        : ExcludeSemantics(
            child: WholeWordText.rich(
              TextSpan(
                style: LtText.body(weight: FontWeight.w700),
                children: [
                  const TextSpan(text: 'Healthier than '),
                  TextSpan(text: '${percentile.round()} of 100', style: LtText.display(22)),
                  const TextSpan(text: ' people your age'),
                ],
              ),
            ),
          );
    final Widget top;
    if (score == null) {
      top = Row(
        children: [
          Expanded(child: label),
          chevron,
        ],
      );
    } else {
      final number = _ScoreNumber(snapshot: snapshot, score: score, size: 40, percentile: percentile);
      top = big
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: label),
                    chevron,
                  ],
                ),
                number,
                if (stat != null) ...[const SizedBox(height: 6), stat],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, number]),
                ),
                if (stat != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 6,
                    child: Padding(padding: const EdgeInsets.only(top: 2), child: stat),
                  ),
                ],
                chevron,
              ],
            );
    }
    final trend = snapshot.history.length >= 2
        ? Expanded(child: ScoreSparkline(values: snapshot.history))
        : const Spacer();
    return WellnessCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          top,
          if (snapshot.roughGuide)
            const Align(alignment: Alignment.centerLeft, child: RoughGuideBadge(caveat: extrapolationCaveat)),
          if (score != null)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 4),
              child: ScoreScale(score: score, percentile: percentile),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 4),
              child: WholeWordText(
                snapshot.status == null || snapshot.message == null ? 'Getting to know you' : snapshot.message!,
                style: LtText.body(weight: FontWeight.w700),
              ),
            ),
          if (!big && score != null)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 2),
              child: WholeWordText(HomeWellnessPanel.tagline, style: LtText.body()),
            ),
          if (stateLine != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: WholeWordText(stateLine!, style: LtText.body()),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 4),
            child: big
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (score != null && snapshot.history.length >= 2) ScoreSparkline(values: snapshot.history),
                      chip,
                    ],
                  )
                : Row(
                    children: [
                      if (score != null) trend else const Spacer(),
                      const SizedBox(width: 8),
                      Flexible(child: chip),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The big number and its circled i (own 48 target, opens [showHealthScoreSheet]). The number
/// reads as one group with the percentile.
class _ScoreNumber extends StatelessWidget {
  const _ScoreNumber({required this.snapshot, required this.score, required this.size, this.percentile});
  final WellnessSnapshot snapshot;
  final double score;
  final double size;
  final double? percentile;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Semantics(
        label: healthScoreSemantics(score, percentile: percentile),
        excludeSemantics: true,
        child: Text(
          formatHealthScore(score),
          style: LtText.display(size, weight: FontWeight.w700),
          maxLines: 1,
          softWrap: false,
        ),
      ),
      IconButton(
        tooltip: 'About the health score',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.info_outline_rounded, color: LtColors.ink, size: 24),
        onPressed: () => showHealthScoreSheet(context, snapshot),
      ),
    ],
  );
}

/// The sheet behind the circled i (K-HZ-2, and K-HZ-4 with the Rough guide badge).
Future<void> showHealthScoreSheet(BuildContext context, WellnessSnapshot snapshot) {
  final score = snapshot.displayScore;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: SingleChildScrollView(
          child: Sheet(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: WholeWordText(
                    score == null ? 'Health score' : 'Health score ${formatHealthScore(score)}',
                    style: LtText.display(28),
                  ),
                ),
                if (snapshot.roughGuide) ...[
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: RoughGuideBadge(caveat: extrapolationCaveat),
                  ),
                ],
                const SizedBox(height: 8),
                WholeWordText(healthScoreSheetBody(snapshot.groupLabel), style: LtText.body()),
                const SizedBox(height: 10),
                WholeWordText(healthScoreSheetNote, style: LtText.body()),
                const SizedBox(height: 10),
                WholeWordText(healthScoreSheetLinked, style: LtText.body(weight: FontWeight.w700)),
                const SizedBox(height: 16),
                LipButton(label: 'Got it', fontSize: 24, onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The chip into the estimate: "Around 2051 ›" once the one-time reveal was seen, otherwise "Your
/// estimate ›", with "Estimate, rough guide" under the year (always, whatever the engine's flag).
class _EstimateChip extends StatelessWidget {
  const _EstimateChip({required this.lifespan, required this.onTap});
  final LifespanReveal? lifespan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = lifespan;
    final label = l == null ? 'Your estimate' : l.yearText;
    return Semantics(
      button: true,
      label: l == null ? 'Your estimate. Open your estimate' : '${l.semantics} Open your estimate',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LtRadii.chip),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: LtColors.paper,
            borderRadius: BorderRadius.circular(LtRadii.chip),
            border: Border.all(color: LtColors.control, width: LtBorders.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: LtText.body(weight: FontWeight.w700)),
                    if (l != null) Text(lifespanCaption, style: LtText.body(color: LtColors.secondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: LtColors.ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// The recent displayed scores as a thin line. Draw it only with at least two points.
class ScoreSparkline extends StatelessWidget {
  const ScoreSparkline({super.key, required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Recent trend of your health score, latest ${formatHealthScore(values.last)}',
    excludeSemantics: true,
    child: SizedBox(height: 28, child: CustomPaint(painter: _SparkPainter(values))),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final span = (hi - lo) < 0.01 ? 0.01 : hi - lo;
    Offset at(int i) =>
        Offset(4 + (size.width - 8) * i / (values.length - 1), 4 + (size.height - 8) * (1 - (values[i] - lo) / span));
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = LtColors.ink,
    );
    canvas.drawCircle(at(values.length - 1), 4, Paint()..color = LtColors.ink);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values;
}

/// The score, its tagline and age-group line, and a "Rough guide" badge when the model
/// extrapolated; under 18 only a quiet info line. Shared by Home and the estimate
/// screen, where it sits above the outlook.
class HealthScoreSummary extends StatelessWidget {
  const HealthScoreSummary({super.key, required this.snapshot, this.compact = false, this.emphasis = false});
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
        Semantics(header: true, child: WholeWordText('Health score', style: LtText.display(compact ? 22 : 25))),
        if (!big) ...[const SizedBox(height: 4), WholeWordText(HomeWellnessPanel.tagline, style: LtText.body())],
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
            children: [
              _ScoreDisc(score: score, percentile: percentile, emphasis: emphasis),
              const SizedBox(height: 10),
              words,
            ],
          )
        else
          Row(
            children: [
              _ScoreDisc(score: score, percentile: percentile, emphasis: emphasis),
              const SizedBox(width: 14),
              Expanded(child: words),
            ],
          ),
        if (score != null) ...[const SizedBox(height: 10), ScoreScale(score: score, percentile: percentile)],
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
  const _ScoreDisc({required this.score, this.percentile, this.emphasis = false});
  final double score;
  final double? percentile;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final text = formatHealthScore(score);
    final size = emphasis ? 136.0 : 104.0;
    return Semantics(
      label: healthScoreSemantics(score, percentile: percentile),
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

/// "Higher risk ‹ · Average · › Better health": a bar with one constant-colour marker. With a
/// [percentile] the marker sits there (58 is 58% along the track, the tick in the middle is the
/// average); without one it falls back to the index on a log scale, clamped to 1/3 to 3.
class ScoreScale extends StatelessWidget {
  const ScoreScale({super.key, required this.score, this.percentile});
  final double score;
  final double? percentile;

  double get markerPosition => percentile == null ? position(score) : (percentile! / 100).clamp(0.0, 1.0);

  /// The index shown at the far right; its inverse is at the far left.
  static const range = 3.0;

  /// 0 (far left, higher risk) to 1 (far right, better health); 0.5 is the index 1.0, the
  /// middle of the age group. Symmetric in log(index), since the index is a ratio.
  static double position(double score) {
    if (!(score > 0)) return 0;
    final r = math.log(range);
    return ((math.log(score).clamp(-r, r) + r) / (2 * r)).toDouble();
  }

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
                  decoration: BoxDecoration(color: LtColors.container, borderRadius: BorderRadius.circular(3)),
                ),
                Positioned(
                  left: box.maxWidth / 2 - 1,
                  child: Container(width: 2, height: 14, color: LtColors.ink),
                ),
                Positioned(
                  key: const ValueKey('score-marker'),
                  left: (box.maxWidth - 16) * markerPosition,
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
            Flexible(child: Text('‹ Higher risk', style: LtText.body())),
            Text('Average', style: LtText.body()),
            Flexible(
              child: Text('Better health ›', style: LtText.body(), textAlign: TextAlign.end),
            ),
          ],
        ),
      ],
    ),
  );
}
