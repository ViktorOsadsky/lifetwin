import 'package:flutter/material.dart';

import '../experiment/experiment_page.dart';
import '../experiment/experiment_twins.dart';
import '../experiment/widgets/widgets.dart';
import '../twin/twin_model.dart' show TwinAssessment;
import '../twin/twin_repository.dart';
import '../twin/twin_state.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart' hide TwinMood;
import '../widgets/whole_word_text.dart';
import 'check_in.dart';
import 'checkin_controller.dart';
import 'emergency_card.dart';
import 'outlook_change.dart';
import 'readback_adapter.dart';
import 'updated_card.dart';

/// Mochi's short line in the bubble for the field being asked (the full question sits in the card).
String bubbleFor(
  String? field, {
  required bool confirming,
  required bool done,
  required bool weekly,
  bool finalReadback = false,
}) {
  if (done) return weekly ? 'Your week is in.' : 'Thanks for checking in!';
  if (finalReadback) return 'Here’s what I heard.';
  if (confirming) return 'Did I get that right?';
  return switch (field) {
    'wellbeing' => 'How are you feeling?',
    'sleep_hours_last_night' || 'sleep_hours' => 'How did you sleep?',
    'vigorous_recreation_min' || 'moderate_recreation_min' => 'Did you move?',
    'vigorous_recreation_min_week' || 'moderate_recreation_min_week' => 'How active was your week?',
    'sedentary_min_day' => 'How much sitting?',
    _ => 'Got a minute?',
  };
}

