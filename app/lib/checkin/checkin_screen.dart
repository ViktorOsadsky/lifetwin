import 'package:flutter/material.dart';

import '../experiment/experiment_page.dart';
import '../experiment/experiment_twins.dart';
import '../experiment/widgets/widgets.dart';
import '../twin/twin_state.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart' hide TwinMood;
import '../widgets/whole_word_text.dart';
import 'checkin_client.dart';
import 'checkin_controller.dart';
import 'emergency_card.dart';
import 'updated_card.dart';

/// Quick replies for the question being asked: the person's own tapped answer, sent as text.
/// Nothing is pre-selected and "Skip" is always there. Fields with no sensible chips (drinks,
/// smoking, blood pressure) are answered by typing or talking.
List<String> quickReplies(String? field) => switch (field) {
  'wellbeing' => const ['Good', 'Okay', 'Not great'],
  'sleep_hours_last_night' || 'sleep_hours' => const ['5 hours', '6 hours', '7 hours', '8 hours'],
  'exercise_minutes_today' => const ['0 minutes', '15 minutes', '30 minutes', '60 minutes'],
  'exercise_minutes_weekly' => const ['0 minutes', '60 minutes', '150 minutes', '300 minutes'],
  _ => const [],
};

/// Mochi's short line in the bubble for the field being asked (the full reply sits in the card).
String bubbleFor(
  String? field, {
  required bool confirming,
  required bool done,
  required bool readback,
  required CheckInKind kind,
}) {
  if (done) return kind == CheckInKind.daily ? 'Thanks for checking in!' : 'Your week is in.';
  if (readback) return kind == CheckInKind.daily ? 'Here’s your day. Right?' : 'Here’s your week. Right?';
  if (confirming) return 'Did I get that right?';
  return switch (field) {
    'wellbeing' => 'How are you feeling?',
    'sleep_hours_last_night' || 'sleep_hours' => 'How did you sleep?',
    'exercise_minutes_today' => 'Did you move today?',
    'exercise_minutes_weekly' => 'How active was your week?',
    'alcohol_drinks_yesterday' || 'alcohol_drinks_weekly' => 'Any drinks?',
    'smoking_status' => 'Do you smoke?',
    'weight_kg' => 'Your weight?',
    'systolic_bp' || 'diastolic_bp' => 'Blood pressure?',
    _ => 'Got a minute?',
  };
}

