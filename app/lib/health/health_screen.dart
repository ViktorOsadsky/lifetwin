import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import '../widgets/whole_word_text.dart';

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
  const HealthImportScreen({
    super.key,
    required this.onDone,
    this.reader,
    this.now,
    this.appearance = const TwinAppearance(),
  });

  final void Function(HealthImportResult result) onDone;

  /// Defaults to the real Apple Health reader; tests pass a fake.
  final HealthReader? reader;
  final DateTime Function()? now;

  /// Cosmetic look of the twin beside the words.
  final TwinAppearance appearance;

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
    return ModeScaffold(
      mode: LtMode.onboarding,
      child: _Twin(
        appearance: widget.appearance,
        child: switch (_step) {
          _Step.intro => _Page(
            title: 'Use Apple Health?',
            body:
                'I can read your height, weight, exercise, sleep and blood pressure from Apple Health, '
                "so you don't have to type them.\n\n"
                "I'll check each one with you, and only the ones you say are right are used.",
            primary: ('Yes, use Apple Health', _start),
            secondary: ("No thanks, I'll answer myself", _skip),
          ),
          _Step.reading => const _Page(title: 'Reading Apple Health…', body: 'This takes a few seconds.', busy: true),
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
                "That's okay. Either Apple Health has no readings yet, or it isn't sharing them with LifeTwin. "
                'You can change that later in Apple Health. For now, I will ask you instead.',
            primary: ('Continue', _finish),
          ),
          _Step.done => _Page(
            title: 'Thank you',
            mood: TwinMood.pleased,
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

/// Passes the twin's look down to each step.
class _Twin extends InheritedWidget {
  const _Twin({required this.appearance, required super.child});
  final TwinAppearance appearance;

  static TwinAppearance of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Twin>()?.appearance ?? const TwinAppearance();

  @override
  bool updateShouldNotify(_Twin old) => old.appearance != appearance;
}

/// One step of the import, in the conversation's style: a title (or the question
/// count), the twin's words in a bubble with the twin beside them, and the big
/// buttons pinned at the bottom on the sheet.
class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.body,
    this.primary,
    this.secondary,
    this.back,
    this.busy = false,
    this.step,
    this.mood = TwinMood.asking,
  });

  final String title;
  final String body;
  final (String, VoidCallback)? primary;
  final (String, VoidCallback)? secondary;
  final VoidCallback? back;
  final bool busy;

  /// (question, of) when the title is "Question N of M": shown as the progress line.
  final (int, int)? step;
  final TwinMood mood;

  static Widget _pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child);

  @override
  Widget build(BuildContext context) {
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final twin = TwinSprite(appearance: _Twin.of(context), pose: mood.pose, height: big ? 80 : 120);
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The words scroll; the buttons stay in reach.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 20, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (step case (final n, final of))
                    _pad(
                      Semantics(
                        header: true,
                        child: StepProgress(step: n, total: of),
                      ),
                    )
                  else
                    _pad(Semantics(header: true, child: WholeWordText(title, style: LtText.display(30)))),
                  const SizedBox(height: 16),
                  _pad(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        twin,
                        const SizedBox(width: 4),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            container: true,
                            child: Bubble(
                              text: body,
                              tail: BubbleTail.left,
                              tailAt: 1,
                              fontSize: step == null ? 20 : 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (busy) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator(strokeWidth: 5, color: LtColors.ink)),
                  ],
                ],
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: primary == null && secondary == null && back == null
                  ? const SizedBox.shrink()
                  : Sheet(
                      padding: EdgeInsets.zero,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (primary case (final label, final onTap))
                              LipButton(label: label, height: 72, onTap: onTap),
                            if (secondary case (final label, final onTap)) ...[
                              const SizedBox(height: 12),
                              LipButton(label: label, kind: LipKind.secondary, height: 72, onTap: onTap),
                            ],
                            if (back != null) ...[
                              const SizedBox(height: 4),
                              Center(
                                child: LinkButton(label: 'Go back', icon: Icons.undo_rounded, onTap: back),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
