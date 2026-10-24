import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/lifetwin_theme.dart';
import '../widgets/lip_button.dart';
import '../widgets/lt_buttons.dart';
import '../widgets/lt_icons.dart';
import '../widgets/lt_progress.dart';
import '../widgets/lt_text_link.dart';
import '../widgets/pip.dart';
import '../widgets/scene_paper.dart';
import '../widgets/speech_bubble.dart';
import 'voice_onboarding_controller.dart';

/// Fields whose answer is a number: the keyboard opens on the number pad.
const numberFields = {'age', 'weight_kg', 'sleep_hours', 'exercise_minutes_weekly', 'alcohol_drinks_weekly'};

/// Opens this app's page in the iPhone Settings app (to turn the microphone on).
Future<void> openAppSettings() async {
  try {
    await launchUrl(Uri.parse('app-settings:'));
  } catch (_) {}
}

/// Text is enlarged enough that the layout changes (Pip moves to the corner,
/// buttons stack): QuestionLargeText.dc.html.
bool largeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(1) > 1.3;

/// The screen's side gutter. Scenes are drawn edge to edge, so padding is per row.
Widget _pad(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: LtSpace.gutter),
  child: child,
);

/// Pip standing on the paper strip under a speech bubble (Question.dc.html).
/// [beside] (Hear it again, Speaking… Stop) sits on the strip to Pip's right.
class PipScene extends StatelessWidget {
  const PipScene({super.key, this.mood = PipMood.asking, this.beside});
  final PipMood mood;
  final Widget? beside;

  @override
  Widget build(BuildContext context) {
    final pip = Positioned(left: 62, bottom: 6, child: Pip(mood: mood, height: 104));
    if (beside == null) return ScenePaper(height: 132, child: pip);
    return SizedBox(
      height: 132,
      child: Stack(
        children: [
          const Positioned.fill(child: ScenePaper(height: 132)),
          pip,
          // Low on the strip, clear of the lavender squiggle.
          Positioned(
            left: 172,
            right: 8,
            bottom: 8,
            child: Align(alignment: AlignmentDirectional.centerStart, child: beside),
          ),
        ],
      ),
    );
  }
}

/// Mascot conversation by voice or typing. One action per screen, large type,
/// captions always on, nothing disappears by itself.
class VoiceOnboardingScreen extends StatefulWidget {
  const VoiceOnboardingScreen({
    super.key,
    required this.controller,
    required this.onDone,
    this.onUseHealth,
    this.onOpenSettings = openAppSettings,
  });

  final VoiceOnboardingController controller;

  /// Called with the confirmed profile when the conversation is finished.
  final void Function(Map<String, dynamic> confirmedProfile) onDone;

  /// Opens the Apple Health import. The button is hidden when null.
  final VoidCallback? onUseHealth;

  /// Opens the phone's Settings app after the microphone was not allowed.
  final Future<void> Function() onOpenSettings;

  @override
  State<VoiceOnboardingScreen> createState() => _VoiceOnboardingScreenState();
}

class _VoiceOnboardingScreenState extends State<VoiceOnboardingScreen> {
  final _text = TextEditingController();

  /// Owned here, not by the TextField, so the typing box keeps focus (and the
  /// keyboard stays up) whatever else on the screen changes.
  final _focus = FocusNode(debugLabel: 'answer');

  /// The voice answer from the first consent question, kept until the second is answered.
  bool? _voiceChoice;

  bool _wasListening = false;

