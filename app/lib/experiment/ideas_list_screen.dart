import 'package:flutter/material.dart';

import '../checkin/consents.dart' show AiProvider;
import '../onboarding/missing_answers.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import '../widgets/whole_word_text.dart';
import 'answers.dart';
import 'experiment_page.dart';
import 'experiment_twins.dart';
import 'idea_detail_screen.dart';
import 'lever_copy.dart';
import 'recommendations.dart';
import 'widgets/idea_card.dart';
import 'widgets/widgets.dart';

/// "Ideas for you" (design set I): up to three ideas from `/api/recommendations`, the most
/// helpful first. Loads [source] itself, and shows the calm offline / error screen (I-6) when
/// it fails and the "a few more answers" screen (I-3) when there is nothing to say yet.
///
/// The person's age is the caller's business: under 18 this screen is never built (it would
/// never call the server), and no entry point to it exists.
class IdeasListScreen extends StatefulWidget {
  const IdeasListScreen({
    super.key,
    required this.source,
    required this.appearance,
    required this.origin,
    required this.onBack,
    required this.onTry,
    this.missingInputs = const [],
    this.onAnswerMore,
    this.questionCount,
    this.worded,
    this.open = defaultOpenUrl,
  });

  final RecommendationsSource source;
  final TwinAppearance appearance;

  /// Where this screen was opened from ("room", "Today", "what moves it", "Experiment"):
  /// the back button says "Back to {origin}".
  final String origin;
  final VoidCallback onBack;

  /// "Try it with my twin": opens the lever. Null value: open it without a preset.
  final void Function(Recommendation idea) onTry;

  /// Model inputs still missing (`missing_inputs`), for the "a few more answers" screen.
  final List<String> missingInputs;

  /// Opens the conversation with Mochi that asks for the missing answers ("Answer N more
  /// questions").
  final VoidCallback? onAnswerMore;

  /// The questions it asks (height and weight are two); [missingInputs].length when null.
  final int? questionCount;

  /// The outside AI that worded the ideas, when the person agreed to it; null otherwise. Its
  /// training line shows only when `may_train_on_content` is true.
  final AiProvider? worded;
  final OpenUrl open;

  @override
  State<IdeasListScreen> createState() => _IdeasListScreenState();
}

