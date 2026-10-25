import 'package:flutter/material.dart';

import '../twin/twin_experiment.dart';
import '../twin/twin_repository.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import '../widgets/whole_word_text.dart';
import '../wellness/today_card.dart' show MoreIdeasLink;
import 'experiment_copy.dart';
import 'ideas_hub.dart';
import 'experiment_page.dart';
import 'experiment_twins.dart';
import 'lever_copy.dart';
import 'result_display.dart';
import 'widgets/widgets.dart';

/// "Side by side" (Y-3, Y-4, Y-16, Y-17): today and the what-if, as people out of 100.
///
/// One combined result for the whole what-if, never a sum of levers. A gain of one or more
/// shows the two bear arrays; a tiny one shows words and an (i); "About the same" shows words.
/// Below: the levers in this what-if, and "See years 1 to 5" for the curve.
class SideBySideScreen extends StatelessWidget {
  const SideBySideScreen({
    super.key,
    required this.repository,
    required this.whatIf,
    required this.appearance,
    this.open = defaultOpenUrl,
    this.ideas,
  });

  /// "More ideas like this ›" under the result. Null hides it (under 18).
  final IdeasAccess? ideas;

  final TwinRepository repository;
  final TwinExperiment whatIf;
  final TwinAppearance appearance;
  final OpenUrl open;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: whatIf, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final display = ResultDisplay.of(whatIf.result);
    final moved = [
      for (final l in whatIf.levers)
        if (l.changed && LeverCopy.of(l.id) != null) l,
    ];
    final counted = whatIf.result.levers.where((f) => f.counted).length;
    final big = display.kind == ResultKind.big;
    final today = repository.twinState();
    // The card that praises what the person already does, when the what-if barely moves.
    final strong = display.kind == ResultKind.tiny || display.kind == ResultKind.same ? _strengthCard(moved) : null;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!big)
          ExperimentPlate(
            appearance: appearance,
            twins: [TwinSlot(state: whatIfTwinState(today, display), x: 0.3, halo: true)],
            bubble: display.kind == ResultKind.tiny ? ExperimentCopy.bubbleTiny : ExperimentCopy.bubbleBig,
            overlay: const Stack(children: [Positioned(right: 16, top: 30, child: ModePill.whatIf())]),
          ),
        if (!big) const SizedBox(height: 14),
        ResultCard(
          display: display,
          leverName: (id) => LeverCopy.of(id)?.full ?? 'This change',
          gainNote: counted == 1 ? 'from this change' : 'with all $counted changes',
          celebrate: true,
          currentScore: whatIf.result.currentScore,
          scoreDelta: whatIf.result.scoreDelta,
        ),
        if (strong != null) ...[const SizedBox(height: 14), strong],
        if (moved.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              header: true,
              child: WholeWordText(ExperimentCopy.inThisWhatIf, style: LtText.body(weight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in moved)
                  WhatIfChip(
                    icon: LeverCopy.of(l.id)!.icon,
                    label: l.id == LeverId.smoking
                        ? 'Smoke-free'
                        : '${LeverCopy.of(l.id)!.full} ${LeverCopy.withUnit(l, l.value!)}',
                  ),
              ],
            ),
          ),
        ],
        if (display.rows.isNotEmpty) ...[
          const SizedBox(height: 14),
          LipButton(
            label: ExperimentCopy.seeYears,
            icon: Icons.show_chart_rounded,
            kind: LipKind.secondary,
            height: 56,
            fontSize: 21,
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CurveScreen(display: display))),
          ),
        ],
      ],
    );
    return ExperimentPage(
      title: big ? 'Side by side' : null,
      whatIfPill: big,
      onBack: () => Navigator.of(context).pop(),
      backLabel: 'Back to Experiment',
      dock: HonestyDock(
        action: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LipButton(label: ExperimentCopy.tryOther, fontSize: 24, onTap: () => Navigator.of(context).pop()),
            if (ideas case final access?) _MoreLikeThis(access: access, levers: {for (final l in moved) l.id}),
          ],
        ),
      ),
      body: body,
    );
  }

  Widget? _strengthCard(List<ExperimentLever> moved) {
    for (final l in moved) {
      final id = LeverCopy.of(l.id)!.wellnessCard;
      final card = repository.wellnessCards.where((c) => c.id == id && c.level == 'strength').firstOrNull;
      if (card != null) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          decoration: BoxDecoration(
            color: LtColors.mintWash,
            borderRadius: BorderRadius.circular(LtRadii.panel),
            border: Border.all(color: LtColors.container, width: LtBorders.container),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_border_rounded, size: 24, color: LtColors.ink),
                  const SizedBox(width: 8),
                  Text("You're already strong", style: LtText.display(22)),
                ],
              ),
              const SizedBox(height: 4),
              WholeWordText('You already do a lot of this. That’s good news.', style: LtText.body()),
              SourceLink(
                label: '${SourceLink.siteName(card.sourceUrl)}: ${card.title}',
                url: card.sourceUrl,
                open: open,
              ),
            ],
          ),
        );
      }
    }
    return null;
  }
}

/// "Years 1 to 5" (Y-5): the modeled survival of similar people, zoomed in by default and
/// labelled as zoomed, with the honest 0 to 100 scale behind a switch, and the table behind
/// "See the numbers".
class CurveScreen extends StatefulWidget {
  const CurveScreen({super.key, required this.display});
  final ResultDisplay display;

  @override
  State<CurveScreen> createState() => _CurveScreenState();
}