  VoiceOnboardingController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void didUpdateWidget(VoiceOnboardingScreen old) {
    super.didUpdateWidget(old);
    if (old.controller != c) {
      old.controller.removeListener(_changed);
      c.addListener(_changed);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    c.screenReader = MediaQuery.accessibleNavigationOf(context);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A short buzz when the microphone opens or closes, however it happened.
  void _changed() {
    final listening = c.phase == VoicePhase.listening;
    if (listening != _wasListening) HapticFeedback.mediumImpact();
    _wasListening = listening;
  }

  void _send() {
    final t = _text.text;
    if (t.trim().isEmpty || c.phase == VoicePhase.interpreting) return;
    _text.clear();
    c.submitTyped(t);
  }

  /// Pip listens while the microphone is open, is pleased after an answer was
  /// taken ("Got it.") or while reading it back, and asks otherwise.
  PipMood get _mood {
    if (c.phase == VoicePhase.listening) return PipMood.listening;
    if (c.phase == VoicePhase.done || (c.confirming && !c.correcting) || c.mascotLine.startsWith('Got it')) {
      return PipMood.pleased;
    }
    return PipMood.asking;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LtColors.paper,
      body: SafeArea(
        // Tapping anywhere that is not a control puts the keyboard away.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => !c.askingVoice && !(c.phase == VoicePhase.consent && c.turn == null && !c.canRetry)
                ? _talk(context)
                : c.askingVoice
                ? _voiceAgain(context)
                : _consent(context),
          ),
        ),
      ),
    );
  }

  static const _voiceCopy =
      'You can talk to me, or type. While you talk, your voice is sent to Cartesia, '
      'a speech service, to turn it into words.';

  /// A consent question: title, Pip's words in a bubble, Pip on the paper, two big buttons.
  Widget _question(BuildContext context, {required String title, required String body, required List<Widget> buttons}) {
    // The words scroll; the two buttons stay at the bottom, always in reach.
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StoryScroll(
              top: [
                _pad(Semantics(header: true, child: Text(title, style: LtText.title))),
                const SizedBox(height: LtSpace.xl),
                _pad(SpeechBubble(child: Text(body, style: LtText.body))),
              ],
              bottom: const PipScene(),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.6),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(LtSpace.gutter, LtSpace.sm, LtSpace.gutter, LtSpace.gutter),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: buttons),
            ),
          ),
        ],
      ),
    );
  }

  Widget _consent(BuildContext context) {
    final voice = _voiceChoice;
    if (voice != null) return _aiConsent(context, voice);
    return _question(
      context,
      title: 'Talk with me?',
      body: _voiceCopy,
      buttons: [
        LtPrimaryButton(
          label: "Yes, I'll talk",
          icon: const LtIcon(LtIconKind.mic, size: 36),
          onPressed: () => setState(() => _voiceChoice = true),
        ),
        const SizedBox(height: LtSpace.buttonGap),
        LtSecondaryButton(
          label: "No, I'll type",
          icon: const LtIcon(LtIconKind.keyboard),
          onPressed: () => setState(() => _voiceChoice = false),
        ),
      ],
    );
  }

  /// Same question as the first screen, asked when someone who started by
  /// typing wants to talk.
  Widget _voiceAgain(BuildContext context) => _question(
    context,
    title: 'Talk with me?',
    body: _voiceCopy,
    buttons: [
      LtPrimaryButton(
        label: "Yes, I'll talk",
        icon: const LtIcon(LtIconKind.mic, size: 36),
        onPressed: () => c.answerVoiceAgain(true),
      ),
      const SizedBox(height: LtSpace.buttonGap),
      LtSecondaryButton(
        label: 'Keep typing',
        icon: const LtIcon(LtIconKind.keyboard),
        onPressed: () => c.answerVoiceAgain(false),
      ),
    ],
  );

  /// Second question: may an AI helper read the answers? "Not now" works
  /// fully, and it can be turned on later in Settings.
  Widget _aiConsent(BuildContext context, bool voice) => _question(
    context,
    title: 'Let an AI helper read hard answers?',
    body:
        "If I can't understand an answer, an AI service can read your words. "
        "It's off unless you say yes. You can change this in Settings.",
    buttons: [
      LtPrimaryButton(
        label: 'Yes, turn it on',
        icon: const LtIcon(LtIconKind.check, size: 38, strokeWidth: 2.8),
        onPressed: () => c.answerConsent(voice, aiHelper: true),
      ),
      const SizedBox(height: LtSpace.buttonGap),
      LtSecondaryButton(label: 'Not now', onPressed: () => c.answerConsent(voice)),
    ],
  );

  /// The conversation: everything about the question scrolls; the controls stay
  /// at the bottom. "Hide keyboard" sits outside the controls' scroll area so
  /// it can never be clipped.
  Widget _talk(BuildContext context) {
    // Read above the Scaffold: inside its body the keyboard inset is already removed.
    final keyboard = MediaQuery.viewInsetsOf(this.context).bottom > 0;
    final hideKeyboard = keyboard && _showsTypingBox;
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _story(context, keyboard)),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * (hideKeyboard ? 0.5 : 0.6)),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(LtSpace.gutter, LtSpace.sm, LtSpace.gutter, hideKeyboard ? 8 : 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _controls(context, keyboard)),
            ),
          ),
          if (hideKeyboard)
            Padding(
              padding: const EdgeInsets.fromLTRB(LtSpace.gutter, 0, LtSpace.gutter, 12),
              child: LtSecondaryButton(
                label: 'Hide keyboard',
                icon: const LtIcon(LtIconKind.keyboard, size: 30),
                minHeight: LtSize.minButton,
                onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ),
        ],
      ),
    );
  }

  /// Typing: quick answers stay under the question. By voice they join the controls.
  bool get _quickInStory => c.typing && !c.confirming && c.phase != VoicePhase.done && c.quickAnswers.isNotEmpty;

  bool get _showsTypingBox => c.typing && c.phase != VoicePhase.done && (!c.confirming || c.correcting);

  /// Progress, Pip and its words, what was heard, and any notice. Scrolls; Pip's
  /// paper scene sits at the bottom, just above the controls (Question.dc.html).
  Widget _story(BuildContext context, bool keyboard) {
    final busy = c.phase == VoicePhase.interpreting;
    final line = c.mascotLine.isEmpty ? (busy ? 'One moment…' : '') : c.mascotLine;
    final big = largeText(context);
    final listening = c.phase == VoicePhase.listening;
    final mood = _mood;
    final n = c.questionNumber;
    // By voice the quick answers sit with the controls (QuickAnswer.dc.html).
    final quick = _quickInStory;
    // The read-back has three choices below it, so its "You said:" line needs the room.
    final readBack = c.confirming && !c.correcting && c.caption.isNotEmpty;
    final more = readBack || c.notice != null || quick;
    // While listening Pip sits beside the question (Listening.dc.html). Otherwise it
    // stands under the bubble (Question.dc.html), unless the text is large or more is
    // on screen (a read-back with its caption, a notice): then it sits small in the corner
    // (QuestionLargeText.dc.html) so the words and buttons keep the room. With the
    // keyboard up the room goes to the question and the typing box.
    final beside = listening && !big && !keyboard;
    final corner = !keyboard && (big || (more && !beside));
    final scene = line.isNotEmpty && !corner && !keyboard && !beside;
    final links = c.phase != VoicePhase.done && !keyboard;
    final voiceLine = c.phase == VoicePhase.speaking
        ? _speaking()
        : c.canHearAgain && !listening
        ? LtTextLink(label: 'Hear it again', icon: const LtIcon(LtIconKind.speaker, size: 28), onPressed: c.hearAgain)
        : null;
    // Settings (and the small Pip) share the "Question N of 11" row.
    final trailing = corner || links
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (corner) Pip(mood: mood, height: big ? 70 : 48),
              if (links)
                Flexible(
                  child: LtTextLink(label: 'Settings', onPressed: _openSettings),
                ),
            ],
          )
        : null;
    return _StoryScroll(
      top: [
        // "Go back" at the top left, where the artboards keep "Back".
        // Also once done, so an answer can still be changed (or a skipped one added).
        if (!keyboard && c.canGoBack)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: LtTextLink(
                label: 'Go back',
                icon: const LtIcon(LtIconKind.back, size: 26, strokeWidth: 2.8),
                onPressed: c.goBack,
              ),
            ),
          ),
        // With the keyboard up only the question shows above the typing box.
        if (n != null && !keyboard) ...[
          _pad(LtStepProgress(step: n, total: VoiceOnboardingController.questionCount, trailing: trailing)),
          const SizedBox(height: LtSpace.lg),
        ] else if (trailing != null) ...[
          _pad(Align(alignment: AlignmentDirectional.centerEnd, child: trailing)),
          const SizedBox(height: LtSpace.sm),
        ],
        // Mascot line: always visible as a caption, announced when it changes.
        _pad(
          Semantics(
            liveRegion: true,
            container: true,
            child: line.isEmpty
                ? const SizedBox.shrink()
                : beside
                ? Row(
                    children: [
                      Pip(mood: mood, height: 100),
                      const SizedBox(width: 4),
                      Expanded(
                        child: SpeechBubble(
                          tail: BubbleTail.left,
                          tailOffset: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          radius: const BorderRadius.all(Radius.circular(24)),
                          child: _line(line, short: LtText.bubble),
                        ),
                      ),
                    ],
                  )
                : SpeechBubble(
                    tail: scene ? BubbleTail.down : BubbleTail.none,
                    child: _line(line, short: keyboard ? LtText.bubble : null),
                  ),
          ),
        ),
        if (!scene) ...[
          const SizedBox(height: LtSpace.md),
          if (voiceLine != null) _pad(Align(alignment: AlignmentDirectional.centerStart, child: voiceLine)),
        ],
        if (c.caption.isNotEmpty && !keyboard) ...[
          const SizedBox(height: LtSpace.sm),
          _pad(listening ? _hearing() : _youSaid()),
        ],
        if (c.notice != null) ...[
          const SizedBox(height: LtSpace.lg),
          _pad(
            _NoticeBox(
              message: c.notice!,
              onRetry: c.canRetry ? c.retry : null,
              onOpenSettings: c.notice == micDeniedNotice ? widget.onOpenSettings : null,
            ),
          ),
        ],
        if (quick) ...[const SizedBox(height: LtSpace.lg), _pad(_quickAnswers(busy))],
      ],
      bottom: scene ? PipScene(mood: mood, beside: voiceLine) : null,
    );
  }

  /// The mascot's words. Lines over 80 characters use the smaller body style. A
  /// read-back ends with "Is that right?" set apart in bold, as on Readback.dc.html.
  Widget _line(String line, {TextStyle? short}) {
    const ask = 'Is that right?';
    if (c.confirming && !c.correcting && line.endsWith(ask) && line.length > ask.length) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: line.substring(0, line.length - ask.length).trimRight(), style: LtText.body),
            const TextSpan(text: '\n'),
            TextSpan(text: ask, style: short ?? LtText.question),
          ],
        ),
      );
    }
    return Text(line, style: line.length > 80 ? LtText.body : (short ?? LtText.question));
  }

  Widget _speaking() => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: LtSpace.md,
    children: [
      Text('Speaking…', style: LtText.label),
      LtTextLink(label: 'Stop', icon: const LtIcon(LtIconKind.stop, size: 26), onPressed: c.stopSpeaking),
    ],
  );

  /// The live caption, large, in its own card (Listening.dc.html).
  Widget _hearing() => Semantics(
    liveRegion: true,
    container: true,
    child: Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      decoration: const BoxDecoration(
        color: LtColors.white,
        borderRadius: LtRadii.card,
        border: Border.fromBorderSide(LtOutline.side),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text('Hearing:', style: LtText.label)),
              const SizedBox(width: LtSpace.md),
              const ExcludeSemantics(child: _SoundBars()),
            ],
          ),
          const SizedBox(height: LtSpace.sm),
          Text(c.caption, style: LtText.question.copyWith(fontSize: 32)),
        ],
      ),
    ),
  );

  Widget _youSaid() => Semantics(liveRegion: true, child: Text('You said: ${c.caption}', style: LtText.body));

  List<Widget> _controls(BuildContext context, bool keyboard) {
    final busy = c.phase == VoicePhase.interpreting;
    if (c.phase == VoicePhase.done) {
      return [
        LtPrimaryButton(label: 'Continue', onPressed: () => widget.onDone(c.confirmedProfile)),
        if (widget.onUseHealth != null) ...[
          const SizedBox(height: LtSpace.buttonGap),
          LtSecondaryButton(label: 'Use my Health app', onPressed: widget.onUseHealth!),
        ],
      ];
    }
    if (c.confirming && c.correcting) {
      return [
        Text('Okay. What is the right answer?', style: LtText.bodyStrong),
        const SizedBox(height: LtSpace.lg),
        ..._answerControls(busy, keyboard),
        if (!busy && !keyboard) ...[
          const SizedBox(height: LtSpace.buttonGap),
          LtSecondaryButton(label: 'Never mind', onPressed: c.keepAnswer),
        ],
        if (!keyboard) ..._more(),
      ];
    }
    if (c.confirming) {
      return [
        LtPrimaryButton(
          label: 'Yes',
          icon: const LtIcon(LtIconKind.check, size: 38, strokeWidth: 2.8),
          onPressed: busy ? null : c.confirm,
        ),
        const SizedBox(height: LtSpace.buttonGap),
        LtSecondaryButton(
          label: 'No, change it',
          icon: const LtIcon(LtIconKind.pencil, size: 32, strokeWidth: 2.2),
          onPressed: busy ? null : c.change,
        ),
        // By voice, the person can also just say yes, no, or the right answer.
        if (!c.typing) ...[const SizedBox(height: LtSpace.sm), TalkButton(controller: c, compact: true)],
        // Readback.dc.html has only Yes, "No, change it" and Talk; switching is a link here.
        Center(
          child: LtTextLink(
            label: c.typing ? 'Talk instead' : 'Type instead',
            icon: LtIcon(c.typing ? LtIconKind.mic : LtIconKind.keyboard, size: 28),
            onPressed: () => c.setTyping(!c.typing),
          ),
        ),
      ];
    }
    final quick = !c.typing && c.quickAnswers.isNotEmpty;
    return [
      // The offer after an answer the server could not read, first so it is seen.
      if (c.helperWouldHelp && !busy) ...[
        LtSecondaryButton(label: 'Yes, let the AI helper read it', onPressed: () => c.setAiHelper(true)),
        const SizedBox(height: LtSpace.buttonGap),
      ],
      if (quick) ...[_quickAnswers(busy), const SizedBox(height: LtSpace.sm)],
      // With quick answers on screen they are the big choices; Talk is the smaller one.
      if (quick) TalkButton(controller: c, compact: true) else ..._answerControls(busy, keyboard),
      if (!keyboard) ...[const SizedBox(height: LtSpace.buttonGap), _switchMode()],
      const SizedBox(height: LtSpace.xs),
      Center(
        child: LtTextLink(label: 'Skip this question', onPressed: busy ? null : c.skip),
      ),
      if (!keyboard) ..._minor(),
    ];
  }

  /// The typing box and Send, or the Talk button.
  List<Widget> _answerControls(bool busy, bool keyboard) {
    if (!c.typing) return [TalkButton(controller: c)];
    final field = c.state?['current_field'];
    const border = OutlineInputBorder(borderRadius: LtRadii.tile, borderSide: LtOutline.side);
    return [
      TextField(
        // Keyed and given a lasting focus node: the rest of this column
        // changes when the keyboard opens, and without these the field was
        // rebuilt from scratch, dropping focus and the keyboard mid-tap.
        key: const ValueKey('answer-field'),
        controller: _text,
        focusNode: _focus,
        // Read-only (not disabled) while waiting, so focus is never taken away.
        readOnly: busy,
        keyboardType: numberFields.contains(field) ? const TextInputType.numberWithOptions(decimal: true) : null,
        style: LtText.bubble,
        cursorColor: LtColors.ink,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _send(),
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'Type your answer',
          labelStyle: LtText.body.copyWith(color: LtColors.ink),
          floatingLabelStyle: LtText.label,
          filled: true,
          fillColor: LtColors.white,
          contentPadding: const EdgeInsets.all(18),
          border: border,
          enabledBorder: border,
          focusedBorder: const OutlineInputBorder(
            borderRadius: LtRadii.tile,
            borderSide: BorderSide(color: LtColors.ink, width: LtOutline.selected),
          ),
        ),
      ),
      const SizedBox(height: LtSpace.buttonGap),
      LtPrimaryButton(
        key: const ValueKey('send'),
        label: busy ? 'One moment…' : 'Send',
        // Shorter with the keyboard up, so Send stays above it; never under 72 pt.
        minHeight: keyboard ? LtSize.minButton : null,
        onPressed: busy ? null : _send,
      ),
    ];
  }

  Widget _switchMode() => LtSecondaryButton(
    label: c.typing ? 'Talk instead' : 'Type instead',
    icon: LtIcon(c.typing ? LtIconKind.mic : LtIconKind.keyboard),
    onPressed: () => c.setTyping(!c.typing),
  );

  /// Talk/Type instead. (Go back and Settings are links at the top.)
  List<Widget> _more() => [const SizedBox(height: LtSpace.buttonGap), _switchMode()];

  /// On the first question only: the Health app instead of answering.
  List<Widget> _minor() => [
    if (widget.onUseHealth != null && c.questionNumber == 1 && !c.confirming && c.phase != VoicePhase.listening)
      Center(
        child: LtTextLink(label: 'Use my Health app instead', onPressed: widget.onUseHealth),
      ),
  ];

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: LtColors.paper,
      builder: (sheet) => SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (sheet, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(LtSpace.gutter, 0, LtSpace.gutter, LtSpace.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(header: true, child: Text('Settings', style: LtText.title)),
                  const SizedBox(height: LtSpace.lg),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('AI helper', style: LtText.bodyStrong),
                    subtitle: Text('Reads answers I can’t understand', style: LtText.bodySmall),
                    value: c.aiHelper,
                    onChanged: (on) => c.setAiHelper(on),
                  ),
                  const SizedBox(height: LtSpace.lg),
                  Text('Answer by', style: LtText.bodyStrong),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(Size(0, LtSize.smallTap)),
                      textStyle: WidgetStatePropertyAll(LtText.label),
                      side: const WidgetStatePropertyAll(LtOutline.side),
                    ),
                    segments: const [
                      ButtonSegment(value: false, label: Text('Talk'), icon: Icon(Icons.mic)),
                      ButtonSegment(value: true, label: Text('Type'), icon: Icon(Icons.keyboard)),
                    ],
                    selected: {c.typing},
                    onSelectionChanged: (s) {
                      // Talking may first need the "Talk with me?" question, shown on the main screen.
                      if (!s.first) Navigator.of(sheet).pop();
                      c.setTyping(s.first);
                    },
                  ),
                  const SizedBox(height: LtSpace.xxl),
                  LtPrimaryButton(label: 'Done', onPressed: () => Navigator.of(sheet).pop()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Two per row when they fit, one per row when the text is large.
  Widget _quickAnswers(bool busy) {
    final answers = c.quickAnswers;
    final width = MediaQuery.sizeOf(context).width - 2 * LtSpace.gutter;
    const gap = LtSpace.md;
    final perRow = largeText(context) ? 1 : 2;
    final w = (width - gap * (perRow - 1)) / perRow;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final (label, say) in answers)
          SizedBox(
            width: w,
            child: LtSecondaryButton(label: label, onPressed: busy ? null : () => c.submitQuick(say)),
          ),
      ],
    );
  }
}

