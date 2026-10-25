import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../experiment/ideas_hub.dart' show IdeasScope;
import '../experiment/widgets/idea_scene.dart' show IdeasLinkRow;
import '../onboarding/missing_answers.dart';
import '../twin/twin_model.dart' show extrapolationCaveat;
import '../widgets/whole_word_text.dart';

import '../ui/theme.dart';
import '../ui/widgets/lip_button.dart';
import '../ui/widgets/mode_scaffold.dart' show Sheet;
import '../ui/widgets/rough_guide_badge.dart';
import 'models.dart';
import 'widgets.dart';

/// Home's health score card (design KN-HZ, K-HZ-1): one number (the signed health score, two decimals),
/// "Healthier than X of 100 people your age", a Higher risk / Average / Better health scale with
/// the marker at the percentile, a circled i that opens the sheet, and a chip into the estimate.
/// The chevron opens "What moves your score". The check-in entry is #58's `CheckInEntry`, mounted
/// by the Room, never a second one here.
class HomeWellnessPanel extends StatelessWidget {
  const HomeWellnessPanel({
    super.key,
    required this.snapshot,
    this.onEstimate,
    this.onHistory,
    this.onDrivers,
    this.stateLine,
    this.compact = false,
    this.onCollapse,
    this.onAnswerMissing,
  });
  final bool compact;

  /// Collapses the card to the score chip (the chevron at the card's bottom right). Null: no collapse button.
  final VoidCallback? onCollapse;

  /// "Answer N more questions" ([WellnessSnapshot.missingCount]): the one path back to the
  /// missing answers, under a rough score or in place of the number. Hidden when null.
  final VoidCallback? onAnswerMissing;
  final WellnessSnapshot snapshot;
  final VoidCallback? onHistory;

  /// "What moves your score": the chevron, top right.
  final VoidCallback? onDrivers;

  /// A small state line under the card ("Still learning 2").
  final String? stateLine;

  /// Opens the estimate (the chip). Null: the chip is display only.
  final VoidCallback? onEstimate;

  static const tagline = 'Feeling good now, and healthy years ahead.';
  static const underAgeLine = 'The health score is made for adults, ages 18 and over.';

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
    final collapse = onCollapse == null || score == null
        ? null
        : IconButton(
            tooltip: 'Collapse health score',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.keyboard_arrow_up_rounded, color: LtColors.ink, size: 28),
            onPressed: onCollapse,
          );
    final label = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      children: [
        Semantics(
          header: true,
          child: WholeWordText(
            'Health score',
            style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
          ),
        ),
        if (stateLine != null) WholeWordText(stateLine!, style: LtText.body()),
      ],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          number,
                          if (stat != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Padding(padding: const EdgeInsets.only(top: 2), child: stat),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // A little air, so "91 of 100" never touches the chevron's ring.
                const SizedBox(width: 6),
                chevron,
              ],
            );
    }
    final trend = snapshot.history.length >= 2
        ? Expanded(child: ScoreSparkline(values: snapshot.history))
        : const Spacer();
    return WellnessCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          top,
          if (snapshot.roughGuide)
            const Align(
              alignment: Alignment.centerLeft,
              child: RoughGuideBadge(caveat: extrapolationCaveat),
            ),
          if (snapshot.roughMissing && snapshot.missingCount > 0)
            WholeWordText(roughMissingLabel(snapshot.missingCount), style: LtText.body(weight: FontWeight.w700)),
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
              padding: const EdgeInsets.only(right: 6),
              child: WholeWordText(HomeWellnessPanel.tagline, style: LtText.body()),
            ),
          if (onAnswerMissing != null && snapshot.missingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 6),
              child: LipButton(
                label: answerMoreLabel(snapshot.missingCount),
                icon: Icons.mic_none_rounded,
                height: 52,
                fontSize: 19,
                onTap: onAnswerMissing,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 4),
            // The collapse chevron shares the estimate chip's row, so collapsing costs the card no height.
            child: _withCollapse(
              collapse,
              // The Home card is compact: the chip only (design K-HZ-1 has no trend line).
              compact
                  ? Align(alignment: Alignment.centerLeft, child: chip)
                  : big
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
          ),
        ],
      ),
    );
  }

  static Widget _withCollapse(Widget? collapse, Widget row) => collapse == null
      ? row
      : Row(
          children: [
            Expanded(child: row),
            collapse,
          ],
        );
}