class _CurveScreenState extends State<CurveScreen> {
  bool _full = false;
  bool _caveat = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.display;
    final lo = ExperimentCurve.zoomFloor(d.rows);
    return ExperimentPage(
      title: 'Years 1 to 5',
      whatIfPill: true,
      onBack: () => Navigator.of(context).pop(),
      dock: HonestyDock(
        action: LipButton(
          label: ExperimentCopy.tryOther,
          fontSize: 24,
          onTap: () => Navigator.of(context)
            ..pop()
            ..pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: LtColors.paper,
              borderRadius: BorderRadius.circular(LtRadii.panel),
              border: Border.all(color: LtColors.container, width: LtBorders.container),
              boxShadow: LtShadows.soft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Modeled survival of similar people', style: LtText.display(22)),
                    ),
                    if (d.caveat != null)
                      RoughGuideBadge(
                        caveat: d.caveat!,
                        expanded: _caveat,
                        onTap: () => setState(() => _caveat = !_caveat),
                      ),
                  ],
                ),
                if (_caveat && d.caveat != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: WholeWordText(d.caveat!, style: LtText.body()),
                  ),
                WholeWordText(
                  'Of 100 people like you, still alive each year',
                  style: LtText.body(color: LtColors.secondary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const _Key(dashed: true, label: 'Today'),
                    const SizedBox(width: 16),
                    const _Key(dashed: false, label: 'What-if'),
                  ],
                ),
                const SizedBox(height: 8),
                if (_full)
                  ExperimentCurve(rows: d.rows, full: true)
                else
                  DashedBox(
                    color: LtColors.container,
                    radius: 18,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, size: 20, color: LtColors.ink),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text('Zoomed in: $lo to 100', style: LtText.body(weight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        ExperimentCurve(rows: d.rows),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                _FullScaleSwitch(on: _full, onChanged: (v) => setState(() => _full = v)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LipButton(
            label: ExperimentCopy.seeNumbers,
            icon: Icons.table_rows_outlined,
            kind: LipKind.secondary,
            height: 56,
            fontSize: 21,
            onTap: () => _numbers(context, d),
          ),
        ],
      ),
    );
  }

  void _numbers(BuildContext context, ResultDisplay d) => showInfoSheet(
    context,
    title: 'About how many in 100',
    body: 'Today and the what-if, year by year.',
    extra: NumbersTable(rows: d.rows),
  );
}

/// The numbers behind the curve: the same rounding as the arrays and the labels.
class NumbersTable extends StatelessWidget {
  const NumbersTable({super.key, required this.rows});
  final List<YearRow> rows;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Years 1 to 5, today and what-if, about how many in 100',
    child: Table(
      columnWidths: const {0: FixedColumnWidth(64), 1: FixedColumnWidth(64)},
      children: [
        TableRow(
          children: [
            for (final h in ['Year', 'Today', 'What-if'])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(h, style: LtText.body(weight: FontWeight.w700)),
              ),
          ],
        ),
        for (final r in rows)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${r.year}', style: LtText.body()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${r.today}', style: LtText.body()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(r.gapIsTiny ? '${r.whatIf}, less than 1 more' : '${r.whatIf}', style: LtText.body()),
              ),
            ],
          ),
      ],
    ),
  );
}

class _Key extends StatelessWidget {
  const _Key({required this.dashed, required this.label});
  final bool dashed;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 28, child: CustomPaint(painter: _KeyPainter(dashed))),
      const SizedBox(width: 6),
      Text(label, style: LtText.body(weight: dashed ? FontWeight.w400 : FontWeight.w700)),
    ],
  );
}

class _KeyPainter extends CustomPainter {
  _KeyPainter(this.dashed);
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = dashed ? LtColors.control : LtColors.teal
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
      return;
    }
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, size.height / 2), Offset((x + 4).clamp(0, size.width), size.height / 2), p);
    }
  }

  @override
  bool shouldRepaint(_KeyPainter old) => old.dashed != dashed;
}

class _FullScaleSwitch extends StatelessWidget {
  const _FullScaleSwitch({required this.on, required this.onChanged});
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: on,
    label: 'Show full scale, 0 to 100',
    excludeSemantics: true,
    onTap: () => onChanged(!on),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!on),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: LtColors.control, width: LtBorders.control),
        ),
        child: Row(
          children: [
            const LeverIcon(Icons.show_chart_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Show full scale', style: LtText.body(size: 18, weight: FontWeight.w700)),
                  Text('0 to 100', style: LtText.body(color: LtColors.secondary)),
                ],
              ),
            ),
            Container(
              width: 64,
              height: 38,
              padding: const EdgeInsets.all(3),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on ? LtColors.mint : LtColors.trackOff,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: LtColors.controlOnMint, width: LtBorders.control),
              ),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: LtColors.paper,
                  shape: BoxShape.circle,
                  border: Border.all(color: LtColors.controlOnMint, width: LtBorders.control),
                ),
                child: on ? const Icon(Icons.check_rounded, size: 16, color: LtColors.ink) : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// "More ideas like this ›": Ideas for you, filtered to the levers in this what-if. Hidden when no idea
/// today is for one of them (it never promises that an idea will give this result).
class _MoreLikeThis extends StatelessWidget {
  const _MoreLikeThis({required this.access, required this.levers});
  final IdeasAccess access;
  final Set<String> levers;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: access.hub,
    builder: (context, _) {
      final any = access.hub.visibleRecommendations.any((r) => levers.contains(r.leverId));
      if (!any) return const SizedBox.shrink();
      return Center(
        child: MoreIdeasLink(
          label: 'More ideas like this',
          onTap: () => access.openList(context, origin: 'result', levers: levers),
        ),
      );
    },
  );
}