/// A scrolling column: [top] from the top, [bottom] (Pip's scene) pushed down to
/// the bottom edge when there is room, and simply after [top] when there is not.
class _StoryScroll extends StatelessWidget {
  const _StoryScroll({required this.top, this.bottom});
  final List<Widget> top;
  final Widget? bottom;

  static const _padTop = LtSpace.sm, _padBottom = LtSpace.sm;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      padding: const EdgeInsets.only(top: _padTop, bottom: _padBottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: (box.maxHeight - _padTop - _padBottom).clamp(0, double.infinity)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: top),
            ?bottom,
          ],
        ),
      ),
    ),
  );
}

/// The five lavender bars beside "Hearing:". Still, so nothing moves with reduced motion.
class _SoundBars extends StatelessWidget {
  const _SoundBars();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final h in const [10.0, 20.0, 14.0, 24.0, 12.0])
        Container(
          width: 6,
          height: h,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(color: LtColors.lavender, borderRadius: BorderRadius.circular(3)),
        ),
    ],
  );
}

/// Tap to start talking and tap again when done; holding and letting go also works.
/// [compact] is the read-back's smaller Talk (Readback.dc.html), under Yes and
/// "No, change it", so Yes stays the one big mint button.
class TalkButton extends StatefulWidget {
  const TalkButton({super.key, required this.controller, this.compact = false});
  final VoiceOnboardingController controller;
  final bool compact;