/// The check-in chat: Mochi asks one question at a time, with tap answers, voice or the keyboard, and Skip.
/// It is driven by the engine's `CheckinController`, which saves the finished check-in exactly once.
///
/// A tapped answer is the answer: the chat confirms it for the person. A spoken or typed answer is read back
/// with "Yes" / "Not quite", and an Apple Health value with "Looks right" / "Not quite". An emergency pauses
/// calmly ("Call 911" is a tapped `tel:` link, never dialled for you). When a weekly check-in finishes, how
/// the outlook moved shows (Z-17).
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({
    super.key,
    required this.controller,
    required this.kind,
    required this.repository,
    required this.appearance,
    required this.onDone,
    this.open = defaultOpenUrl,
    this.readback = const ServerReadback(),
  });

  final CheckinController controller;
  final CheckInKind kind;
  final TwinRepository repository;
  final TwinAppearance appearance;
  final VoidCallback onDone;
  final OpenUrl open;

  /// How the server's read-back is listed.
  final ReadbackAdapter readback;

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _text = TextEditingController();
  TwinAssessment? _before;
  bool _nothing = false;
  bool _starting = true;

  CheckinController get c => widget.controller;
  bool get weekly => widget.kind == CheckInKind.weekly;

  @override
  void initState() {
    super.initState();
    _before = widget.repository.current;
    c.start(kind: widget.kind.name).then((ok) {
      if (mounted) {
        setState(() {
          _starting = false;
          _nothing = !ok;
        });
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    c.submitTyped(t);
  }

  // A tapped answer is heard like a spoken or typed one; quick and daily check-ins read everything back once, at the end.
  Future<void> _quick(String words) => c.submitQuick(words);

  bool get _finished => c.turn?.complete ?? false;

  /// "Stop for today" was chosen after Mochi's care reply.
  bool _stopped = false;

  /// Back to the Room; after "Stop for today" Mochi says it is okay.
  void _leave() {
    if (_stopped && _finished) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('That’s okay. I saved what you told me.')));
    }
    widget.onDone();
  }

  TwinState _twin() {
    if (c.emergency) {
      return const TwinState(mood: TwinMood.concerned, pose: TwinPose.stand, reason: TwinStateReason.emergency);
    }
    if (_finished) return widget.repository.twinState();
    return curiousTwin;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => ExperimentPage(
      mode: LtMode.room,
      onBack: c.emergency ? c.continueAfterEmergency : widget.onDone,
      backLabel: c.emergency ? 'Continue' : 'Back',
      dock: _dock(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: widget.appearance,
            twins: [TwinSlot(state: _twin(), x: 0.3)],
            bubble: c.emergency
                ? EmergencyCard.apology
                : _nothing
                ? 'All set for today!'
                : bubbleFor(
                    c.turn?.currentField,
                    confirming: c.confirming,
                    done: _finished,
                    weekly: weekly,
                    finalReadback: c.finalReadback,
                  ),
          ),
          const SizedBox(height: 14),
          Sheet(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: c.emergency
                ? EmergencyCard(onContinue: c.continueAfterEmergency, picksUpAt: c.mascotLine, open: widget.open)
                : _card(context),
          ),
        ],
      ),
    ),
  );

  Widget _title(String text) => Semantics(header: true, child: Text(text, style: LtText.display(28)));

  Widget _card(BuildContext context) {
    final label = weekly ? 'Weekly check-in' : 'Check in';
    if (_nothing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('All set for today'),
          WholeWordText('Nothing more to ask. See you tomorrow.', style: LtText.body(color: LtColors.secondary)),
        ],
      );
    }
    if (_starting || c.turn == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(label),
          WholeWordText(c.notice ?? 'One moment…', style: LtText.body(color: LtColors.secondary)),
          if (c.canRetry) ...[const SizedBox(height: 10), LipButton(label: 'Try again', fontSize: 22, onTap: c.retry)],
        ],
      );
    }
    if (_finished) return _done(context);
    final q = c.questionNumber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _title(label)),
            if (q != null) _Dots(total: q.$2, position: q.$1),
          ],
        ),
        WholeWordText(weekly ? 'A few minutes' : 'About 1 minute', style: LtText.body(color: LtColors.secondary)),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: LtColors.paper,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: LtColors.container, width: 1.5),
            ),
            child: WholeWordText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Mochi  ',
                    style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
                  ),
                  TextSpan(text: c.mascotLine, style: LtText.body()),
                ],
              ),
            ),
          ),
        ),
        if (c.finalReadback) ...[
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text('Here’s what I heard', style: LtText.body(weight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          _AnswerList(items: widget.readback.items(c.turn!)),
        ] else if (!c.confirming && c.heardAnswers.isNotEmpty) ...[
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(
              'So far',
              style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
            ),
          ),
          const SizedBox(height: 6),
          _AnswerList(items: widget.readback.heard(c.turn!)),
        ],
        if (c.phase == CheckinPhase.listening && c.caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          WholeWordText('“${c.caption}”', style: LtText.body(color: LtColors.secondary)),
        ],
        if (c.notice != null) ...[
          const SizedBox(height: 8),
          WholeWordText(c.notice!, style: LtText.body(color: LtColors.secondary)),
        ],
        if (c.canRetry) ...[
          const SizedBox(height: 8),
          LipButton(label: 'Try again', kind: LipKind.secondary, height: 56, fontSize: 20, onTap: c.retry),
        ],
      ],
    );
  }

  Widget _done(BuildContext context) {
    final change = weekly ? OutlookChange.between(_before, widget.repository.current) : null;
    final confirmed = Map<String, dynamic>.from(c.turn?.state['confirmed'] as Map? ?? const {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(weekly ? 'Outlook updated' : 'All done'),
        const SizedBox(height: 8),
        if (change != null)
          OutlookChangeCard(change: change)
        else
          WholeWordText(
            widget.repository.twinState().mood == TwinMood.cheerful ? 'See you tomorrow!' : 'Thanks for telling me.',
            style: LtText.body(),
          ),
        if (weekly && confirmed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text('Your confirmed week', style: LtText.body(weight: FontWeight.w700)),
          ),
          ConfirmedWeek(confirmed: confirmed),
        ],
        if (c.progress != null && c.progress!.goodWeeks > 0) ...[
          const SizedBox(height: 10),
          WholeWordText(
            c.progress!.goodWeeks == 1 ? '1 good week so far' : '${c.progress!.goodWeeks} good weeks so far',
            style: LtText.body(weight: FontWeight.w700),
          ),
        ],
        if (c.offerReminder) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: LtColors.paper,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: LtColors.container, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WholeWordText(
                  'Would you like a gentle reminder each day?',
                  style: LtText.body(weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: LipButton(
                        label: 'Not now',
                        kind: LipKind.secondary,
                        height: 56,
                        fontSize: 19,
                        onTap: c.declineReminders,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LipButton(label: 'Yes', height: 56, fontSize: 19, onTap: c.acceptReminders),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _dock(BuildContext context) {
    final pad = EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom);
    if (c.emergency) return const SizedBox.shrink();
    if (_nothing || _finished) {
      return Padding(
        padding: pad,
        child: LipButton(label: 'Back to my room', fontSize: 24, onTap: _leave),
      );
    }
    if (c.turn == null) return const SizedBox.shrink();
    final busy = c.phase == CheckinPhase.interpreting;
    if (c.careQuestionOpen) {
      // Two equal choices, no red: the warm reply (with the soft 911 line) is Mochi's bubble above.
      return Padding(
        padding: pad,
        child: Row(
          children: [
            Expanded(
              child: LipButton(
                label: 'Stop for today',
                kind: LipKind.secondary,
                fontSize: 20,
                onTap: busy
                    ? null
                    : () {
                        _stopped = true;
                        c.submitQuick('stop');
                      },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LipButton(
                label: 'Keep going',
                fontSize: 20,
                onTap: busy ? null : () => c.submitQuick('keep going'),
              ),
            ),
          ],
        ),
      );
    }
    // A yes or no is open (the final read-back, a check on an unusual value, Apple Health's value, or a weekly
    // answer), unless the person is saying what to change.
    final yesNo = (c.confirming || c.confirmingHealth) && !c.correcting;
    return Padding(
      padding: pad,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (yesNo) ...[
            Row(
              children: [
                Expanded(
                  child: LipButton(
                    label: c.finalReadback ? 'Change with Mochi' : 'Not quite',
                    icon: c.finalReadback ? Icons.chat_bubble_outline_rounded : null,
                    kind: LipKind.secondary,
                    fontSize: c.finalReadback ? 18 : 20,
                    onTap: busy ? null : c.change,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LipButton(
                    label: c.confirmingHealth ? 'Looks right' : (c.finalReadback ? 'Looks right' : 'Yes'),
                    icon: Icons.check_rounded,
                    fontSize: 20,
                    onTap: busy ? null : c.confirm,
                  ),
                ),
              ],
            ),
            if (c.checkQuestion || (c.finalReadback && c.canGoBack)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  // An unusual value can be dropped; the final read-back can reopen an earlier question.
                  if (c.checkQuestion)
                    _Chip(label: 'Skip', icon: Icons.keyboard_double_arrow_right_rounded, onTap: busy ? null : c.skip),
                  if (c.finalReadback && c.canGoBack)
                    _Chip(label: 'Go back', icon: Icons.undo_rounded, onTap: busy ? null : c.goBack),
                ],
              ),
            ],
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.correcting)
                  _Chip(label: 'Keep it', icon: Icons.check_rounded, onTap: c.keepAnswer)
                else ...[
                  for (final (label, words) in c.quickAnswers)
                    _Chip(label: label, onTap: busy ? null : () => _quick(words)),
                  _Chip(label: 'Skip', icon: Icons.keyboard_double_arrow_right_rounded, onTap: busy ? null : c.skip),
                  if (c.canGoBack) _Chip(label: 'Go back', icon: Icons.undo_rounded, onTap: busy ? null : c.goBack),
                ],
              ],
            ),
            const SizedBox(height: 10),
            if (c.typing || !c.voiceUsable)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(hintText: c.correcting ? 'What should it be?' : 'Type your answer'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(52, 52),
                      backgroundColor: LtColors.mint,
                      foregroundColor: LtColors.ink,
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: LipButton(
                      label: c.phase == CheckinPhase.listening ? 'Tap when done' : 'Tap to talk',
                      icon: Icons.mic_none_rounded,
                      fontSize: 24,
                      onTap: c.phase == CheckinPhase.listening ? c.stopTalk : c.startTalk,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Semantics(
                    button: true,
                    label: 'Type instead',
                    excludeSemantics: true,
                    onTap: () => c.setTyping(true),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => c.setTyping(true),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: LtColors.paper,
                          shape: BoxShape.circle,
                          border: Border.all(color: LtColors.control, width: LtBorders.control),
                        ),
                        child: const Icon(Icons.keyboard_alt_outlined, size: 28, color: LtColors.ink),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52, minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: LtColors.control, width: LtBorders.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 22, color: LtColors.ink), const SizedBox(width: 4)],
            Text(label, style: LtText.display(19)),
          ],
        ),
      ),
    ),
  );
}

/// Progress dots: done (ink), now (mint pill), later (outline).
class _Dots extends StatelessWidget {
  const _Dots({required this.total, required this.position});
  final int total;
  final int position;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Question $position of $total',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= total; i++)
          Container(
            width: i == position ? 28 : 12,
            height: 12,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: i < position ? LtColors.ink : (i == position ? LtColors.mint : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: LtColors.control, width: 1.5),
            ),
          ),
      ],
    ),
  );
}

/// The answers heard, each with the value the server holds now (the last one said).
class _AnswerList extends StatelessWidget {
  const _AnswerList({required this.items});
  final List<ReadbackItem> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: item.value == null
              ? NoNumberBox(icon: Icons.keyboard_double_arrow_right_rounded, title: '${item.label} · Skipped')
              : Semantics(
                  container: true,
                  label: '${item.label}: ${item.value}',
                  excludeSemantics: true,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBF6EE),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: LtColors.container, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label, style: LtText.body(size: 15, color: LtColors.secondary)),
                        Text(item.value!, style: LtText.display(20)),
                      ],
                    ),
                  ),
                ),
        ),
    ],
  );
}