/// Home's score card that can shrink to a chip ("+0.53 ▾") so the room shows. The state is kept per
/// device (shared_preferences); with nothing stored (first launch after onboarding) it starts
/// expanded, so the reveal lands. Under 18, or with no score yet, there is nothing to collapse.
class CollapsibleHealthScore extends StatefulWidget {
  const CollapsibleHealthScore({
    super.key,
    required this.snapshot,
    this.onEstimate,
    this.onDrivers,
    this.stateLine,
    this.onAnswerMissing,
  });
  final WellnessSnapshot snapshot;
  final VoidCallback? onEstimate;
  final VoidCallback? onDrivers;
  final String? stateLine;

  /// "Answer N more questions", in the expanded card (the collapsed chip shows "Rough guide").
  final VoidCallback? onAnswerMissing;

  static const prefsKey = 'home_score_collapsed';

  /// "Delete my data": the folded-away choice goes too, as on a fresh install.
  static Future<void> forget() async => (await SharedPreferences.getInstance()).remove(prefsKey);
  static const duration = Duration(milliseconds: 200);

  @override
  State<CollapsibleHealthScore> createState() => _CollapsibleHealthScoreState();
}

class _CollapsibleHealthScoreState extends State<CollapsibleHealthScore> {
  bool _collapsed = false;

  /// The restored state is applied without animation.
  bool _instant = false;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getBool(CollapsibleHealthScore.prefsKey);
      if (!mounted || _touched || saved == null || saved == _collapsed) return;
      setState(() {
        _collapsed = saved;
        _instant = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _instant = false);
      });
    } catch (_) {
      // No local storage (a test, a private mode): the card just starts expanded.
    }
  }

  Future<void> _set(bool collapsed) async {
    if (collapsed == _collapsed) return;
    _touched = true;
    setState(() => _collapsed = collapsed);
    try {
      await (await SharedPreferences.getInstance()).setBool(CollapsibleHealthScore.prefsKey, collapsed);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;
    final score = snap.displayScore;
    final panel = HomeWellnessPanel(
      key: const ValueKey('score-expanded'),
      snapshot: snap,
      compact: true,
      onEstimate: widget.onEstimate,
      onDrivers: widget.onDrivers,
      stateLine: widget.stateLine,
      onCollapse: () => _set(true),
      onAnswerMissing: widget.onAnswerMissing,
    );
    if (snap.underAge || score == null) return panel;
    final instant = MediaQuery.disableAnimationsOf(context) || _instant;
    final shown = _collapsed
        ? _CollapsedScoreChip(
            key: const ValueKey('score-collapsed'),
            snapshot: snap,
            score: score,
            onTap: () => _set(false),
          )
        : panel;
    return SizeChangedLayoutNotifier(
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onVerticalDragEnd: (e) {
          if (!_collapsed && (e.primaryVelocity ?? 0) < -250) _set(true);
        },
        // Reduced motion (and the restored state) switches at once: no animation widgets at all.
        child: instant
            ? shown
            : AnimatedSize(
                duration: CollapsibleHealthScore.duration,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: CollapsibleHealthScore.duration,
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                  child: shown,
                ),
              ),
      ),
    );
  }
}

