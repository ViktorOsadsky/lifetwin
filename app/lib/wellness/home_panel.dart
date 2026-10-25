import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../twin/twin_model.dart' show extrapolationCaveat;
import '../widgets/whole_word_text.dart';

import '../ui/theme.dart';
import '../ui/widgets/rough_guide_badge.dart';
import 'models.dart';
import 'widgets.dart';

/// Home's health score card (design K-4), compact: a ring gauge on the higher = better scale with the
/// signed number inside, the age-group line with a thin percentile bar, the recent trend, and one chip into
/// the estimate. "What moves it" is the circled i at the top right. The check-in entry is #58's
/// `CheckInEntry`, mounted by the Room, never a second one here.
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

  /// "What moves your score": the circled i, top right.
  final VoidCallback? onDrivers;

  /// A small state line under the card ("Still learning 2").
  final String? stateLine;

  /// Opens the estimate (the chip).
  final VoidCallback onEstimate;

  static const tagline = 'Feeling good now, and healthy years ahead.';
  static const underAgeLine =
      'Health tools start at 18. Until then, play, dress up and chat.';

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
    final chip = _EstimateChip(
      label: lifespan == null ? 'Your estimate' : 'Around ${lifespan.expectedYear}',
      onTap: onEstimate,
    );
    final info = onDrivers == null
        ? const SizedBox.shrink()
        : IconButton(
            tooltip: 'What moves your score',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: EdgeInsets.zero,
            icon: Semantics(
              label: 'What moves your score',
              excludeSemantics: true,
              child: const Icon(Icons.info_outline_rounded, color: LtColors.ink, size: 28),
            ),
            onPressed: onDrivers,
          );
    final title = Row(
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              Semantics(
                header: true,
                child: WholeWordText('Health score', style: LtText.display(22)),
              ),
              if (compact && stateLine != null) WholeWordText(stateLine!, style: LtText.body(size: 15)),
            ],
          ),
        ),
        info,
      ],
    );
    final facts = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (score != null)
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text('‹ Higher risk', style: LtText.body(size: 15))),
                Flexible(child: Text('Better health ›', style: LtText.body(size: 15), textAlign: TextAlign.end)),
              ],
            ),
          ),
        if (percentile != null) ...[
          WholeWordText(
            'Healthier than ${percentile.round()} of 100 people your age',
            style: LtText.body(size: 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          PercentileBar(percent: percentile),
        ] else if (score == null)
          WholeWordText(
            snapshot.status == null || snapshot.message == null ? 'Getting to know you' : snapshot.message!,
            style: LtText.body(weight: FontWeight.w700),
          ),
      ],
    );
    final trend = snapshot.history.length >= 2
        ? Expanded(child: ScoreSparkline(values: snapshot.history))
        : const Spacer();
    return WellnessCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          if (!big && !compact && score != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: WholeWordText(HomeWellnessPanel.tagline, style: LtText.body(size: 15)),
            ),
          if (score == null)
            Padding(padding: const EdgeInsets.only(right: 8), child: facts)
          else if (big)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [ScoreRing(score: score), const SizedBox(height: 6), facts],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ScoreRing(score: score),
                  const SizedBox(width: 12),
                  Expanded(child: facts),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                if (score != null) trend else const Spacer(),
                const SizedBox(width: 8),
                Flexible(child: chip),
              ],
            ),
          ),
          if (snapshot.roughGuide)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Align(alignment: Alignment.centerLeft, child: RoughGuideBadge(caveat: extrapolationCaveat)),
            ),
          if (!compact && stateLine != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: WholeWordText(stateLine!, style: LtText.body(size: 15)),
            ),
        ],
      ),
    );
  }
}

/// The chip into the estimate: "Around 2051 ›" once the one-time reveal was seen, otherwise "Your estimate ›".
class _EstimateChip extends StatelessWidget {
  const _EstimateChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label. Open your estimate',
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LtRadii.chip),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(LtRadii.chip),
          border: Border.all(color: LtColors.control, width: LtBorders.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: LtText.body(size: 16, weight: FontWeight.w700), maxLines: 1, softWrap: false),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: LtColors.ink),
          ],
        ),
      ),
    ),
  );
}

/// A ring gauge on the higher = better scale: the arc runs from "Higher risk" (start, bottom left) to
/// "Better health" (end, bottom right), the dot sits where the score falls (clamped to -3..+3), and the
/// signed number is inside. No colour by value.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score, this.size = 84});
  final double score;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: healthScoreSemantics(score),
    excludeSemantics: true,
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(ScoreScale.position(score)),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatHealthScore(score),
                style: LtText.display(26, weight: FontWeight.w700),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t);
  final double t;

  static const _start = 0.75 * math.pi; // bottom left
  static const _sweep = 1.5 * math.pi; // over the top to bottom right

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 9;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r - 5, Paint()..color = LtColors.mint);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = LtColors.container;
    canvas.drawArc(rect, _start, _sweep, false, track);
    canvas.drawArc(rect, _start, _sweep * t, false, track..color = LtColors.ink);
    // The average tick at the top, then the marker.
    final avg = _start + _sweep / 2;
    canvas.drawLine(
      c + Offset(math.cos(avg), math.sin(avg)) * (r - 8),
      c + Offset(math.cos(avg), math.sin(avg)) * (r + 8),
      Paint()
        ..color = LtColors.ink
        ..strokeWidth = 2,
    );
    final a = _start + _sweep * t;
    final m = c + Offset(math.cos(a), math.sin(a)) * r;
    canvas.drawCircle(m, 8, Paint()..color = LtColors.paper);
    canvas.drawCircle(m, 6, Paint()..color = LtColors.ink);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}

/// A thin bar filled to the age-group percentile (0..100).
class PercentileBar extends StatelessWidget {
  const PercentileBar({super.key, required this.percent});
  final double percent;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: LtColors.container)),
            FractionallySizedBox(
              widthFactor: (percent / 100).clamp(0.0, 1.0),
              child: const ColoredBox(color: LtColors.ink),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The recent displayed scores as a thin line. Draw it only with at least two points.
class ScoreSparkline extends StatelessWidget {
  const ScoreSparkline({super.key, required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Recent trend of your health score',
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
    Offset at(int i) => Offset(
      4 + (size.width - 8) * i / (values.length - 1),
      4 + (size.height - 8) * (1 - (values[i] - lo) / span),
    );
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