/// The check-in chat (Z-15 daily, Z-16 weekly): Mochi asks one question at a time, with quick
/// replies, a keyboard or voice; reads each answer back before it counts; and pauses calmly on an
/// emergency. About 3 questions for daily, so it takes about a minute. When a weekly check-in
/// finishes, the outlook change shows (Z-17).
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({
    super.key,
    required this.controller,
    required this.appearance,
    required this.onDone,
    this.open = defaultOpenUrl,
    this.onTalk,
  });

  final CheckinController controller;
  final TwinAppearance appearance;
  final VoidCallback onDone;
  final OpenUrl open;

  /// "Tap to talk": starts voice input. Null until voice is wired to this screen; the keyboard is shown instead.
  final VoidCallback? onTalk;

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _text = TextEditingController();
  bool _typing = false;

  CheckinController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (!c.started) c.start();
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
    c.reply(t);
  }

  TwinState _twin() {
    if (c.emergency) {
      return const TwinState(mood: TwinMood.concerned, pose: TwinPose.stand, reason: TwinStateReason.emergency);
    }
    if (c.done) return c.repository.twinState();
    return curiousTwin;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final r = c.response;
      final confirming = r?.phase == 'confirming';
      return ExperimentPage(
        mode: LtMode.room,
        onBack: c.emergency ? c.resume : widget.onDone,
        backLabel: c.emergency ? 'Continue' : 'Back',
        dock: _dock(context, confirming),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExperimentPlate(
              appearance: widget.appearance,
              twins: [TwinSlot(state: _twin(), x: 0.3)],
              bubble: c.emergency
                  ? EmergencyCard.apology
                  : bubbleFor(
                      r?.currentField,
                      confirming: confirming,
                      done: c.done,
                      readback: c.readback != null,
                      kind: c.kind,
                    ),
            ),
            const SizedBox(height: 14),
            Sheet(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: c.emergency
                  ? EmergencyCard(onContinue: c.resume, picksUpAt: c.pausedAt, open: widget.open)
                  : _card(context),
            ),
          ],
        ),
      );
    },
  );

  Widget _card(BuildContext context) {
    final r = c.response;
    final weekly = c.kind == CheckInKind.weekly;
    if (r == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(weekly ? 'Weekly check-in' : 'Daily check-in', style: LtText.display(28)),
          WholeWordText(c.error ?? 'One moment…', style: LtText.body(color: LtColors.secondary)),
          if (c.error != null) ...[
            const SizedBox(height: 10),
            LipButton(label: 'Try again', fontSize: 22, onTap: c.start),
          ],
        ],
      );
    }
    if (c.done) return _done(context, r);
    if (c.readback != null) return _readback(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(weekly ? 'Weekly check-in' : 'Daily check-in', style: LtText.display(28)),
              ),
            ),
            _Dots(total: c.total, position: c.position),
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
                  TextSpan(text: r.message, style: LtText.body()),
                ],
              ),
            ),
          ),
        ),
        if (c.error != null) ...[
          const SizedBox(height: 8),
          WholeWordText('That did not go through. Try again.', style: LtText.body(color: LtColors.secondary)),
        ],
      ],
    );
  }

  /// The ONE read-back of the whole check-in, with every answer in a list (skipped ones dashed).
  Widget _readback(BuildContext context) {
    final weekly = c.kind == CheckInKind.weekly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(weekly ? 'Weekly check-in' : 'Daily check-in', style: LtText.display(28))),
        WholeWordText('Here’s what I heard.', style: LtText.body(color: LtColors.secondary)),
        const SizedBox(height: 8),
        for (final item in c.readback!)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: item.value == null
                ? NoNumberBox(icon: Icons.keyboard_double_arrow_right_rounded, title: '${item.label} · Skipped')
                : Container(
                    constraints: const BoxConstraints(minHeight: 56),
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBF6EE),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: LtColors.container, width: 1.5),
                    ),
                    child: Semantics(
                      container: true,
                      label: '${item.label}: ${item.value}',
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.label, style: LtText.body(color: LtColors.secondary)),
                          Text(item.value!, style: LtText.display(20)),
                        ],
                      ),
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _done(BuildContext context, CheckInResponse r) {
    final change = c.change;
    final weekly = c.kind == CheckInKind.weekly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(weekly ? 'Outlook updated' : 'All done', style: LtText.display(28))),
        const SizedBox(height: 8),
        if (weekly && change != null)
          OutlookChangeCard(change: change)
        else
          WholeWordText(
            c.repository.twinState().mood == TwinMood.cheerful ? 'See you tomorrow!' : 'Thanks for telling me.',
            style: LtText.body(),
          ),
        if (weekly && r.confirmed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text('Your confirmed week', style: LtText.body(weight: FontWeight.w700)),
          ),
          ConfirmedWeek(confirmed: r.confirmed),
        ],
      ],
    );
  }

  Widget _dock(BuildContext context, bool confirming) {
    final pad = EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom);
    if (c.emergency) return const SizedBox.shrink();
    if (c.done) {
      return Padding(
        padding: pad,
        child: LipButton(label: 'Back to my room', fontSize: 24, onTap: widget.onDone),
      );
    }
    final r = c.response;
    if (r == null) return const SizedBox.shrink();
    if (c.readback != null) {
      return Padding(
        padding: pad,
        child: Row(
          children: [
            Expanded(
              child: LipButton(
                label: 'Change with Mochi',
                icon: Icons.chat_bubble_outline_rounded,
                kind: LipKind.secondary,
                fontSize: 18,
                onTap: c.busy ? null : c.redo,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LipButton(
                label: 'Looks right',
                icon: Icons.check_rounded,
                fontSize: 20,
                onTap: c.busy ? null : c.accept,
              ),
            ),
          ],
        ),
      );
    }
    final chips = confirming ? const <String>[] : quickReplies(r.currentField);
    return Padding(
      padding: pad,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (confirming)
            Row(
              children: [
                Expanded(
                  child: LipButton(
                    label: 'Not quite',
                    kind: LipKind.secondary,
                    fontSize: 20,
                    onTap: c.busy ? null : () => c.reply('no'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LipButton(
                    label: 'Yes',
                    icon: Icons.check_rounded,
                    fontSize: 20,
                    onTap: c.busy ? null : c.confirm,
                  ),
                ),
              ],
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in chips) _Chip(label: q, onTap: c.busy ? null : () => c.reply(q)),
                _Chip(label: 'Skip', icon: Icons.keyboard_double_arrow_right_rounded, onTap: c.busy ? null : c.skip),
              ],
            ),
            const SizedBox(height: 10),
            if (_typing)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'Type your answer'),
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
                      label: 'Tap to talk',
                      icon: Icons.mic_none_rounded,
                      fontSize: 24,
                      onTap: widget.onTalk ?? () => setState(() => _typing = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Semantics(
                    button: true,
                    label: 'Type instead',
                    excludeSemantics: true,
                    onTap: () => setState(() => _typing = true),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _typing = true),
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
