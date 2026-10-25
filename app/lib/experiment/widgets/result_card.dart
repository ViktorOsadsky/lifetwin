import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../ui/widgets/lottie_burst.dart';
import '../../ui/widgets/rough_guide_badge.dart';
import '../../widgets/whole_word_text.dart';
import '../../wellness/models.dart'
    show ScoreChange, formatHealthScore, formatScoreDelta, newScoreSemantics, scoreChangeOf;
import '../experiment_copy.dart';
import '../result_display.dart';
import 'bear_array.dart';
import 'info_sheet.dart';
import 'no_number_box.dart';
import 'pills.dart';

/// "Modeled difference between profiles": one result for the whole what-if (or, with
/// [title] "Just this change", for one lever alone). It switches on the engine status:
///
/// - big (1.0 or more): "About 4 more in 100" and two 10 by 10 bear arrays;
/// - tiny: "Less than 1 more in 100", an (i) with the exact figure, no arrays;
/// - same / lower: words only;
/// - nothing moved, not counted, no number, too many hours: a dashed box and no number.
///
/// With [summary] only the headline shows (the hub). A "Rough guide" badge sits beside any number
/// the model extrapolated; tapping it opens the engine's caveat inline.
class ResultCard extends StatefulWidget {
  const ResultCard({
    super.key,
    required this.display,
    required this.leverName,
    this.title = ExperimentCopy.heroTitle,
    this.gainNote = 'with these changes',
    this.summary,
    this.celebrate = false,
    this.currentScore,
    this.scoreDelta,
  });

  final ResultDisplay display;
  final String Function(String id) leverName;
  final String title;

  /// After the count of gained bears: "4 more, [with all 4 changes]".
  final String gainNote;

  /// Hub: a line under the headline ("All 4 changes together"); no arrays or boxes.
  final String? summary;

  /// A soft glow behind the headline when the outlook updates.
  final bool celebrate;

  /// The health index today and the what-if's difference (`scoreDelta`). The line shows only
  /// with both, on a number result.
  final double? currentScore;
  final double? scoreDelta;

  @override
  State<ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<ResultCard> {
  bool _caveatOpen = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.display;
    return Semantics(
      container: true,
      label: widget.title,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(LtRadii.panel),
          border: Border.all(color: LtColors.container, width: LtBorders.container),
          boxShadow: LtShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: WholeWordText(widget.title, style: LtText.display(20))),
            WholeWordText(ExperimentCopy.subtitle, style: LtText.body(color: LtColors.secondary)),
            const SizedBox(height: 6),
            ..._body(context, d),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, ResultDisplay d) {
    switch (d.kind) {
      case ResultKind.noChange:
        return [const NoNumberBox(icon: Icons.eco_outlined, title: ExperimentCopy.pickAChange)];
      case ResultKind.notCounted:
        return [
          const NoNumberBox(
            icon: Icons.info_outline_rounded,
            title: ExperimentCopy.noNumber,
            trailing: NotCountedPill(),
          ),
          ..._notCounted(context, d),
        ];
      case ResultKind.noNumber:
        return [
          NoNumberBox(
            icon: Icons.info_outline_rounded,
            title: ExperimentCopy.noNumber,
            body: ExperimentCopy.tooRare,
            trailing: d.message == null
                ? null
                : InfoButton(
                    label: 'Why is there no number?',
                    onTap: () => showInfoSheet(context, title: ExperimentCopy.noNumber, body: d.message!),
                  ),
          ),
          ..._notCounted(context, d),
        ];
      case ResultKind.invalid:
        return [
          NoNumberBox(
            icon: Icons.help_outline_rounded,
            title: ExperimentCopy.tooManyHours,
            body: ExperimentCopy.tooManyHoursBody,
            trailing: d.message == null
                ? null
                : InfoButton(
                    label: 'Why too many hours?',
                    onTap: () => showInfoSheet(context, title: ExperimentCopy.tooManyHours, body: d.message!),
                  ),
          ),
        ];
      case ResultKind.same:
      case ResultKind.lower:
      case ResultKind.tiny:
      case ResultKind.big:
        return _number(context, d);
    }
  }

