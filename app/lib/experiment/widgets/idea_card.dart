import 'package:flutter/material.dart';

import '../../twin/twin_experiment.dart';
import '../../ui/theme.dart';
import '../../ui/twin_appearance.dart';
import '../../ui/widgets/widgets.dart';
import '../../widgets/whole_word_text.dart';
import '../lever_copy.dart';
import '../recommendations.dart';
import 'idea_scene.dart';

/// The server's fixed wording for an effect level: never edited, never given a number.
const effectNote = 'Modeled difference for people like you, not a promise';

/// "big" / "some" / "small" / "tiny" -> the word, or null (no cue) for anything else.
String? effectWord(String? effect) => switch (effect) {
  'big' => 'Big',
  'some' => 'Some',
  'small' => 'Small',
  'tiny' => 'Tiny',
  _ => null,
};

/// Three steps: big fills three, tiny none.
int _steps(String effect) => switch (effect) {
  'big' => 3,
  'some' => 2,
  'small' => 1,
  _ => 0,
};

/// What "Based on ..." says, from the lever the idea is about (and the notebook, when a quote exists).
String basedOn(Recommendation idea) {
  final parts = <String>[
    switch (idea.leverId) {
      LeverId.sleepHours => 'your sleep',
      LeverId.moderate || LeverId.vigorous => 'your activity',
      LeverId.sitting => 'your sitting time',
      LeverId.smoking => 'your smoking answer',
      _ => 'your answers',
    },
    if (idea.habitNoteQuote != null) 'your note',
  ];
  return 'Based on ${parts.join(', ')}';
}

/// The three-step meter for an effect level.
class EffectMeter extends StatelessWidget {
  const EffectMeter({super.key, required this.effect, this.scale = 1});
  final String effect;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final on = _steps(effect);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Container(
              width: 9 * scale,
              height: (10 + 5 * i) * scale,
              decoration: BoxDecoration(
                color: i < on ? LtColors.teal : LtColors.paper,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: i < on ? const Color(0xFF17594A) : LtColors.control, width: 2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The effect cue: meter + word + (i). A button that opens the effect sheet. Null effect: nothing.
class EffectCue extends StatelessWidget {
  const EffectCue({super.key, required this.effect, required this.onTap});
  final String? effect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final word = effectWord(effect);
    if (word == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Modeled effect: ${word.toLowerCase()}. $effectNote.',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F5EC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: LtColors.container, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EffectMeter(effect: effect!),
                  const SizedBox(width: 8),
                  Text(word, style: LtText.body(weight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  const Icon(Icons.info_outline_rounded, size: 20, color: LtColors.secondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One idea on the list (I-1): icon, title, effect cue, the why line (always shown, wraps),
/// "Based on", and "Try it with my twin" (filled on the [top] card, a quiet link on the others).
/// The whole card opens the details; the cue and the Try button win their own taps.
class IdeaCard extends StatelessWidget {
  const IdeaCard({
    super.key,
    required this.idea,
    required this.onOpen,
    required this.onEffect,
    this.onTry,
    this.top = false,
    this.appearance,
  });

  /// With a twin look the card shows a small Mochi in the idea's pose instead of the lever icon.
  final TwinAppearance? appearance;

  final Recommendation idea;
  final VoidCallback onOpen;
  final VoidCallback onEffect;

  /// Null hides the Try button (an idea with no lever).
  final VoidCallback? onTry;
  final bool top;

  /// The one why line: the server's short line, else the idea's own words.
  String get why => idea.whyShort.isNotEmpty ? idea.whyShort : idea.tip;

  @override
  Widget build(BuildContext context) {
    final copy = idea.leverId == null ? null : LeverCopy.of(idea.leverId!);
    final iconSize = MediaQuery.textScalerOf(context).scale(1) >= 1.5 ? 56.0 : 48.0;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Idea: ${idea.title}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(LtRadii.panel),
          border: Border.all(color: LtColors.container, width: LtBorders.container),
          boxShadow: LtShadows.soft,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(LtRadii.panel),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    button: true,
                    label: '${idea.title}. Open details',
                    onTap: onOpen,
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        if (appearance != null)
                          IdeaThumb(appearance: appearance!, kind: idea.kind, size: iconSize)
                        else
                          Container(
                            width: iconSize,
                            height: iconSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFE3F5EC),
                              border: Border.all(color: LtColors.control, width: 2),
                            ),
                            child: Icon(copy?.icon ?? Icons.eco_outlined, size: iconSize * 0.54, color: LtColors.ink),
                          ),
                        const SizedBox(width: 12),
                        Expanded(child: WholeWordText(idea.title, style: LtText.display(22))),
                        if (!top) const Icon(Icons.chevron_right_rounded, size: 28, color: LtColors.ink),
                      ],
                    ),
                  ),
                  if (effectWord(idea.effect) != null) ...[
                    const SizedBox(height: 8),
                    EffectCue(effect: idea.effect, onTap: onEffect),
                  ] else if (appearance != null) ...[
                    const SizedBox(height: 8),
                    const Align(alignment: Alignment.centerLeft, child: GuidelineChip()),
                  ],
                  const SizedBox(height: 8),
                  WholeWordText(why, style: LtText.body(size: 18)),
                  const SizedBox(height: 4),
                  WholeWordText(basedOn(idea), style: LtText.body(color: LtColors.secondary)),
                  if (onTry != null) ...[
                    const SizedBox(height: 8),
                    if (top)
                      LipButton(
                        label: 'Try it with my twin',
                        icon: Icons.eco_outlined,
                        height: 56,
                        fontSize: 21,
                        semanticLabel: 'Try it with my twin: ${idea.title}',
                        onTap: onTry,
                      )
                    else
                      _QuietTry(onTap: onTry!, title: idea.title),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuietTry extends StatelessWidget {
  const _QuietTry({required this.onTap, required this.title});
  final VoidCallback onTap;
  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Try it with my twin: $title',
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            const Icon(Icons.eco_outlined, size: 22, color: LtColors.ink),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Try it with my twin',
                style: LtText.body(weight: FontWeight.w700)
                    .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
