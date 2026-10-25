import 'package:flutter/material.dart';

import '../checkin/consents.dart' show AiProvider;
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import '../widgets/whole_word_text.dart';
import 'experiment_page.dart';
import 'ideas_list_screen.dart' show showEffectSheet;
import 'recommendations.dart';
import 'widgets/idea_card.dart';
import 'widgets/idea_scene.dart';
import 'widgets/widgets.dart';

/// One idea in full (I-2): the why line (the server's `why_short`, never cut), what it is based
/// on, what the model says (level and its fixed note), the source, and "Try it with my twin".
///
/// "Add to my plan" is not here: the coach has no way yet to take an idea (see the PR notes).
class IdeaDetailScreen extends StatelessWidget {
  const IdeaDetailScreen({
    super.key,
    required this.idea,
    required this.appearance,
    required this.onBack,
    required this.backLabel,
    this.onTry,
    this.worded,
    this.open = defaultOpenUrl,
  });

  final Recommendation idea;
  final TwinAppearance appearance;
  final VoidCallback onBack;
  final String backLabel;
  final VoidCallback? onTry;
  final AiProvider? worded;
  final OpenUrl open;

  /// Mochi's bubble: the server's own line when it is short (its first sentence if that is);
  /// otherwise Mochi stands without one.
  static String? _short(String text) {
    final t = text.trim();
    if (t.isNotEmpty && t.length <= 60) return t;
    final first = RegExp(r'^[^.!?]+[.!?]').firstMatch(t)?.group(0);
    return first != null && first.length <= 60 ? first : null;
  }

  @override
  Widget build(BuildContext context) {
    final why = idea.whyShort.isNotEmpty ? idea.whyShort : idea.tip;
    final word = effectWord(idea.effect);
    final bubble = _short(idea.tip);
    final url = idea.sourceUrl;
    final training = worded?.trainingLine;
    return ExperimentPage(
      title: 'Idea',
      onBack: onBack,
      backLabel: backLabel,
      dock: onTry == null
          ? null
          : Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                14 + MediaQuery.paddingOf(context).bottom,
              ),
              child: LipButton(
                label: 'Try it with my twin',
                icon: Icons.eco_outlined,
                fontSize: 24,
                semanticLabel: 'Try it with my twin: ${idea.title}',
                onTap: onTry,
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mochi in the pose for the idea's kind, with a short line from the server's own words.
          IdeaScene(
            key: ValueKey('scene-${idea.id}'),
            appearance: appearance,
            kind: idea.kind,
            bubble: bubble,
            x: bubble == null ? 0.5 : 0.3,
          ),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: WholeWordText(idea.title, style: LtText.display(28)),
          ),
          const SizedBox(height: 14),
          WholeWordText.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Why? ',
                  style: LtText.body(size: 18, weight: FontWeight.w700),
                ),
                TextSpan(text: why, style: LtText.body(size: 18)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          WholeWordText(
            basedOn(idea),
            style: LtText.body(
              weight: FontWeight.w700,
              color: LtColors.secondary,
            ),
          ),
          if (word == null) ...[
            const SizedBox(height: 10),
            const Align(alignment: Alignment.centerLeft, child: GuidelineChip()),
          ] else ...[
            const SizedBox(height: 14),
            Semantics(
              container: true,
              label:
                  'What the model says: $word. $effectNote. Linked, not proven.',
              excludeSemantics: true,
              child: Sheet(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WholeWordText(
                      'What the model says',
                      style: LtText.body(
                        weight: FontWeight.w700,
                        color: LtColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        EffectMeter(effect: idea.effect!, scale: 1.3),
                        const SizedBox(width: 10),
                        Text(word, style: LtText.display(26)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    WholeWordText('$effectNote.', style: LtText.body(size: 18)),
                    const SizedBox(height: 6),
                    WholeWordText.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Linked, not proven. ',
                            style: LtText.body(weight: FontWeight.w700),
                          ),
                          TextSpan(
                            text:
                                'See your own numbers in Try it with my twin.',
                            style: LtText.body(color: LtColors.secondary),
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => showEffectSheet(context, idea.effect!),
                        child: Text(
                          'What does this mean?',
                          style: LtText.body(weight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (url != null) ...[
            const SizedBox(height: 14),
            SourceLink(
              label:
                  '${idea.sourceTitle ?? SourceLink.siteName(url)}${idea.sourceDomain.isEmpty ? '' : ' (${idea.sourceDomain})'}',
              url: url,
              open: open,
            ),
          ],
          if (worded != null) ...[
            const SizedBox(height: 10),
            WholeWordText(
              'Worded with ${worded!.displayName}.${training == null ? '' : ' $training'}',
              style: LtText.body(color: LtColors.secondary),
            ),
          ],
        ],
      ),
    );
  }
}
