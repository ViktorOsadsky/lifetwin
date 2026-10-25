import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart';
import '../wellness/widgets.dart';
import 'quiz_game.dart';

/// Three-question rounds. A selected answer is checked explicitly. Practice never
/// scores again, and only acknowledging an explanation recovers game health.
class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.onBack,
    this.game,
    this.appearance = const TwinAppearance(),
  });
  final VoidCallback onBack;
  final QuizGame? game;
  final TwinAppearance appearance;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  QuizGame? _game;
  bool _failed = false;
  bool _started = false;
  bool _why = false;
  bool _practice = false;
  bool _checked = false;
  String? _selected;
  int _index = 0;
  int _round = 0;
  late List<QuizQuestion> _questions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final game = widget.game ?? QuizGame(await loadReviewedQuiz());
      if (!mounted) {
        if (widget.game == null) game.dispose();
        return;
      }
      if (game.questions.isEmpty) {
        throw const FormatException('No reviewed questions');
      }
      setState(() {
        _game = game;
        _newRound();
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _newRound() {
    final all = _game!.questions;
    _questions = List.generate(
      all.length.clamp(1, 3),
      (i) => all[(_round * 3 + i) % all.length],
    );
    _index = 0;
    _selected = null;
    _checked = false;
    _why = false;
    _practice = false;
  }

  Future<void> _leave() async {
    if (_started && _index < _questions.length) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Leave this round?'),
          content: const Text(
            'Your game health stays as it is. Come back whenever you like.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep playing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Leave quiz'),
            ),
          ],
        ),
      );
      if (leave != true) return;
    }
    if (mounted) widget.onBack();
  }

  @override
  void dispose() {
    if (widget.game == null) _game?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_started || _index >= (_game == null ? 0 : _questions.length),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: WellnessPage(
      key: ValueKey('quiz-$_started-$_index-$_practice'),
      title: 'Quick quiz',
      onBack: _leave,
      children: [
        if (_game == null && !_failed)
          const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Loading questions',
            ),
          ),
        if (_failed) ...[
          const MochiMessage(message: 'Couldn’t check. No points lost.'),
          LipButton(label: 'Try again', onTap: _load),
        ],
        if (_game case final game?)
          ListenableBuilder(
            listenable: game,
            builder: (context, _) => _content(game),
          ),
      ],
    ),
  );

  Widget _content(QuizGame game) {
    if (!_started) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MochiMessage(
            message: 'Quiz time! Ready?',
            appearance: widget.appearance,
          ),
          WellnessCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_questions.length} questions · Food labels and food safety',
                  style: LtText.body(weight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  'Just a game. Your outlook doesn’t change.',
                  style: LtText.body(),
                ),
              ],
            ),
          ),
          LipButton(
            label: 'Start quiz',
            onTap: () => setState(() => _started = true),
          ),
          LinkButton(label: 'Not now', onTap: widget.onBack),
        ],
      );
    }
    if (_index >= _questions.length) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MochiMessage(
            message: 'Round done. Nice exploring!',
            appearance: widget.appearance,
            pose: TwinPose.wave,
          ),
          _health(game),
          for (final q in _questions)
            WellnessCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(q.scenario),
                subtitle: Text(
                  game.reviewed(q)
                      ? 'Learned'
                      : game.answerFor(q) == q.correctId
                      ? 'Right'
                      : 'Read why',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _reviewSheet(q),
              ),
            ),
          LipButton(
            label: 'New round',
            onTap: () => setState(() {
              _round++;
              _newRound();
            }),
          ),
          LinkButton(label: 'Back to room', onTap: widget.onBack),
        ],
      );
    }
    final q = _questions[_index];
    final recorded = game.answerFor(q);
    final practicing = _practice || recorded != null && !_checked;
    final answer = _checked ? _selected : null;
    final wrong = answer != null && answer != q.correctId;
    final recovered = game.reviewed(q);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _health(game),
        MochiMessage(
          appearance: widget.appearance,
          pose: wrong && !recovered && !_practice
              ? TwinPose.dizzy
              : TwinPose.wave,
          message: !_checked
              ? 'Take your time.'
              : _practice
              ? 'Practice time. Let’s check the answer.'
              : wrong && !recovered
              ? 'Oops! I feel a bit tired.'
              : recovered
              ? 'All better. Thank you!'
              : 'You got it!',
        ),
        WellnessCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_index + 1} of ${_questions.length}${practicing ? ' · Practice · No score' : ''}',
                style: LtText.body(size: 15),
              ),
              const SizedBox(height: 12),
              Text(
                q.scenario,
                style: LtText.body(size: 20, weight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              for (final option in q.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LipButton(
                    label:
                        '${option['text']}${answer == option['id']
                            ? ' · Your pick'
                            : _checked && option['id'] == q.correctId
                            ? ' · Answer'
                            : ''}',
                    kind: _selected == option['id']
                        ? LipKind.active
                        : LipKind.secondary,
                    fontSize: 18,
                    onTap: _checked
                        ? null
                        : () => setState(
                            () => _selected = option['id'] as String,
                          ),
                  ),
                ),
              if (!_checked)
                LipButton(
                  label: 'Check my answer',
                  onTap: _selected == null
                      ? null
                      : () {
                          game.answer(q, _selected!);
                          setState(() {
                            _checked = true;
                            _practice = practicing;
                            _why = _selected == q.correctId;
                          });
                        },
                ),
              if (_checked && !_why)
                LinkButton(
                  label: 'Read why',
                  onTap: () => setState(() => _why = true),
                ),
              if (_why) ...[
                Text(q.explanation, style: LtText.body()),
                ..._sources(q),
                if (wrong && !recovered)
                  LipButton(label: 'Got it', onTap: () => game.review(q)),
              ],
            ],
          ),
        ),
        if (_checked) ...[
          if (recovered)
            LinkButton(
              label: 'Try again for practice · No score',
              onTap: () => setState(() {
                _practice = true;
                _checked = false;
                _selected = null;
                _why = false;
              }),
            ),
          LipButton(
            label: _index + 1 == _questions.length
                ? 'Round done'
                : 'Next question',
            onTap: () => setState(() {
              _index++;
              _selected = null;
              _checked = false;
              _why = false;
              _practice = false;
            }),
          ),
        ],
      ],
    );
  }

  Widget _health(QuizGame game) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            'Game health ${game.gameHealth} / 100',
            style: LtText.body(weight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Just a game. Your outlook doesn’t change.',
          style: LtText.body(size: 15),
        ),
      ],
    ),
  );

  List<Widget> _sources(QuizQuestion q) => [
    for (final s in q.sources)
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(s['url'] as String),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text('${s['publisher']}: ${s['title']}'),
        ),
      ),
  ];

  Future<void> _reviewSheet(QuizQuestion q) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(q.scenario, style: LtText.display(24)),
          const SizedBox(height: 16),
          Text(q.explanation, style: LtText.body()),
          ..._sources(q),
          LipButton(
            label: 'Got it',
            onTap: () {
              _game!.review(q);
              Navigator.pop(c);
            },
          ),
        ],
      ),
    ),
  );
}
