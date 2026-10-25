import 'package:flutter/material.dart';

import '../twin/twin_model.dart';
import '../twin/twin_state.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart' hide TwinMood;
import 'experiment_copy.dart';
import 'experiment_page.dart';
import 'wellness_panel.dart';
import 'widgets/widgets.dart';

/// "Here's what I see so far" (Y-12): the engine's wellness cards beside Mochi. "Going well" and
/// "Room to grow" rows each open the engine's message and have their own source link; the
/// weight card opens About weight.
class WellnessScreen extends StatelessWidget {
  const WellnessScreen({
    super.key,
    required this.appearance,
    required this.state,
    required this.cards,
    required this.onBack,
    this.onWeight,
    this.open = defaultOpenUrl,
  });

  final TwinAppearance appearance;
  final TwinState state;
  final List<WellnessCard> cards;
  final VoidCallback onBack;
  final VoidCallback? onWeight;
  final OpenUrl open;

  @override
  Widget build(BuildContext context) => ExperimentPage(
    mode: LtMode.room,
    onBack: onBack,
    backLabel: ExperimentCopy.backToRoom,
    dock: Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
      child: LipButton(label: ExperimentCopy.backToRoom, icon: Icons.home_rounded, fontSize: 24, onTap: onBack),
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExperimentPlate(
          appearance: appearance,
          twins: [TwinSlot(state: state, x: 0.3)],
          bubble: 'Here’s what I see so far.',
        ),
        const SizedBox(height: 14),
        Sheet(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: cards.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('I will have more to say once I know a bit more.', style: LtText.body()),
                )
              : WellnessPanel(cards: cards, onWeight: onWeight, open: open),
        ),
      ],
    ),
  );
}
