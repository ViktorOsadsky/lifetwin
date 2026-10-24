import 'package:flutter/material.dart';

import '../theme/lifetwin_theme.dart';
import '../widgets/lt_buttons.dart';
import '../widgets/lt_icons.dart';
import '../widgets/lt_progress.dart';
import '../widgets/lt_text_link.dart';
import '../widgets/pip.dart';
import '../widgets/scene_paper.dart';
import '../widgets/speech_bubble.dart';

import 'health_reader.dart';
import 'health_sample.dart';
import 'health_summary.dart';
import 'readback.dart';

/// What the import produced. Only [confirmed] values may enter the profile.
class HealthImportResult {
  const HealthImportResult({required this.confirmed, required this.toAsk, required this.samples});

  final List<HealthCandidate> confirmed;

  /// Fields the user said were wrong, or that Apple Health had nothing for:
  /// the mascot asks these in conversation.
  final List<HealthField> toAsk;

  /// Raw samples for the agents (sent through the server once the contract lands).
  final List<HealthSample> samples;
}

/// One question per screen, large type, two big choices.
class HealthImportScreen extends StatefulWidget {
  const HealthImportScreen({super.key, required this.onDone, this.reader, this.now});

  final void Function(HealthImportResult result) onDone;

  /// Defaults to the real Apple Health reader; tests pass a fake.
  final HealthReader? reader;
  final DateTime Function()? now;

  @override
  State<HealthImportScreen> createState() => _HealthImportScreenState();
}

enum _Step { intro, reading, confirm, nothingFound, done }

class _HealthImportScreenState extends State<HealthImportScreen> {
  late final HealthReader _reader = widget.reader ?? HealthReader();
  _Step _step = _Step.intro;
  List<HealthSample> _samples = const [];
  List<HealthCandidate> _candidates = const [];
  int _index = 0;
  final _confirmed = <HealthCandidate>[];
  final _toAsk = <HealthField>[];
  final _answers = <bool>[];

  DateTime get _now => (widget.now ?? DateTime.now)();

  bool get _imperial => usesImperial(WidgetsBinding.instance.platformDispatcher.locale.countryCode);

  Future<void> _start() async {
    setState(() => _step = _Step.reading);
    try {
      await _reader.requestAccess();
      final now = _now;
      _samples = await _reader.read(now: now);
      _candidates = summarize(_samples, now);
    } catch (_) {
      _samples = const [];
      _candidates = const [];
    }
    if (!mounted) return;
    final found = _candidates.map((c) => c.field).toSet();
    _toAsk.addAll(HealthField.values.where((f) => !found.contains(f)));
    setState(() => _step = _candidates.isEmpty ? _Step.nothingFound : _Step.confirm);
  }

  /// Ignores a second tap (e.g. a tremor double-tap) so it can't answer the next question.
  bool _locked = false;

  void _answer(bool accurate) {
    if (_locked) return;
    _locked = true;
    Future.delayed(const Duration(milliseconds: 700), () => _locked = false);
    final c = _candidates[_index];
    if (accurate) {
      _confirmed.add(c);
    } else {
      _toAsk.add(c.field);
    }
    _answers.add(accurate);
    setState(() {
      if (_index + 1 < _candidates.length) {
        _index++;
      } else {
        _step = _Step.done;
      }
    });
  }

  /// Undoes the last answer, so a mistaken tap is never final.
  void _back() {
    if (_answers.isEmpty) return;
    final wasAccurate = _answers.removeLast();
    setState(() {
      if (_step == _Step.confirm) _index--;
      _step = _Step.confirm;
      final c = _candidates[_index];
      wasAccurate ? _confirmed.remove(c) : _toAsk.removeLast();
    });
  }

  void _finish() =>
      widget.onDone(HealthImportResult(confirmed: List.of(_confirmed), toAsk: List.of(_toAsk), samples: _samples));