class _IdeasListScreenState extends State<IdeasListScreen> {
  List<Recommendation>? _ideas;
  RecommendationsFailure? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final ideas = await widget.source.load();
      if (mounted) setState(() => _ideas = ideas);
    } on RecommendationsFailure catch (f) {
      if (mounted) setState(() => _failure = f);
    } catch (_) {
      if (mounted) {
        setState(() => _failure = const RecommendationsFailure(null));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _backLabel => 'Back to ${widget.origin}';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _plate('One moment…', 'Mochi is looking for ideas.', null, null);
    }
    if (_failure != null) {
      final offline = _failure!.statusCode == null;
      return _plate(
        'Ideas didn’t load.',
        'Your answers are safe.',
        offline ? 'Check your connection, then try again.' : 'Something went wrong on our side. Try again.',
        LipButton(label: 'Try again', icon: Icons.refresh_rounded, fontSize: 24, onTap: _load),
      );
    }
    final ideas = _ideas ?? const <Recommendation>[];
    if (ideas.isEmpty) return _notYet();
    return _list(ideas);
  }

  Widget _plate(String bubble, String heading, String? body, Widget? action) => ExperimentPage(
    title: 'Ideas for you',
    onBack: widget.onBack,
    backLabel: _backLabel,
    dock: action == null
        ? null
        : Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom), child: action),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExperimentPlate(
          appearance: widget.appearance,
          twins: const [TwinSlot(state: steadyTwin, x: 0.3)],
          bubble: bubble,
        ),
        const SizedBox(height: 14),
        Semantics(header: true, child: WholeWordText(heading, style: LtText.display(26))),
        if (body != null) ...[const SizedBox(height: 6), WholeWordText(body, style: LtText.body(size: 18))],
      ],
    ),
  );

  /// I-3: nothing to say yet. The rows are the model inputs still missing, in plain words.
  Widget _notYet() {
    final n = widget.missingInputs.length;
    return ExperimentPage(
      title: 'Ideas for you',
      onBack: widget.onBack,
      backLabel: _backLabel,
      dock: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
        child: LipButton(
          label: n > 0 ? answerMoreLabel(widget.questionCount ?? n) : 'Talk to Mochi',
          icon: Icons.chat_bubble_outline_rounded,
          fontSize: 24,
          onTap: widget.onAnswerMore,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: widget.appearance,
            twins: const [TwinSlot(state: steadyTwin, x: 0.3)],
            bubble: 'Not yet!',
          ),
          const SizedBox(height: 14),
          Semantics(header: true, child: WholeWordText('A few more answers', style: LtText.display(26))),
          const SizedBox(height: 6),
          WholeWordText(
            'Once I know a little more about your days, I’ll have some ideas for you. There’s no rush.',
            style: LtText.body(size: 18),
          ),
          if (n > 0) ...[
            const SizedBox(height: 14),
            Sheet(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (final (i, m) in widget.missingInputs.indexed) ...[
                    if (i > 0) const Divider(height: 1, color: Color(0xFFE9DFD0)),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 64),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: LtColors.control, width: 2),
                            ),
                            child: Icon(_icon(m), size: 24, color: LtColors.ink),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: WholeWordText(
                              Answers.label(m),
                              style: LtText.body(size: 18, weight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _icon(String input) => LeverCopy.of(input)?.icon ?? Icons.help_outline_rounded;

  Widget _list(List<Recommendation> ideas) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final anyEffect = ideas.any((i) => effectWord(i.effect) != null);
    final training = widget.worded?.trainingLine;
    return ExperimentPage(
      title: 'Ideas for you',
      onBack: widget.onBack,
      backLabel: _backLabel,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scale < 1.5) ...[
            Row(
              children: [
                _MochiHead(appearance: widget.appearance),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: LtColors.paper,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: LtColors.container, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mochi', style: LtText.body(color: LtColors.secondary)),
                        WholeWordText(
                          ideas.length == 1 ? 'One idea for you.' : '${_word(ideas.length)} ideas, most helpful first.',
                          style: LtText.body(size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // The effect note stays on the first screen, above the first card.
          if (anyEffect) ...[
            WholeWordText('$effectNote.', style: LtText.body(color: LtColors.secondary)),
            const SizedBox(height: 8),
          ],
          for (final (i, idea) in ideas.indexed) ...[
            if (i > 0) const SizedBox(height: 14),
            IdeaCard(
              idea: idea,
              top: i == 0,
              onOpen: () => _openDetail(idea),
              onEffect: () => showEffectSheet(context, idea.effect!),
              onTry: idea.leverId == null ? null : () => widget.onTry(idea),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: WholeWordText(
                  'Linked, not proven.',
                  style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
                ),
              ),
              Text('  ·  ', style: LtText.body(color: LtColors.secondary)),
              _AboutLink(onTap: () => showAboutSheet(context)),
            ],
          ),
          if (widget.worded != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.auto_awesome_outlined, size: 20, color: LtColors.secondary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: WholeWordText(
                    'Worded with ${widget.worded!.displayName}.${training == null ? '' : ' $training'}',
                    style: LtText.body(color: LtColors.secondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _word(int n) => switch (n) {
    2 => 'Two',
    3 => 'Three',
    _ => '$n',
  };

  void _openDetail(Recommendation idea) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (c) => IdeaDetailScreen(
        idea: idea,
        appearance: widget.appearance,
        backLabel: 'Back to ideas',
        worded: widget.worded,
        open: widget.open,
        onBack: () => Navigator.of(c).pop(),
        onTry: idea.leverId == null ? null : () => widget.onTry(idea),
      ),
    ),
  );
}

class _MochiHead extends StatelessWidget {
  const _MochiHead({required this.appearance});
  final TwinAppearance appearance;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 64,
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFEEE8FB),
        border: Border.all(color: LtColors.control, width: 2),
      ),
      child: OverflowBox(
        maxWidth: 110,
        maxHeight: 110,
        alignment: const Alignment(0, -0.2),
        child: TwinStateSprite(state: steadyTwin, appearance: appearance, height: 110),
      ),
    ),
  );
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'About this',
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Center(
          child: Text(
            'About this ›',
            style: LtText.body(weight: FontWeight.w700)
                .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
          ),
        ),
      ),
    ),
  );
}

/// I-8: what an effect level means: the level, the server's note, "Linked, not proven.".
Future<void> showEffectSheet(BuildContext context, String effect) {
  final word = effectWord(effect) ?? '';
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: LtColors.paper,
            borderRadius: BorderRadius.circular(LtRadii.panel),
            border: Border.all(color: LtColors.container, width: LtBorders.container),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    EffectMeter(effect: effect, scale: 1.3),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(header: true, child: Text(word, style: LtText.display(28))),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                WholeWordText('$effectNote.', style: LtText.body(size: 18)),
                const SizedBox(height: 8),
                WholeWordText.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Linked, not proven.',
                        style: LtText.body(weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LipButton(
                  label: 'Got it',
                  kind: LipKind.secondary,
                  height: 56,
                  fontSize: 20,
                  onTap: () => Navigator.of(c).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// "About this": what these ideas can and cannot say.
Future<void> showAboutSheet(BuildContext context) => showInfoSheet(
  context,
  title: 'About these ideas',
  body:
      'Linked, not proven. Suggestions follow public-health guidance and the model’s lever ranking; '
      'they are not medical advice and promise no benefit. The model compares similar people over one to '
      'five years; it does not show what a change would do for you. The server keeps nothing. '
      'Habit notes and history stay on your phone.',
);
