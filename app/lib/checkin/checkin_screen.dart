import 'package:flutter/material.dart';

import '../experiment/experiment_page.dart';
import '../onboarding/missing_answers.dart';
import '../experiment/experiment_twins.dart';
import '../experiment/ideas_hub.dart';
import '../experiment/widgets/idea_scene.dart';
import '../experiment/widgets/ideas_turn_cards.dart';
import '../experiment/widgets/widgets.dart';
import '../onboarding/voice_onboarding_controller.dart' show listeningNudge;
import '../twin/twin_model.dart' show TwinAssessment;
import '../twin/twin_repository.dart';
import '../twin/twin_state.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart' hide TwinMood;
import '../voice/voice_indicator.dart';
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
    this.todayPlan,
    this.ideas,
  });

  /// Today's idea for the done screen; null hides it.
  final IdeasAccess? ideas;

  final CheckinController controller;
  final CheckInKind kind;

  /// Encouragement and "Here's today's plan" once the check-in is done. Null: neither.
  final TodayPlanHook? todayPlan;
  final TwinRepository repository;
  final TwinAppearance appearance;
  final VoidCallback onDone;
  final OpenUrl open;

  /// How the server's read-back is listed.
  final ReadbackAdapter readback;

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _questionBubble = GlobalKey();
  final _answerField = GlobalKey();
  (String, String, String?)? _lastPrompt;
  double _lastKeyboardInset = 0;
  TwinAssessment? _before;
  bool _nothing = false;
  bool _starting = true;

  CheckinController get c => widget.controller;
  bool get weekly => widget.kind == CheckInKind.weekly;

  /// Hands-free may open the microphone only while this screen is the top route and the
  /// app is in front.
  ModalRoute<Object?>? _route;
  late final bool Function() _mayListen = _mayListenNow;
  bool _mayListenNow() {
    final s = WidgetsBinding.instance.lifecycleState;
    return mounted && (_route?.isCurrent ?? true) && (s == null || s == AppLifecycleState.resumed);
  }

  @override
  void initState() {
    super.initState();
    _before = widget.repository.current;
    c.mayListen = _mayListen;
    WidgetsBinding.instance.addObserver(this);
    widget.ideas?.hub.ensureToday();
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // VoiceOver reads Mochi's words; the microphone then opens with a tap, never by itself.
    c.screenReader = MediaQuery.accessibleNavigationOf(context);
    _route = ModalRoute.of(context);
  }

  /// Leaving LifeTwin (home screen, another app, a call) closes the microphone and stops
  /// speech; back in front, hands-free listens again if this check-in is still the top screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Every way out passes through hidden (before paused); the way back passes it after paused.
    if (state == AppLifecycleState.hidden && _lifecycle != AppLifecycleState.paused) c.pauseVoice();
    if (state == AppLifecycleState.resumed) c.resumeVoice();
    _lifecycle = state;
  }

  AppLifecycleState? _lifecycle;

  @override
  void dispose() {
    if (identical(c.mayListen, _mayListen)) {
      c.mayListen = () => false;
      c.pauseVoice();
    }
    WidgetsBinding.instance.removeObserver(this);
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('That’s okay. I saved what you told me.'), duration: Duration(seconds: 2)),
      );
    }
    widget.onDone();
  }

  /// The continuous-voice look (status pill, ring, live transcript): hands-free, with a question open.
  bool get _voiceUi => c.handsFree && c.turn != null && !c.emergency && !_nothing && !_finished;

  /// What the pill and ring say now. Only an open microphone is ever [VoiceLook.listening].
  VoiceLook get _look {
    if (c.typing || !c.voiceUsable) return VoiceLook.typing;
    return switch (c.phase) {
      CheckinPhase.listening => VoiceLook.listening,
      CheckinPhase.speaking => VoiceLook.speaking,
      CheckinPhase.interpreting => VoiceLook.thinking,
      CheckinPhase.idle => c.screenReader ? VoiceLook.waiting : VoiceLook.between,
      _ => VoiceLook.typing,
    };
  }

  /// The ring around the twin and the status pill on the bottom edge of the picture.
  Widget _voiceOverlay() => VoiceLive(
    look: _look,
    builder: (context, shown, hidden) => LayoutBuilder(
      builder: (context, box) {
        const d = 190.0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: box.maxWidth * 0.3 - d * 0.57,
              top: box.maxHeight * 0.5 - d * 0.57,
              width: d * 1.14,
              height: d * 1.14,
              child: VoiceRing(look: hidden ? VoiceLook.between : shown, size: d, glow: false),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: -24,
              child: Center(
                child: VoicePill(look: shown, hidden: hidden),
              ),
            ),
          ],
        );
      },
    ),
  );

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
      dock: _keyboardDock(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: widget.appearance,
            twins: [TwinSlot(state: _twin(), x: 0.3)],
            overlay: _voiceUi ? _voiceOverlay() : null,
          ),
          // The pill hangs 24 pt below the picture: room for it.
          SizedBox(height: _voiceUi ? 36 : 14),
          _prompt(context),
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

  Widget _prompt(BuildContext context) {
    final words = c.emergency
        ? EmergencyCard.apology
        : _nothing
        ? 'All set for today!'
        : bubbleFor(
            c.turn?.currentField,
            confirming: c.confirming,
            done: _finished,
            weekly: weekly,
            finalReadback: c.finalReadback,
          );
    final prompt = (words, c.mascotLine, c.turn?.currentField);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final reveal = keyboardInset > 0 && (keyboardInset != _lastKeyboardInset || prompt != _lastPrompt);
    _lastKeyboardInset = keyboardInset;
    _lastPrompt = prompt;
    if (reveal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _questionBubble.currentContext;
        if (mounted && target != null) {
          // Bottom alignment keeps the question above the answer dock. Do this only
          // for a new question/keyboard geometry, never for an ordinary user scroll.
          Scrollable.ensureVisible(target, alignment: 1);
          final field = _answerField.currentContext;
          if (field != null) Scrollable.ensureVisible(field, alignment: 1);
        }
      });
    }
    // Speech takes real space in the scroll view. A positioned bubble in the fixed
    // plate can grow beyond its scroll extent and disappear behind the keyboard dock.
    return Bubble(key: _questionBubble, text: words, tail: BubbleTail.none, fontSize: 19);
  }

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
        if (widget.ideas case final access? when c.turn?.clientAction == 'open_ideas') ...[
          const SizedBox(height: 10),
          IdeasOpenCard(access: access, appearance: widget.appearance),
        ],
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
        if (_voiceUi && c.nudged && c.caption.isEmpty && (c.phase == CheckinPhase.listening || c.nudgeSpeaking)) ...[
          const SizedBox(height: 8),
          const NudgeCaption(line: listeningNudge),
        ],
        if (_voiceUi &&
            c.caption.isNotEmpty &&
            (c.phase == CheckinPhase.listening || c.phase == CheckinPhase.interpreting)) ...[
          const SizedBox(height: 8),
          TranscriptCard(text: c.caption, listening: c.phase == CheckinPhase.listening),
        ] else if (c.phase == CheckinPhase.listening && c.caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          WholeWordText('“${c.caption}”', style: LtText.body(color: LtColors.secondary)),
        ],
        if (_voiceUi && !c.typing && c.voiceUsable) ...[
          const SizedBox(height: 10),
          c.screenReader ? const VoiceOverInfo() : const ListeningNote(),
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

  /// The questions the estimate still needs (missing_answers.dart).
  int get _missing => missingQuestions(widget.repository.missingInputs, widget.repository.profile).length;

  Widget _done(BuildContext context) {
    final change = weekly ? OutlookChange.between(_before, widget.repository.current) : null;
    final confirmed = Map<String, dynamic>.from(c.turn?.state['confirmed'] as Map? ?? const {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(weekly ? 'Outlook updated' : 'All done'),
        const SizedBox(height: 8),
        if (change != null)
          OutlookChangeCard(
            change: change,
            // "Still needed": the one path back to the missing answers.
            answerLabel: _missing == 0 ? null : answerMoreLabel(_missing),
            onTellMochi: _missing == 0 || CheckInScope.maybeOf(context)?.answerMissing == null
                ? null
                : () => CheckInScope.maybeOf(context)!.answerMissing!(context),
          )
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
        if (widget.todayPlan case final hook?) ...[
          const SizedBox(height: 12),
          _Encouragement(hook: hook, onDone: widget.onDone),
        ],
        if (widget.ideas case final access?) _ideaCard(access),
        if (c.progress != null && c.progress!.goodWeeks > 0) ...[
          const SizedBox(height: 10),
          WholeWordText(
            c.progress!.goodWeeks == 1 ? '1 good week so far' : '${c.progress!.goodWeeks} good weeks so far',
            style: LtText.body(weight: FontWeight.w700),
          ),
        ],
        if (c.offerReminder) ...[
          const SizedBox(height: 12),
          ReminderOfferCard(onNotNow: c.declineReminders, onYes: c.acceptReminders),
        ],
      ],
    );
  }

  /// "Mochi has an idea for today" on the finished daily check-in: not weekly, never in an emergency,
  /// and never after Mochi's care line (that moment is not for suggestions).
  Widget _ideaCard(IdeasAccess access) => ListenableBuilder(
    listenable: access.hub,
    builder: (context, _) {
      final idea = access.hub.featured;
      if (idea == null || weekly || c.emergency || c.turn?.state['care_line_shown'] == true) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 22, color: LtColors.ink),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Mochi has an idea for today', style: LtText.body(weight: FontWeight.w700))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            IdeaRow(idea: idea, appearance: widget.appearance, onTap: () => access.openIdea(context, idea)),
          ],
        ),
      );
    },
  );

  Widget _keyboardDock(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard == 0) return _dock(context);
    final available = MediaQuery.sizeOf(context).height - keyboard - MediaQuery.paddingOf(context).vertical;
    // Keep real space for the question when the keyboard reduces the page. The
    // answer chips and input can scroll within their own region without hiding it.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: available * 0.45),
      child: SingleChildScrollView(child: _dock(context)),
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
                      key: _answerField,
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
            else if (c.handsFree)
              // Hands-free needs no button: the pill shows what is happening. With VoiceOver there is
              // one tap target. "Type instead" stays in reach in every voice state.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.screenReader)
                    LipButton(
                      key: const ValueKey('tap-to-talk'),
                      label: 'Tap to talk to Mochi',
                      icon: Icons.mic_none_rounded,
                      height: 72,
                      hint: 'Double tap, then speak',
                      onTap: c.phase == CheckinPhase.idle ? () => c.startTalk() : null,
                    ),
                  Center(
                    child: LinkButton(
                      label: 'Type instead',
                      icon: Icons.keyboard_outlined,
                      onTap: () => c.setTyping(true),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    // Hands-free it only shows what is happening (a tap still sends at once, or
                    // cuts Mochi short); "Tap to talk" is left for VoiceOver and after a problem.
                    child: LipButton(
                      label: switch (c.phase) {
                        CheckinPhase.listening => c.continuous ? 'Listening…' : 'Tap when done',
                        CheckinPhase.speaking when c.continuous => 'Mochi is talking…',
                        CheckinPhase.interpreting when c.continuous => 'One moment…',
                        _ => 'Tap to talk',
                      },
                      icon: c.phase == CheckinPhase.listening && c.continuous
                          ? Icons.graphic_eq_rounded
                          : Icons.mic_none_rounded,
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
            if (c.handsFree && c.typing && c.voiceUsable)
              Center(
                child: LinkButton(label: 'Talk instead', icon: Icons.mic_none_rounded, onTap: () => c.setTyping(false)),
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
            Flexible(child: Text(label, style: LtText.display(19))),
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

/// "Would you like a gentle reminder each day?" with Not now / Yes. Shown after the first
/// check-in and at the end of onboarding.
class ReminderOfferCard extends StatelessWidget {
  const ReminderOfferCard({super.key, required this.onNotNow, required this.onYes});
  final VoidCallback onNotNow;
  final VoidCallback onYes;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: LtColors.paper,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: LtColors.container, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WholeWordText('Would you like a gentle reminder each day?', style: LtText.body(weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: LipButton(label: 'Not now', kind: LipKind.secondary, height: 56, fontSize: 19, onTap: onNotNow),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LipButton(label: 'Yes', height: 56, fontSize: 19, onTap: onYes),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Mochi's encouragement after a check-in, and "Here's today's plan" (back to Home, then the plan).
class _Encouragement extends StatefulWidget {
  const _Encouragement({required this.hook, required this.onDone});
  final TodayPlanHook hook;
  final VoidCallback onDone;

  static const fallback = 'Nice work today. A small step counts.';

  @override
  State<_Encouragement> createState() => _EncouragementState();
}

class _EncouragementState extends State<_Encouragement> {
  // Asked once, not on every rebuild.
  late final Future<TodayUpdate> _update = widget.hook.update().catchError((Object _) => const TodayUpdate());

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FutureBuilder<TodayUpdate>(
        future: _update,
        builder: (_, snap) {
          final u = snap.data;
          final changes = u?.changes;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: WholeWordText(
                  u?.encouragement ?? _Encouragement.fallback,
                  style: LtText.body(weight: FontWeight.w700),
                ),
              ),
              if (changes != null) ...[
                const SizedBox(height: 10),
                if (changes.isEmpty)
                  WholeWordText('Your plan stays the same today.', style: LtText.body())
                else ...[
                  Semantics(
                    header: true,
                    child: Text('Mochi updated your plan', style: LtText.body(weight: FontWeight.w700)),
                  ),
                  for (final line in changes) WholeWordText(line, style: LtText.body()),
                ],
              ],
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      LipButton(
        label: 'Here’s today’s plan',
        kind: LipKind.secondary,
        height: 56,
        fontSize: 20,
        onTap: () {
          final nav = Navigator.of(context);
          widget.onDone();
          widget.hook.open(nav.context);
        },
      ),
    ],
  );
}
