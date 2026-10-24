import 'package:flutter/material.dart';

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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
              body: _confirmed.isEmpty
                  ? 'I will ask you about each one instead.'
                  : 'You checked ${_confirmed.length} ${_confirmed.length == 1 ? 'reading' : 'readings'}.'
                        '${_toAsk.isEmpty ? '' : ' I will ask you about the rest.'}',
              primary: ('Continue', _finish),
              back: _back,
            ),
          },
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.body, this.primary, this.secondary, this.back, this.busy = false});

  final String title;
  final String body;
  final (String, VoidCallback)? primary;
  final (String, VoidCallback)? secondary;
  final VoidCallback? back;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(title, style: text.headlineMedium)),
                const SizedBox(height: 24),
                Text(body, style: text.titleLarge?.copyWith(height: 1.4)),
                if (busy) ...[const SizedBox(height: 32), const Center(child: CircularProgressIndicator())],
              ],
            ),
          ),
        ),
        if (primary case (final label, final onTap)) _BigButton(label: label, onTap: onTap, filled: true),
        if (secondary case (final label, final onTap)) ...[
          const SizedBox(height: 16),
          _BigButton(label: label, onTap: onTap, filled: false),
        ],
        if (back != null) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: back,
            icon: const Icon(Icons.arrow_back),
            label: Text('Go back', style: text.titleMedium),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ],
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.onTap, required this.filled});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(72)),
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.titleLarge),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
    );
    final child = Text(label, textAlign: TextAlign.center);
    return filled
        ? FilledButton(onPressed: onTap, style: style, child: child)
        : OutlinedButton(onPressed: onTap, style: style, child: child);
  }
}