  void _skip() => widget.onDone(const HealthImportResult(confirmed: [], toAsk: HealthField.values, samples: []));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LtColors.paper,
      body: SafeArea(
        child: switch (_step) {
          _Step.intro => _Page(
            title: "Use your iPhone's Health app?",
            body:
                'I can read your height, weight, exercise, sleep and blood pressure from the Health app, '
                "so you don't have to type them.\n\n"
                "I'll check each one with you. The readings are also sent to LifeTwin's assistant, "
                'an AI service, so it can give you advice.',
            primary: ('Yes, use my Health app', _start),
            secondary: ("No thanks, I'll answer myself", _skip),
          ),
          _Step.reading => const _Page(
            title: 'Reading your Health app…',
            body: 'This takes a few seconds.',
            busy: true,
          ),
          _Step.confirm => _Page(
            title: 'Question ${_index + 1} of ${_candidates.length}',
            step: (_index + 1, _candidates.length),
            body: readBack(_candidates[_index], imperial: _imperial, now: _now),
            primary: (confirmLabel, () => _answer(true)),
            secondary: (fixLabel, () => _answer(false)),
            back: _answers.isEmpty ? null : _back,
          ),
          _Step.nothingFound => _Page(
            title: "I couldn't find any readings",
            body:
                "That's okay. Either the Health app has no readings yet, or it isn't sharing them with LifeTwin. "
                'You can change that later in the Health app. For now, I will ask you instead.',
            primary: ('Continue', _finish),
          ),
          _Step.done => _Page(
            title: 'Thank you',
            mood: PipMood.pleased,
            body: _confirmed.isEmpty
                ? 'I will ask you about each one instead.'
                : 'You checked ${_confirmed.length} ${_confirmed.length == 1 ? 'reading' : 'readings'}.'
                      '${_toAsk.isEmpty ? '' : ' I will ask you about the rest.'}',
            primary: ('Continue', _finish),
            back: _back,
          ),
        },
      ),
    );
  }
}

/// One step of the import, in the conversation's style: a title (or the question
/// count), Pip's words in a bubble with Pip on the paper below, and the big
/// buttons pinned at the bottom.
class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.body,
    this.primary,
    this.secondary,
    this.back,
    this.busy = false,
    this.step,
    this.mood = PipMood.asking,
  });

  final String title;
  final String body;
  final (String, VoidCallback)? primary;
  final (String, VoidCallback)? secondary;
  final VoidCallback? back;
  final bool busy;

  /// (question, of) when the title is "Question N of M": shown as the progress line.
  final (int, int)? step;
  final PipMood mood;

  static Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: LtSpace.gutter),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final pip = Pip(mood: mood, height: big ? 70 : 104);
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Words scroll; Pip's scene sits at the bottom, just above the buttons.
          Expanded(
            child: LayoutBuilder(
              builder: (context, area) => SingleChildScrollView(
                padding: const EdgeInsets.only(top: LtSpace.xl),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: (area.maxHeight - LtSpace.xl).clamp(0, double.infinity)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (step case (final n, final of))
                            _pad(
                              Semantics(
                                header: true,
                                child: LtStepProgress(step: n, total: of, trailing: big ? pip : null),
                              ),
                            )
                          else
                            _pad(
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Semantics(header: true, child: Text(title, style: LtText.title)),
                                  ),
                                  if (big) pip,
                                ],
                              ),
                            ),
                          const SizedBox(height: LtSpace.xl),
                          _pad(
                            SpeechBubble(
                              tail: big ? BubbleTail.none : BubbleTail.down,
                              child: Semantics(
                                liveRegion: true,
                                container: true,
                                child: Text(body, style: step == null ? LtText.body : LtText.bubble),
                              ),
                            ),
                          ),
                          if (busy) ...[
                            const SizedBox(height: LtSpace.xl),
                            const Center(child: CircularProgressIndicator(strokeWidth: 5)),
                          ],
                          const SizedBox(height: LtSpace.lg),
                        ],
                      ),
                      if (!big) ScenePaper(height: 132, child: Positioned(left: 62, bottom: 6, child: pip)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.6),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(LtSpace.gutter, LtSpace.sm, LtSpace.gutter, LtSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (primary case (final label, final onTap)) LtPrimaryButton(label: label, onPressed: onTap),
                  if (secondary case (final label, final onTap)) ...[
                    const SizedBox(height: LtSpace.buttonGap),
                    LtSecondaryButton(label: label, onPressed: onTap),
                  ],
                  if (back != null) ...[
                    const SizedBox(height: LtSpace.xs),
                    Center(
                      child: LtTextLink(
                        label: 'Go back',
                        icon: const LtIcon(LtIconKind.back, size: 26, strokeWidth: 2.8),
                        onPressed: back,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
