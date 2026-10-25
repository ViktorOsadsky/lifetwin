import 'package:flutter/material.dart';

import '../widgets/whole_word_text.dart';

import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart';

/// Shared painted-card surfaces. Content grows with Dynamic Type and scrolls.
class WellnessPage extends StatelessWidget {
  const WellnessPage({
    super.key,
    required this.title,
    required this.children,
    required this.onBack,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ModeScaffold(
    mode: LtMode.onboarding,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: RoundBackButton(onTap: onBack),
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                const SizedBox(height: 6),
                Semantics(
                  header: true,
                  child: WholeWordText(title, style: LtText.display(32)),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  WholeWordText(subtitle!, style: LtText.body()),
                ],
                const SizedBox(height: 22),
                ...children,
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class WellnessCard extends StatelessWidget {
  const WellnessCard({
    super.key,
    required this.child,
    this.color = LtColors.paper,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(LtRadii.panel),
      border: Border.all(color: LtColors.container, width: LtBorders.container),
      boxShadow: LtShadows.small,
    ),
    child: Material(color: Colors.transparent, child: child),
  );
}

class MochiMessage extends StatelessWidget {
  const MochiMessage({
    super.key,
    required this.message,
    this.appearance = const TwinAppearance(),
    this.pose = TwinPose.wave,
    this.compact = false,
  });
  final String message;
  final TwinAppearance appearance;
  final TwinPose pose;
  final bool compact;

  @override
  Widget build(BuildContext context) => compact
      ? Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TwinSprite(appearance: appearance, pose: pose, height: 72),
              Expanded(
                child: Bubble(
                  text: message,
                  tail: BubbleTail.left,
                  fontSize: 22,
                  liveRegion: true,
                ),
              ),
            ],
          ),
        )
      : Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            children: [
              SizedBox(
                height: 190,
                child: PlateWindow(
                  name: appearance.name ?? 'Mochi',
                  plate: PlateScene(
                    asset: ScenePlate.customize.asset,
                    focus: const Offset(0.5, 0.48),
                    focusTarget: const Offset(0.3, 0.9),
                    twinBuilder: (feet, scale, box) => plantTwin(
                      feet,
                      TwinSprite(
                        appearance: appearance,
                        pose: pose,
                        height: 145,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                child: Bubble(
                  text: message,
                  tail: BubbleTail.left,
                  fontSize: 22,
                  liveRegion: true,
                ),
              ),
            ],
          ),
        );
}
