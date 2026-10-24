import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_curve_chart.dart';
import '../../widgets/lt_magic_ball.dart';
import '../../widgets/lt_mascot.dart';
import '../../widgets/lt_scaffold.dart';
import '../../widgets/lt_segmented.dart';
import '../../widgets/lt_sheet.dart';
import '../../state/twin_look.dart';
import '../../widgets/lt_habitat.dart';
import '../../widgets/lt_list.dart';
import '../../widgets/lt_twin.dart';

/// F4: Pip and the magic ball. The scene leads; the outlook figure is a
/// placeholder until the model is connected.
class FortuneScreen extends ConsumerStatefulWidget {
  const FortuneScreen({super.key});

  @override
  ConsumerState<FortuneScreen> createState() => _FortuneScreenState();
}

class _FortuneScreenState extends ConsumerState<FortuneScreen> {
  bool _revealed = false;
  int _horizon = 10;

  static const tier = 2;

  @override
  Widget build(BuildContext context) {
    final look = ref.watch(twinLookProvider);
    return LtPage(
      title: 'Magic ball',
      sheetToBottom: true,
      // The meadow absorbs spare height and dissolves into the page at both
      // edges; the reveal rises on one sheet and scrolls once it outgrows
      // the space.
      child: LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, stage) {
                  const fadeBottom = 120.0;
                  final h = stage.maxHeight;
                  final contact = ((h - fadeBottom + 28) / h).clamp(0.55, 0.9);
                  final twinW = ((h * contact - 40) / Twin.aspect).clamp(
                    56.0,
                    stage.maxWidth * 0.42,
                  );
                  final ballW = twinW * 0.62;
                  final pipW = twinW * 0.62;
                  return Habitat(
                    tier: tier,
                    contactLine: contact,
                    fadeTop: 72,
                    fadeBottom: fadeBottom,
                    actors: [
                      // Pip hovers behind the ball, holding it to the light.
                      HabitatActor(
                        x: 0.78,
                        footprint: pipW * 0.5,
                        lift: ballW * 0.62,
                        child: Mascot(
                          state: _revealed
                              ? MascotState.celebrating
                              : MascotState.thinking,
                          width: pipW,
                          shadow: false,
                        ),
                      ),
                      HabitatActor(
                        x: 0.70,
                        footprint: ballW * 0.62,
                        child: MagicBall(size: ballW, revealed: _revealed),
                      ),
                      HabitatActor(
                        x: 0.28,
                        footprint: twinW * 0.78,
                        child: Twin(
                          width: twinW,
                          look: look,
                          mood: _revealed ? TwinMood.happy : TwinMood.calm,
                          pose: _revealed ? TwinPose.reach : TwinPose.rest,
                          lean: _revealed ? 0.35 : 0,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(0, box.maxHeight - 200),
              ),
              child: LtSheetPanel(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    LtSpace.gutter,
                    LtSpace.s12,
                    LtSpace.gutter,
                    LtSpace.s24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _revealed
                            ? 'Here’s what the ball sees.'
                            : 'Pip is peering into the ball…',
                        style: context.text.title2,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: LtSpace.s16),
                      if (!_revealed)
                        LtButton(
                          label: 'Reveal my outlook',
                          onPressed: () => setState(() => _revealed = true),
                        )
                      else
                        _Reveal(
                          horizon: _horizon,
                          onHorizon: (h) => setState(() => _horizon = h),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.horizon, required this.onHorizon});

  final int horizon;
  final ValueChanged<int> onHorizon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LtSegmented<int>(
          segments: const [
            LtSegment(value: 10, label: '10 years'),
            LtSegment(value: 20, label: '20 years'),
          ],
          value: horizon,
          onChanged: onHorizon,
        ),
        const SizedBox(height: LtSpace.s20),
        // Words lead; the number is secondary and always an "outlook".
        Text(
          'Your outlook',
          style: context.text.headline,
          textAlign: TextAlign.center,
        ),
        Semantics(
          label: 'Placeholder percentage, model not connected',
          excludeSemantics: true,
          child: Text(
            '[xx.x %]',
            // Words lead; the figure stays secondary to the scene.
            style: context.text.title1,
            textAlign: TextAlign.center,
          ),
        ),
        Text(
          'modeled chance of reaching the $horizon-year mark',
          style: context.text.subhead.copyWith(color: c.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: LtSpace.s16),
        const Center(child: OutlookFootnote()),
        const SizedBox(height: LtSpace.s8),
        LtTextButton(
          label: 'See the curve',
          center: true,
          onPressed: () =>
              showLtSheet<void>(context, builder: (_) => const _CurveSheet()),
        ),
        const SizedBox(height: LtSpace.s8),
        LtButton(
          label: 'Small steps that may help',
          onPressed: () => context.push('/levers'),
        ),
      ],
    );
  }
}

class _CurveSheet extends StatelessWidget {
  const _CurveSheet();

  @override
  Widget build(BuildContext context) {
    return LtSheetScaffold(
      title: 'Outlook curve',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LtCurveChart(),
          SizedBox(height: LtSpace.s12),
          OutlookFootnote(),
        ],
      ),
    );
  }
}
