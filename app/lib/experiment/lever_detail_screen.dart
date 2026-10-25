import 'package:flutter/material.dart';

import '../twin/twin_experiment.dart';
import '../twin/twin_repository.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import 'experiment_copy.dart';
import 'experiment_page.dart';
import 'experiment_twins.dart';
import 'lever_copy.dart';
import 'result_display.dart';
import 'widgets/widgets.dart';

/// Whether to show the US quitline (1-800-QUIT-NOW) on the smoking screen. The design marks it
/// OWNER APPROVAL NEEDED, so it stays off until the owner says yes. It would be a `tel:` link the
/// person taps, never dialled automatically.
const showQuitline = false;

/// One lever (Y-2 sleep and the other steppers, Y-7 smoking).
///
/// The person moves it on a bounded control and sees "Just this change": the modeled difference
/// of that lever alone, from a private copy of the experiment. "Use in my what-if" then puts the
/// value into the shared what-if. Nothing here is saved to the person's answers.
class LeverDetailScreen extends StatefulWidget {
  const LeverDetailScreen({
    super.key,
    required this.repository,
    required this.whatIf,
    required this.leverId,
    required this.appearance,
    this.open = defaultOpenUrl,
  });

  final TwinRepository repository;

  /// The shared what-if that "Use in my what-if" sets.
  final TwinExperiment whatIf;
  final String leverId;
  final TwinAppearance appearance;
  final OpenUrl open;

  @override
  State<LeverDetailScreen> createState() => _LeverDetailScreenState();
}

class _LeverDetailScreenState extends State<LeverDetailScreen> {
  // This lever alone, on a fresh copy.
  late final TwinExperiment _probe = widget.repository.experiment()!
    ..set(widget.leverId, widget.whatIf.lever(widget.leverId).value ?? 0);

  @override
  void dispose() {
    _probe.dispose();
    super.dispose();
  }

  bool get _isSmoking => widget.leverId == LeverId.smoking;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _probe, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final l = _probe.lever(widget.leverId);
    final copy = LeverCopy.of(widget.leverId)!;
    final display = ResultDisplay.of(_probe.result);
    final today = widget.repository.twinState();
    final v = l.value ?? l.current ?? 0;
    return ExperimentPage(
      onBack: () => Navigator.of(context).pop(),
      backLabel: 'Back to Experiment',
      dock: HonestyDock(
        action: LipButton(
          label: ExperimentCopy.useInWhatIf,
          icon: Icons.check_rounded,
          fontSize: 24,
          semanticLabel:
              'Use ${LeverCopy.spoken(LeverCopy.value(l, v))} in my what-if. '
              'Nothing is saved to your answers.',
          onTap: () {
            widget.whatIf.set(widget.leverId, v);
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: widget.appearance,
            twins: [TwinSlot(state: whatIfTwinState(today, display), x: 0.3, halo: true)],
            bubble: display.kind == ResultKind.noChange ? copy.bubble : ExperimentCopy.bubbleBig,
            overlay: const Stack(children: [Positioned(right: 16, top: 30, child: ModePill.whatIf())]),
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
                      child: Semantics(header: true, child: Text(copy.full, style: LtText.display(28))),
                    ),
                    _JustThis(),
                  ],
                ),
                const SizedBox(height: 10),
                if (_isSmoking)
                  TwoOptionControl(
                    firstLabel: ExperimentCopy.smokeNow,
                    firstCaption: 'Today',
                    secondLabel: ExperimentCopy.quit,
                    secondCaption: 'What-if',
                    secondSelected: v == 1,
                    onChanged: (quit) => _probe.set(widget.leverId, quit ? 1 : 2),
                    semanticLabel: 'Smoking what-if',
                  )
                else ...[
                  _stepper(l, v, copy),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Today ${LeverCopy.value(l, l.current ?? 0)}',
                            style: LtText.body(color: LtColors.secondary),
                          ),
                        ),
                        Text(LeverCopy.change(l, v), style: LtText.body(weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          ResultCard(
            display: display,
            leverName: (id) => LeverCopy.of(id)?.full ?? 'This change',
            title: _isSmoking ? 'Quitting alone vs today' : ExperimentCopy.justThisChange,
            gainNote: _isSmoking ? 'from quitting alone' : 'from this change',
          ),
          if (_isSmoking) ..._smokingHelp(),
          if (!_isSmoking && l.id == LeverId.sleepHours && v >= l.max)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${LeverCopy.value(l, l.max)} ${ExperimentCopy.topOfRange}',
                style: LtText.body(color: LtColors.secondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepper(ExperimentLever l, double v, LeverCopy copy) {
    final cur = l.current ?? 0;
    // Sitting is the one lever that goes down: its minus button is the way to try less.
    final down = l.id == LeverId.sitting;
    final canMinus = down ? v > l.min : v > cur;
    final canPlus = down ? v < cur : v < l.max;
    return BigStepper(
      value: LeverCopy.value(l, v),
      unit: copy.unit,
      minusLabel: LeverCopy.minusLabel(l),
      plusLabel: LeverCopy.plusLabel(l),
      onMinus: canMinus ? () => _probe.set(l.id, v - l.step) : null,
      onPlus: canPlus ? () => _probe.set(l.id, v + l.step) : null,
    );
  }

  List<Widget> _smokingHelp() {
    final card = widget.repository.wellnessCards.where((c) => c.id == 'smoking').firstOrNull;
    if (card == null && !showQuitline) return const [];
    return [
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: LtColors.mintWash,
          borderRadius: BorderRadius.circular(LtRadii.panel),
          border: Border.all(color: LtColors.container, width: LtBorders.container),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showQuitline)
              SourceLink(
                label: ExperimentCopy.quitline,
                url: 'tel:${ExperimentCopy.quitlineNumber}',
                open: widget.open,
              ),
            if (card != null)
              SourceLink(
                label: '${SourceLink.siteName(card.sourceUrl)}: ${card.title}',
                url: card.sourceUrl,
                open: widget.open,
              ),
          ],
        ),
      ),
    ];
  }
}

class _JustThis extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DashedBox(
    color: LtColors.control,
    radius: 16,
    fill: LtColors.paper,
    constraints: const BoxConstraints(minHeight: 32),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Center(
      widthFactor: 1,
      child: Text(ExperimentCopy.justThisChange, style: LtText.body(weight: FontWeight.w700)),
    ),
  );
}