/// The collapsed card: the signed score and a chevron, in the card's own paper, border and shadow.
class _CollapsedScoreChip extends StatelessWidget {
  const _CollapsedScoreChip({super.key, required this.snapshot, required this.score, required this.onTap});
  final WellnessSnapshot snapshot;
  final double score;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Semantics(
            button: true,
            label: 'Health score ${spokenHealthScore(score)}, collapsed. Tap to expand.',
            excludeSemantics: true,
            onTap: onTap,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(LtRadii.chip),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.only(left: 14, right: 6),
                  decoration: BoxDecoration(
                    color: LtColors.paper,
                    borderRadius: BorderRadius.circular(LtRadii.chip),
                    border: Border.all(color: LtColors.container, width: LtBorders.container),
                    boxShadow: LtShadows.small,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatHealthScore(score),
                        style: LtText.display(26, weight: FontWeight.w700),
                        maxLines: 1,
                        softWrap: false,
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: LtColors.ink, size: 28),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (snapshot.roughGuide) const RoughGuideBadge(caveat: extrapolationCaveat),
          // A rough score with answers missing: "Rough guide"; tapping it opens the card, where
          // "Answer N more questions" is.
          if (snapshot.roughMissing && snapshot.missingCount > 0)
            RoughGuideBadge(caveat: roughMissingLabel(snapshot.missingCount), onTap: onTap, expanded: false),
        ],
      ),
    ),
  );
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
                // A way into Ideas for you: only with today's ideas on hand (never under 18).
                if (IdeasScope.maybeOf(context) case final access?)
                  ListenableBuilder(
                    listenable: access.hub,
                    builder: (sheet, _) => (access.hub.response?.recommendations.isEmpty ?? true)
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: IdeasLinkRow(
                              label: 'Ideas linked to a healthier score',
                              onTap: () {
                                Navigator.of(sheet).pop();
                                access.openList(context, origin: 'score');
                              },
                            ),
                          ),
                  ),
                const SizedBox(height: 16),
                LipButton(
                  label: 'Got it',
                  fontSize: 24,
                  kind: LipKind.secondary,
                  onTap: () => Navigator.of(context).pop(),
                ),
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = lifespan;
    final label = l == null ? 'Your estimate' : l.yearText;
    return Semantics(
      button: onTap != null,
      label: l == null
          ? (onTap == null ? 'Your estimate' : 'Your estimate. Open your estimate')
          : (onTap == null ? l.semantics : '${l.semantics} Open your estimate'),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LtRadii.chip),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              // The chevron carries its own space on the right; without it the label needs the same room.
              padding: EdgeInsets.only(left: 12, right: onTap == null ? 12 : 4),
              decoration: BoxDecoration(
                color: LtColors.paper,
                borderRadius: BorderRadius.circular(LtRadii.chip),
                border: Border.all(color: LtColors.control, width: LtBorders.control),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(label, style: LtText.body(weight: FontWeight.w700)),
                  ),
                  if (onTap != null) const Icon(Icons.chevron_right_rounded, color: LtColors.ink),
                ],
              ),
            ),
            if (l != null) Text(lifespanCaption, style: LtText.body(color: LtColors.secondary)),
          ],
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
        if (snapshot.roughMissing && snapshot.missingCount > 0)
          WholeWordText(roughMissingLabel(snapshot.missingCount), style: LtText.body(weight: FontWeight.w700)),
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
/// average); without one it falls back to the centred score itself, clamped to -ln 3 .. +ln 3.
class ScoreScale extends StatelessWidget {
  const ScoreScale({super.key, required this.score, this.percentile});
  final double score;
  final double? percentile;

  double get markerPosition => percentile == null ? position(score) : (percentile! / 100).clamp(0.0, 1.0);

  /// The score shown at the far right; its negative is at the far left (an index of 3 and 1/3).
  static final double range = math.log(3);

  /// 0 (far left, higher risk) to 1 (far right, better health); 0.5 is the score 0, the middle of
  /// the age group.
  static double position(double score) {
    if (score.isNaN) return 0.5;
    return ((score.clamp(-range, range) + range) / (2 * range)).toDouble();
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
        // OverflowBar also supports intrinsic sizing: this scale appears in the
        // score explanation sheet as well as Home. Keep whole labels together
        // and stack them before a narrow row can break words into letters.
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          spacing: 8,
          overflowAlignment: OverflowBarAlignment.center,
          children: [
            for (final label in ['‹ Higher risk', 'Average', 'Better health ›'])
              IntrinsicWidth(child: Text(label, style: LtText.body())),
          ],
        ),
      ],
    ),
  );
}
