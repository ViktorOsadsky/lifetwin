import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../ui/twin_appearance.dart';
import '../../ui/widgets/widgets.dart';
import '../experiment_page.dart';
import '../experiment_twins.dart';
import '../idea_kind.dart';
import '../recommendations.dart';

/// Mochi in the room plate, in the pose for an idea's `kind`, with up to two decorative props.
///
/// One gentle hop when it appears (translateY 6 → −5 → 0 in 420 ms), then the props pop in, 80 ms
/// apart. Nothing loops. Under Reduce Motion Mochi is simply in the pose and the props are there.
/// Give it a `ValueKey(idea.id)` so a new idea plays the hop once; everything here is decorative
/// and hidden from VoiceOver (the card around it says the words).
class IdeaScene extends StatefulWidget {
  const IdeaScene({
    super.key,
    required this.appearance,
    required this.kind,
    this.bubble,
    this.x = 0.5,
  });

  final TwinAppearance appearance;
  final String? kind;

  /// Mochi's short line in a bubble (the detail); the hero has none.
  final String? bubble;

  /// Where Mochi stands across the window.
  final double x;

  @override
  State<IdeaScene> createState() => _IdeaSceneState();
}

class _IdeaSceneState extends State<IdeaScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _hop = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 6.0,
        end: -5.0,
      ).chain(CurveTween(curve: const Cubic(.2, 0, 0, 1))),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: -5.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 55,
    ),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 480),
  ]).animate(_c);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Prop [i] pops after the hop: 320 ms ease-out-back, 80 ms apart.
  Animation<double> _pop(int i) => CurvedAnimation(
    parent: _c,
    curve: Interval(
      (420 + 80.0 * i) / 900,
      math.min(1, (420 + 80.0 * i + 320) / 900),
      curve: const Cubic(.175, .885, .32, 1.275),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final props = ideaProps(widget.kind);
    final left = widget.x < 0.5;
    return ExcludeSemantics(
      child: ExperimentPlate(
        appearance: widget.appearance,
        bubble: widget.bubble,
        twins: [
          TwinSlot(
            state: steadyTwin,
            x: widget.x,
            pose: ideaPose(widget.kind),
            hop: _hop,
          ),
        ],
        overlay: Stack(
          children: [
            for (final (i, icon) in props.indexed)
              Positioned(
                // Beside Mochi: with a bubble on the right both sit at the left; otherwise one each side.
                left: left || i == 1 ? 18 : null,
                right: !left && i == 0 ? 18 : null,
                top: i == 0 ? 74 : 138,
                child: ScaleTransition(
                  scale: _pop(i),
                  child: IdeaProp(
                    icon: icon,
                    lilac: i == 1,
                    tilt: i == 0 ? -0.12 : 0.1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A decorative prop: a soft mint or lilac square with a slight tilt, 40 px, no border and no
/// shadow, so it can never be mistaken for a button. Not announced.
class IdeaProp extends StatelessWidget {
  const IdeaProp({
    super.key,
    required this.icon,
    this.lilac = false,
    this.tilt = -0.1,
  });
  final IconData icon;
  final bool lilac;
  final double tilt;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Transform.rotate(
      angle: tilt,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: lilac ? const Color(0xFFE6E0FA) : LtColors.mintTint,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 24, color: LtColors.ink),
      ),
    ),
  );
}

/// A small Mochi in the pose for [kind], in a round lilac badge (the cards and rows).
class IdeaThumb extends StatelessWidget {
  const IdeaThumb({
    super.key,
    required this.appearance,
    required this.kind,
    this.size = 48,
  });
  final TwinAppearance appearance;
  final String? kind;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFEEE8FB),
        border: Border.all(color: LtColors.control, width: 2),
      ),
      child: OverflowBox(
        maxWidth: size * 1.7,
        maxHeight: size * 1.7,
        alignment: const Alignment(0, -0.1),
        child: TwinStateSprite(
          state: steadyTwin,
          appearance: appearance,
          height: size * 1.7,
          pose: ideaPose(kind),
        ),
      ),
    ),
  );
}

/// "Guideline": the quiet chip for an idea the model gives no effect for (`effect: null`). It has
/// no meter, and never reads as a prediction.
class GuidelineChip extends StatelessWidget {
  const GuidelineChip({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Guideline. Not modeled.',
    excludeSemantics: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: LtColors.container, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.menu_book_outlined,
            size: 20,
            color: LtColors.secondary,
          ),
          const SizedBox(width: 6),
          Text(
            'Guideline',
            style: LtText.body(
              weight: FontWeight.w700,
              color: LtColors.secondary,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A tappable row for a short list of ideas (the check-in, onboarding, voice): Mochi's pose, the
/// title and, optionally, the server's line. A 56 pt target.
class IdeaRow extends StatelessWidget {
  const IdeaRow({
    super.key,
    required this.idea,
    required this.appearance,
    required this.onTap,
    this.showLine = true,
  });
  final Recommendation idea;
  final TwinAppearance appearance;
  final VoidCallback onTap;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    final line = idea.whyShort.isNotEmpty ? idea.whyShort : idea.tip;
    return Semantics(
      button: true,
      label: showLine ? '${idea.title}. $line' : idea.title,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: LtColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LtRadii.panel),
          side: const BorderSide(color: LtColors.control, width: 2),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LtRadii.panel),
          ),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
              child: Row(
                children: [
                  IdeaThumb(appearance: appearance, kind: idea.kind, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(idea.title, style: LtText.display(20)),
                        if (showLine)
                          Text(
                            line,
                            style: LtText.body(color: LtColors.secondary),
                          ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 28,
                    color: LtColors.ink,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bordered row with a bulb for the quiet ways in ("Ideas linked to a healthier score ›"): a 56 pt target.
class IdeasLinkRow extends StatelessWidget {
  const IdeasLinkRow({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Material(
      color: LtColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LtRadii.panel),
        side: const BorderSide(color: LtColors.control, width: 2),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LtRadii.panel)),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded, size: 26, color: LtColors.ink),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: LtText.body(weight: FontWeight.w700))),
                const Icon(Icons.chevron_right_rounded, size: 28, color: LtColors.ink),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
