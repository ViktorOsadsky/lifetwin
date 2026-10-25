import 'package:flutter/material.dart';

import '../twin/twin_experiment.dart';
import '../twin/twin_repository.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import '../widgets/whole_word_text.dart';
import 'experiment_copy.dart';
import 'experiment_page.dart';
import 'experiment_twins.dart';
import 'lever_copy.dart';
import 'lever_detail_screen.dart';
import 'result_display.dart';
import 'side_by_side_screen.dart';
import 'still_learning_screen.dart';
import 'unavailable_screens.dart';
import 'widgets/widgets.dart';

/// "Experiment with your twin": the hub (Y-1).
///
/// Today's twin and the what-if twin stand side by side, one combined result sits under them, and
/// the levers follow in the engine's order. Tapping a lever opens it (a stepper, or two options
/// for smoking); "Use in my what-if" puts it into the shared what-if. The what-if lives only in
/// the [TwinExperiment]: nothing here, and nothing under it, writes to the profile or the history.
///
/// Without a result for the person today it shows the matching screen instead, never a number:
/// missing answers (Y-8), an age outside 18 to 85 (Y-9), a rare profile (Y-10).
class ExperimentScreen extends StatefulWidget {
  const ExperimentScreen({
    super.key,
    required this.repository,
    required this.appearance,
    this.onBack,
    this.onTellMochi,
    this.openUrl = defaultOpenUrl,
  });

  final TwinRepository repository;
  final TwinAppearance appearance;
  final VoidCallback? onBack;

  /// "Tell Mochi" and "Change": opens the change conversation (`/api/change/start`), with the
  /// profile `field` when one answer is being changed, or none ("What would you like to update?").
  final void Function(String? field)? onTellMochi;
  final OpenUrl openUrl;

  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  // A fresh what-if from the stored profile. It only reads the repository.
  late final TwinExperiment? _exp = widget.repository.experiment();

  @override
  void dispose() {
    _exp?.dispose();
    super.dispose();
  }

  void _back() => (widget.onBack ?? () => Navigator.of(context).maybePop())();

  @override
  Widget build(BuildContext context) {
    final exp = _exp;
    final repo = widget.repository;
    if (exp == null) {
      return StillLearningScreen(
        appearance: widget.appearance,
        assessment: repo.assess(const {}),
        known: const [],
        onBack: _back,
        onTellMochi: widget.onTellMochi,
      );
    }
    final cur = exp.current;
    if (!cur.available) {
      return switch (cur.status) {
        'missing_inputs' => StillLearningScreen(
          appearance: widget.appearance,
          assessment: cur,
          known: const [],
          almostReady: true,
          onBack: _back,
          onTellMochi: widget.onTellMochi,
        ),
        'unsupported_age' => OutsideRangeScreen(
          appearance: widget.appearance,
          cards: repo.wellnessCards,
          onBack: _back,
          open: widget.openUrl,
        ),
        _ => RareAnswersScreen(
          appearance: widget.appearance,
          assessment: cur,
          onBack: _back,
          onChange: widget.onTellMochi,
        ),
      };
    }
    return ListenableBuilder(listenable: exp, builder: (context, _) => _hub(context, exp));
  }

  List<ExperimentLever> _levers(TwinExperiment exp) => [
    for (final l in exp.levers)
      if (l.supported && LeverCopy.of(l.id) != null) l,
  ];

  Widget _hub(BuildContext context, TwinExperiment exp) {
    final levers = _levers(exp);
    final display = ResultDisplay.of(exp.result);
    final moved = levers.where((l) => l.changed).toList();
    final counted = exp.result.levers.where((f) => f.counted).length;
    final today = widget.repository.twinState();
    return ExperimentPage(
      title: ExperimentCopy.title,
      onBack: _back,
      backLabel: 'Back to room',
      dock: HonestyDock(
        action: LipButton(
          label: ExperimentCopy.sideBySide,
          icon: Icons.stacked_line_chart_rounded,
          fontSize: 24,
          onTap: moved.isEmpty ? null : () => _open(context, exp),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: widget.appearance,
            divider: true,
            twins: [
              TwinSlot(state: today, x: 0.27, height: 160),
              TwinSlot(state: whatIfTwinState(today, display), x: 0.73, halo: moved.isNotEmpty, height: 160),
            ],
            overlay: const Stack(
              children: [
                Positioned(left: 14, top: 18, child: ModePill.today()),
                Positioned(right: 14, top: 18, child: ModePill.whatIf()),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ResultCard(
            display: display,
            leverName: _name,
            summary: counted > 0 && display.hasNumber ? _together(counted) : null,
            celebrate: true,
            currentScore: exp.result.currentScore,
            scoreDelta: exp.result.scoreDelta,
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
                      child: Semantics(header: true, child: Text(ExperimentCopy.tryAChange, style: LtText.display(28))),
                    ),
                    if (moved.isNotEmpty)
                      Text(
                        moved.length == 1 ? '1 change' : '${moved.length} changes',
                        style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (levers.isEmpty)
                  WholeWordText(
                    'There is nothing to try here yet. The model needs a few more of your answers first.',
                    style: LtText.body(),
                  ),
                for (final l in levers) ...[
                  LeverRow(
                    icon: LeverCopy.of(l.id)!.icon,
                    title: LeverCopy.of(l.id)!.short,
                    today: LeverCopy.today(l),
                    whatIf: LeverCopy.whatIf(l),
                    semanticLabel: LeverCopy.rowLabel(l),
                    onTap: () => _openLever(context, exp, l.id),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _together(int n) => n == 1 ? 'This change' : 'All $n changes together';

  String _name(String id) => LeverCopy.of(id)?.full ?? 'This change';

  void _openLever(BuildContext context, TwinExperiment exp, String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LeverDetailScreen(
        repository: widget.repository,
        whatIf: exp,
        leverId: id,
        appearance: widget.appearance,
        open: widget.openUrl,
      ),
    ),
  );

  void _open(BuildContext context, TwinExperiment exp) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SideBySideScreen(
        repository: widget.repository,
        whatIf: exp,
        appearance: widget.appearance,
        open: widget.openUrl,
      ),
    ),
  );
}