  @override
  State<TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<TalkButton> {
  static const _holdThreshold = Duration(milliseconds: 600);
  DateTime? _downAt;
  bool _stoppedByThisPress = false;

  VoiceOnboardingController get c => widget.controller;

  void _down(PointerDownEvent _) {
    if (c.phase == VoicePhase.interpreting) return;
    if (c.phase == VoicePhase.listening) {
      _stoppedByThisPress = true;
      c.stopTalk();
    } else {
      _stoppedByThisPress = false;
      _downAt = DateTime.now();
      c.startTalk();
    }
  }

  void _up(PointerUpEvent _) {
    final at = _downAt;
    if (_stoppedByThisPress || at == null) return;
    _downAt = null;
    // A long press is "hold to talk": letting go sends. A short tap keeps listening.
    if (DateTime.now().difference(at) >= _holdThreshold) c.stopTalk();
  }

  void _cancel(PointerCancelEvent _) {
    if (_stoppedByThisPress) return;
    _downAt = null;
    c.cancelTalk();
  }

  /// Taps are handled by the Listener above; the face only shows the press.
  static void _noop() {}

  LipStyle _style({required bool listening}) => LipStyle(
    face: listening ? LtColors.listening : LtColors.mint,
    lip: listening ? LtColors.listeningLip : LtColors.mintDeep,
    radius: LtRadii.primary,
    lipDepth: LtLip.primary,
    minHeight: widget.compact ? LtSize.minButton : LtSize.primaryButton,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  );

  @override
  Widget build(BuildContext context) {
    final listening = c.phase == VoicePhase.listening;
    final busy = c.phase == VoicePhase.interpreting;
    final left = c.listenSecondsLeft;
    final label = busy
        ? 'One moment…'
        : c.phase == VoicePhase.speaking
        ? 'Tap to answer'
        : 'Tap to talk';
    final big = largeText(context);
    final ink = busy ? LipStyle.disabledOutline : LtColors.ink;

    Widget lay(Widget icon, Widget text, {double gap = 18}) => big
        ? Column(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(height: 6), text])
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              SizedBox(width: gap),
              Flexible(child: text),
            ],
          );

    final Widget face;
    if (listening) {
      final dot = MediaQuery.disableAnimationsOf(context) ? const RecordingDot() : const _Pulse(child: RecordingDot());
      face = LipButton(
        style: _style(listening: true),
        onPressed: _noop,
        child: lay(
          dot,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: big ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text('Listening…', style: LtText.primaryButton),
              Text(
                'tap when done${left == null ? '' : ' ($left s left)'}',
                textAlign: big ? TextAlign.center : TextAlign.start,
                style: LtText.bodyStrong,
              ),
            ],
          ),
          gap: 20,
        ),
      );
    } else if (widget.compact) {
      // Read-back: the underlined "Talk" link of the artboard, at least 56 pt tall.
      face = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: LtSize.smallTap, minWidth: double.infinity),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(opacity: busy ? .5 : 1, child: const LtIcon(LtIconKind.mic, size: 28)),
              const SizedBox(width: LtSpace.sm),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: LtText.link.copyWith(color: ink, decorationColor: ink),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Question.dc.html: mic in a white circle, label beside it (above it with large text).
      final mic = Opacity(
        opacity: busy ? .5 : 1,
        child: Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LtColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: ink, width: LtOutline.width),
          ),
          child: const LtIcon(LtIconKind.mic, size: 32),
        ),
      );
      face = LipButton(
        style: _style(listening: false),
        onPressed: busy ? null : _noop,
        child: lay(
          mic,
          Text(
            label,
            textAlign: TextAlign.center,
            style: LtText.primaryButton.copyWith(color: ink),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      enabled: !busy,
      label: busy ? label : (listening ? 'Stop listening' : 'Talk'),
      value: listening ? 'Listening' : 'Not listening',
      hint: busy ? null : (listening ? 'Double tap when you are done' : 'Double tap, then speak'),
      excludeSemantics: true,
      onTap: busy ? null : () => listening ? c.stopTalk() : c.startTalk(),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: face,
      ),
    );
  }
}

/// The red "recording" dot shown while the microphone is open (Listening.dc.html).
class RecordingDot extends StatelessWidget {
  const RecordingDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    margin: const EdgeInsets.all(8), // room for the halo
    decoration: const BoxDecoration(
      color: LtColors.recording,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: Color(0x38D7402B), spreadRadius: 8)],
    ),
  );
}

/// A slow fade in and out. Only used when the phone allows motion.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: Tween(begin: 0.35, end: 1.0).animate(_a), child: widget.child);
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.message, this.onRetry, this.onOpenSettings});
  final String message;
  final VoidCallback? onRetry;
  final Future<void> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: const BoxDecoration(
          color: LtColors.lavenderWash,
          borderRadius: LtRadii.card,
          border: Border.fromBorderSide(LtOutline.side),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: LtText.bodyStrong),
            if (onRetry != null) ...[
              const SizedBox(height: LtSpace.lg),
              LtSecondaryButton(label: 'Try again', onPressed: onRetry),
            ],
            if (onOpenSettings != null) ...[
              const SizedBox(height: LtSpace.lg),
              LtSecondaryButton(label: 'Open Settings', onPressed: onOpenSettings),
            ],
          ],
        ),
      ),
    );
  }
}