  List<Widget> _notCounted(BuildContext context, ResultDisplay d) => [
    for (final f in d.notCounted)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: LtColors.container, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: WholeWordText(widget.leverName(f.id), style: LtText.body(weight: FontWeight.w700)),
              ),
              const NotCountedPill(),
              InfoButton(
                label: 'Why is ${widget.leverName(f.id)} not counted?',
                onTap: () => showInfoSheet(
                  context,
                  title: ExperimentCopy.notCounted,
                  body: f.reasonText ?? 'The model does not count this change.',
                ),
              ),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _number(BuildContext context, ResultDisplay d) {
    final good = d.kind == ResultKind.big || d.kind == ResultKind.tiny;
    final tiny = d.kind == ResultKind.tiny;
    final headline = Text(
      d.headline!,
      style: LtText.display(tiny ? 22 : 28, color: good ? LtColors.teal : LtColors.ink),
    );
    final from = widget.currentScore, delta = widget.scoreDelta;
    return [
      if (from != null && delta != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _ScoreChange(from: from, delta: delta),
        ),
      Stack(
        children: [
          if (widget.celebrate && good)
            const Positioned(right: -10, top: -20, child: LottieBurst.outlookGlow(size: Size(96, 96))),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              if (widget.summary != null) const Icon(Icons.eco_outlined, size: 28, color: LtColors.teal),
              Semantics(header: true, child: headline),
              if (d.caveat != null)
                RoughGuideBadge(
                  caveat: d.caveat!,
                  expanded: _caveatOpen,
                  onTap: () => setState(() => _caveatOpen = !_caveatOpen),
                ),
              if (tiny)
                InfoButton(
                  label: 'Exact figure: ${d.exactFigure!.split('.').first.toLowerCase()}',
                  onTap: () => showInfoSheet(context, title: 'The exact figure', body: d.exactFigure!),
                ),
            ],
          ),
        ],
      ),
      if (_caveatOpen && d.caveat != null)
        Container(
          margin: const EdgeInsets.fromLTRB(0, 6, 0, 4),
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: LtColors.control, width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: WholeWordText(d.caveat!, style: LtText.body()),
                ),
              ),
              Semantics(
                button: true,
                label: 'Close',
                excludeSemantics: true,
                onTap: () => setState(() => _caveatOpen = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _caveatOpen = false),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.close_rounded, size: 24, color: LtColors.ink),
                  ),
                ),
              ),
            ],
          ),
        ),
      if (d.kind != ResultKind.same) ...[
        const SizedBox(height: 2),
        WholeWordText(ExperimentCopy.stillAlive, style: LtText.body(color: LtColors.secondary)),
      ],
      if (widget.summary != null) ...[
        const SizedBox(height: 8),
        WholeWordText(widget.summary!, style: LtText.body(weight: FontWeight.w700)),
      ] else if (d.kind == ResultKind.big) ...[
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 14,
          spacing: 8,
          children: [
            _Labelled(
              label: 'Today: ${d.today}',
              color: LtColors.secondary,
              child: BearArray(today: d.today!, semanticLabel: 'Today: about ${d.today} of 100 bear heads filled.'),
            ),
            _Labelled(
              label: 'What-if: ${d.whatIf}',
              child: BearArray(
                today: d.today!,
                gained: d.gap!,
                semanticLabel: 'What-if: about ${d.whatIf} of 100, ${d.gap} more than today shown in green.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            CustomPaint(size: const Size.square(22), painter: _GainedBear()),
            const SizedBox(width: 8),
            Expanded(
              child: WholeWordText('${d.gap} more, ${widget.gainNote}', style: LtText.body(weight: FontWeight.w700)),
            ),
          ],
        ),
      ] else if (tiny) ...[
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Box(
                  label: 'Today',
                  color: LtColors.container,
                  fill: LtColors.paper,
                  child: Text.rich(
                    TextSpan(
                      text: '${d.todayText} ',
                      style: LtText.display(22),
                      children: [TextSpan(text: 'in 100', style: LtText.body())],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Box(
                  label: 'What-if',
                  color: LtColors.control,
                  fill: const Color(0xFFF4F2FD),
                  child: Text(d.whatIfText!, style: LtText.display(22)),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.label, required this.color, required this.fill, required this.child});
  final String label;
  final Color color;
  final Color fill;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WholeWordText(
          label,
          style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
        ),
        const SizedBox(height: 2),
        child,
      ],
    ),
  );
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child, this.color = LtColors.ink});
  final String label;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: BearArray.side,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WholeWordText(
          label,
          style: LtText.body(weight: FontWeight.w700, color: color),
        ),
        const SizedBox(height: 6),
        child,
      ],
    ),
  );
}

class _GainedBear extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = BearArrayPainter.head(0, 0, size.width);
    canvas.drawPath(path, Paint()..color = LtColors.teal);
  }

  @override
  bool shouldRepaint(_GainedBear old) => false;
}

/// "Health score +0.50 →" small and plain, then the NEW score bold in a pill. The pill carries a word
/// and an arrow as well as its colour: ▲ Better (teal), ▼ Lower (soft coral), About the same (grey).
/// Text is ink on every fill (7.2 to 10.8 against the pill).
class _ScoreChange extends StatelessWidget {
  const _ScoreChange({required this.from, required this.delta});
  final double from;
  final double delta;

  @override
  Widget build(BuildContext context) {
    // Each score is shown to two decimals, so the change (and its word) is the difference of the two
    // numbers shown: the raw delta rounded alone read "+0.44 → +0.46 (+0.03)".
    final delta = (((from + this.delta) * 100).round() - (from * 100).round()) / 100;
    final kind = scoreChangeOf(delta);
    final (word, fill, edge) = switch (kind) {
      ScoreChange.better => ('▲ Better', LtColors.mintTint, LtColors.teal),
      ScoreChange.lower => ('▼ Lower', LtColors.peach, LtColors.peachLip),
      ScoreChange.same => ('About the same', LtColors.trackOff, LtColors.container),
    };
    return Semantics(
      label: newScoreSemantics(from, delta),
      excludeSemantics: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text('Health score ${formatHealthScore(from)} →', style: LtText.body(color: LtColors.secondary)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: edge, width: 2),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(word, style: LtText.body(weight: FontWeight.w700)),
                Text(formatHealthScore(from + delta), style: LtText.display(24)),
                if (kind != ScoreChange.same)
                  Text('(${formatScoreDelta(delta)})', style: LtText.body(weight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
