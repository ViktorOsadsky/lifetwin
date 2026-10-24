import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/intake_answers.dart';
import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_habitat.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_list.dart';
import '../../widgets/lt_mascot.dart';
import '../../widgets/lt_scaffold.dart';
import '../../widgets/lt_speech_bubble.dart';
import 'intake_script.dart';

/// Where the conversation is. idle -> asking -> typing -> interpreting ->
/// (asking again | confirming) -> ready.
enum IntakePhase { idle, asking, typing, interpreting, confirming, ready }

class _Line {
  const _Line(this.text, {required this.fromPip});
  final String text;
  final bool fromPip;
}

/// F2: text-first mascot conversation. One question at a time, units
/// clarified, voice shown but unavailable.
class IntakeScreen extends ConsumerStatefulWidget {
  const IntakeScreen({super.key});

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> {
  static const _fields = IntakeField.values;

  final _controller = TextEditingController();
  final _lines = <_Line>[];
  Timer? _timer;

  IntakePhase _phase = IntakePhase.idle;
  int _step = 0;

  /// Set while Pip waits for "cm or inches?".
  double? _pendingValue;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 350), () {
      _pip(
        'Hi, I am Pip! I will ask a few quick questions so your twin '
        'starts from the right place. One at a time.',
      );
      _pip(_fields[0].question);
      setState(() => _phase = IntakePhase.asking);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _pip(String text) {
    _lines.add(_Line(text, fromPip: true));
  }

  bool get _canSend =>
      _phase == IntakePhase.asking || _phase == IntakePhase.typing;

  void _send(String text) {
    if (!_canSend || text.trim().isEmpty) return;
    _controller.clear();
    setState(() {
      _lines.add(_Line(text.trim(), fromPip: false));
      _phase = IntakePhase.interpreting;
    });
    _timer = Timer(const Duration(milliseconds: 500), () => _handle(text));
  }

  void _handle(String text) {
    final field = _fields[_step];
    final answers = ref.read(intakeAnswersProvider);
    final pending = _pendingValue;
    final result = pending != null
        ? resolveUnit(field, pending, text, answers)
        : interpret(field, text, answers);
    setState(() {
      switch (result) {
        case Accepted(answers: final next):
          ref.read(intakeAnswersProvider.notifier).set(next);
          _pendingValue = null;
          _step++;
          if (_step >= _fields.length) {
            _pip(
              'That is everything. Let me show you what I heard, so you can '
              'fix anything I got wrong.',
            );
            _phase = IntakePhase.confirming;
          } else {
            _pip(_fields[_step].question);
            _phase = IntakePhase.asking;
          }
        case NeedsUnit(value: final v):
          _pendingValue = v;
          _pip(unitQuestion(field));
          _phase = IntakePhase.asking;
        case Retry(message: final m):
          _pip(m);
          _phase = IntakePhase.asking;
      }
    });
  }

  MascotState get _mascot => switch (_phase) {
    IntakePhase.idle => MascotState.idle,
    IntakePhase.asking => MascotState.speaking,
    IntakePhase.typing => MascotState.listening,
    IntakePhase.interpreting => MascotState.thinking,
    IntakePhase.confirming || IntakePhase.ready => MascotState.celebrating,
  };

  @override
  Widget build(BuildContext context) {
    final field = _step < _fields.length ? _fields[_step] : null;
    final replies = _pendingValue != null
        ? field!.units
        : (field?.quickReplies ?? const <String>[]);
    return LtPage(
      title: 'Meet Pip',
      sheetToBottom: true,
      child: LayoutBuilder(
        builder: (context, box) {
          // Pip stands in a small meadow that dissolves into the page; the
          // conversation runs below it and the composer rises on one sheet.
          final stageH = (box.maxHeight * 0.28).clamp(128.0, 230.0);
          const tuck = 64.0;
          final pipW = (stageH * 0.5).clamp(56.0, 104.0);
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: stageH + tuck,
                child: Habitat(
                  tier: 2,
                  contactLine: (stageH - 10) / (stageH + tuck),
                  fadeTop: 40,
                  fadeBottom: 120,
                  actors: [
                    HabitatActor(
                      x: 0.5,
                      footprint: pipW * 0.6,
                      lift: 6,
                      child: Mascot(state: _mascot, width: pipW, shadow: false),
                    ),
                  ],
                  overlay: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: LtSpace.s4),
                      child: _ProgressDots(done: _step, total: _fields.length),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                top: stageH,
                child: Column(
                  children: [
                    Expanded(
                      // Older messages feather out under the meadow instead
                      // of being cut by a hard edge.
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (r) => LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            context.colors.bgGround.withValues(alpha: 0),
                            context.colors.bgGround,
                          ],
                          stops: [0, (48 / r.height).clamp(0.0, 1.0)],
                        ).createShader(r),
                        child: ListView(
                          // Newest message at the bottom, always in view.
                          reverse: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: LtSpace.gutter,
                            vertical: LtSpace.s12,
                          ),
                          children: [
                            if (_phase == IntakePhase.interpreting)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: LtSpace.s8,
                                ),
                                child: Text(
                                  'Pip is reading that…',
                                  style: context.text.footnote,
                                ),
                              ),
                            for (final l in _lines.reversed)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: LtSpace.s12,
                                ),
                                child: Align(
                                  alignment: l.fromPip
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                          0.78,
                                    ),
                                    child: LtSpeechBubble(
                                      text: l.text,
                                      fromMascot: l.fromPip,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    LtSheetPanel(
                      grabber: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          LtSpace.gutter,
                          LtSpace.s16,
                          LtSpace.gutter,
                          LtSpace.s8,
                        ),
                        child: _phase == IntakePhase.confirming
                            ? LtButton(
                                label: 'Review my answers',
                                onPressed: () {
                                  setState(() => _phase = IntakePhase.ready);
                                  context.push('/confirm');
                                },
                              )
                            : _phase == IntakePhase.ready
                            ? LtButton(
                                label: 'Review my answers',
                                onPressed: () => context.push('/confirm'),
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (replies.isNotEmpty && _canSend)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: LtSpace.s8,
                                      ),
                                      child: Wrap(
                                        spacing: LtSpace.s8,
                                        runSpacing: LtSpace.s8,
                                        children: [
                                          for (final r in replies)
                                            _QuickReply(
                                              label: r,
                                              onTap: () => _send(r),
                                            ),
                                        ],
                                      ),
                                    ),
                                  _Composer(
                                    controller: _controller,
                                    hint: _pendingValue != null
                                        ? 'Type a unit'
                                        : (field?.hint ?? ''),
                                    enabled: _canSend,
                                    onChanged: (v) {
                                      if (!_canSend) return;
                                      setState(
                                        () => _phase = v.isEmpty
                                            ? IntakePhase.asking
                                            : IntakePhase.typing,
                                      );
                                    },
                                    onSend: () => _send(_controller.text),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Question ${(done + 1).clamp(1, total)} of $total',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: LtSpace.s4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < done ? c.actionPrimary : c.line,
                border: i == done
                    ? Border.all(color: c.actionPrimary, width: 2)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickReply extends StatelessWidget {
  const _QuickReply({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: LtSpace.touch),
          padding: const EdgeInsets.symmetric(horizontal: LtSpace.s16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.chipSelected,
            borderRadius: LtRadius.chipAll,
          ),
          child: Text(
            label,
            style: context.text.subhead.copyWith(color: c.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Voice is not available yet: shown, disabled and labelled.
            Semantics(
              button: true,
              enabled: false,
              label: 'Voice, coming soon',
              excludeSemantics: true,
              child: SizedBox(
                width: LtSpace.touch,
                height: LtSpace.touch,
                child: Center(child: LtIcon(LtIcons.mic, color: c.vizBaseline)),
              ),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: LtSpace.touch),
                padding: const EdgeInsets.symmetric(horizontal: LtSpace.s16),
                decoration: BoxDecoration(
                  color: c.bgSurface,
                  borderRadius: LtRadius.smallAll,
                  border: Border.all(color: c.line),
                ),
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  onChanged: onChanged,
                  onSubmitted: (_) => onSend(),
                  textInputAction: TextInputAction.send,
                  keyboardType: TextInputType.text,
                  style: context.text.body,
                  cursorColor: c.actionPrimary,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: context.text.body.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: LtSpace.s8),
            Semantics(
              button: true,
              enabled: enabled,
              label: 'Send',
              excludeSemantics: true,
              onTap: enabled ? onSend : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? onSend : null,
                child: Container(
                  width: LtSpace.touch,
                  height: LtSpace.touch,
                  decoration: BoxDecoration(
                    color: enabled ? c.actionPrimary : c.line,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: LtIcon(
                      LtIcons.send,
                      color: enabled ? c.bgSurface : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: LtSpace.s4),
          child: Text(
            'Voice coming soon — typing works today.',
            style: context.text.caption,
          ),
        ),
      ],
    );
  }
}
