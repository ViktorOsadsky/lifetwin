import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'voice_onboarding_controller.dart';

/// Fields whose answer is a number: the keyboard opens on the number pad.
const numberFields = {'age', 'weight_kg', 'sleep_hours', 'exercise_minutes_weekly', 'alcohol_drinks_weekly'};

/// Opens this app's page in the iPhone Settings app (to turn the microphone on).
Future<void> openAppSettings() async {
  try {
    await launchUrl(Uri.parse('app-settings:'));
  } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Tapping anywhere that is not a control puts the keyboard away.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => !c.askingVoice && !(c.phase == VoicePhase.consent && c.turn == null && !c.canRetry)
                ? _talk(context)
                : CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: c.askingVoice ? _voiceAgain(context) : _consent(context),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  static const _voiceCopy =
      'You can talk to me, or type. While you talk, your voice is sent to Cartesia, '
      'a speech service, to turn it into words.';

  Widget _question(BuildContext context, {required String title, required String body, required List<Widget> buttons}) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(title, style: text.headlineMedium)),
        const SizedBox(height: 24),
        Text(body, style: text.titleLarge?.copyWith(height: 1.4)),
        const Spacer(),
        const SizedBox(height: 24),
        ...buttons,
      ],
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
        BigButton(label: "Yes, I'll talk", filled: true, onTap: () => setState(() => _voiceChoice = true)),
        const SizedBox(height: 16),
        BigButton(label: "No, I'll type", filled: false, onTap: () => setState(() => _voiceChoice = false)),
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
      BigButton(label: "Yes, I'll talk", filled: true, onTap: () => c.answerVoiceAgain(true)),
      const SizedBox(height: 16),
      BigButton(label: 'Keep typing', filled: false, onTap: () => c.answerVoiceAgain(false)),
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
      BigButton(label: 'Yes, turn it on', filled: true, onTap: () => c.answerConsent(voice, aiHelper: true)),
      const SizedBox(height: 16),
      BigButton(label: 'Not now', filled: false, onTap: () => c.answerConsent(voice)),
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _story(context, keyboard)),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * (hideKeyboard ? 0.5 : 0.6)),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 0, 24, hideKeyboard ? 8 : 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _controls(context, keyboard)),
            ),
          ),
          if (hideKeyboard)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: BigButton(
                label: 'Hide keyboard',
                filled: false,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ),
        ],
      ),
    );
  }

  bool get _showsTypingBox => c.typing && c.phase != VoicePhase.done && (!c.confirming || c.correcting);

  /// Progress, the mascot's words, what was heard, and any notice.
  List<Widget> _story(BuildContext context, bool keyboard) {
    final text = Theme.of(context).textTheme;
    final busy = c.phase == VoicePhase.interpreting;
    final line = c.mascotLine.isEmpty ? (busy ? 'One moment…' : '') : c.mascotLine;
    final bigText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final n = c.questionNumber;
    return [
      if (n != null) ...[
        Text(
          'Question $n of ${VoiceOnboardingController.questionCount}',
          style: text.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
      ],
      // Mascot line: always visible as a caption, announced when it changes.
      Semantics(
        liveRegion: true,
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // With very large text the paw takes room the words need.
            if (!bigText) ...[const ExcludeSemantics(child: Icon(Icons.pets, size: 48)), const SizedBox(width: 16)],
            Expanded(
              child: Text(
                line,
                style: (line.length > 80 ? text.titleLarge : text.headlineSmall)?.copyWith(height: 1.35),
              ),
            ),
          ],
        ),
      ),
      if (c.phase == VoicePhase.speaking)
        _speaking(context)
      else if (c.canHearAgain && c.phase != VoicePhase.listening)
        _hearAgain(),
      if (c.caption.isNotEmpty && !keyboard) ...[
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            c.phase == VoicePhase.listening ? 'Hearing: ${c.caption}' : 'You said: ${c.caption}',
            style: text.titleLarge?.copyWith(height: 1.35),
          ),
        ),
      ],
      if (c.notice != null) ...[
        const SizedBox(height: 16),
        _NoticeBox(
          message: c.notice!,
          onRetry: c.canRetry ? c.retry : null,
          onOpenSettings: c.notice == micDeniedNotice ? widget.onOpenSettings : null,
        ),
      ],
      if (!c.confirming && c.phase != VoicePhase.done) ...[
        if (c.helperWouldHelp && !busy) ...[
          const SizedBox(height: 16),
          BigButton(label: 'Yes, let the AI helper read it', filled: true, onTap: () => c.setAiHelper(true)),
        ],
        if (c.quickAnswers.isNotEmpty) ...[const SizedBox(height: 16), _quickAnswers(busy)],
      ],
    ];
  }

  Widget _speaking(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          'Speaking…',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
      TextButton.icon(
        onPressed: c.stopSpeaking,
        icon: const Icon(Icons.stop),
        label: Text('Stop', style: Theme.of(context).textTheme.titleMedium),
        style: TextButton.styleFrom(minimumSize: const Size(96, 56)),
      ),
    ],
  );

  List<Widget> _controls(BuildContext context, bool keyboard) {
    final busy = c.phase == VoicePhase.interpreting;
    if (c.phase == VoicePhase.done) {
      return [
        BigButton(label: 'Continue', filled: true, onTap: () => widget.onDone(c.confirmedProfile)),
        if (widget.onUseHealth != null) ...[
          const SizedBox(height: 16),
          BigButton(label: 'Use my Health app', filled: false, onTap: widget.onUseHealth!),
        ],
      ];
    }
    if (c.confirming && c.correcting) {
      return [
        Text('Okay. What is the right answer?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        ..._answerControls(busy),
        const SizedBox(height: 12),
        if (!busy && !keyboard) BigButton(label: 'Never mind', filled: false, onTap: c.keepAnswer),
        if (!keyboard) ..._more(),
      ];
    }
    if (c.confirming) {
      return [
        BigButton(label: 'Yes', filled: true, onTap: busy ? null : c.confirm),
        const SizedBox(height: 16),
        BigButton(label: 'No, change it', filled: false, onTap: busy ? null : c.change),
        // By voice, the person can also just say yes, no, or the right answer.
        if (!c.typing) ...[const SizedBox(height: 16), TalkButton(controller: c)],
        ..._more(),
      ];
    }
    return [
      ..._answerControls(busy),
      const SizedBox(height: 12),
      _SecondaryButton(label: 'Skip this question', icon: Icons.skip_next, onTap: busy ? null : c.skip),
      if (!keyboard) ..._more(),
    ];
  }

  /// The typing box and Send, or the Talk button.
  List<Widget> _answerControls(bool busy) {
    if (!c.typing) return [TalkButton(controller: c)];
    final field = c.state?['current_field'];
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
        style: Theme.of(context).textTheme.titleLarge,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _send(),
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Type your answer',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.all(18),
        ),
      ),
      const SizedBox(height: 16),
      BigButton(
        key: const ValueKey('send'),
        label: busy ? 'One moment…' : 'Send',
        filled: true,
        onTap: busy ? null : _send,
      ),
    ];
  }

  /// Less-used choices, under the main ones.
  List<Widget> _more() => [
    if (c.canGoBack) ...[
      const SizedBox(height: 12),
      _SecondaryButton(label: 'Go back', icon: Icons.arrow_back, onTap: c.goBack),
    ],
    const SizedBox(height: 12),
    _SecondaryButton(
      label: c.typing ? 'Talk instead' : 'Type instead',
      icon: c.typing ? Icons.mic : Icons.keyboard,
      onTap: () => c.setTyping(!c.typing),
    ),
    if (widget.onUseHealth != null && c.questionNumber == 1 && !c.confirming) ...[
      const SizedBox(height: 12),
      _SecondaryButton(label: 'Use my Health app instead', icon: Icons.favorite_border, onTap: widget.onUseHealth),
    ],
    const SizedBox(height: 4),
    TextButton.icon(
      onPressed: _openSettings,
      icon: const Icon(Icons.settings),
      label: Text('Settings', style: Theme.of(context).textTheme.titleMedium),
      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
    ),
  ];

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (sheet, _) {
            final text = Theme.of(sheet).textTheme;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(header: true, child: Text('Settings', style: text.headlineSmall)),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('AI helper', style: text.titleLarge),
                    subtitle: Text('Reads answers I can’t understand', style: text.titleMedium),
                    value: c.aiHelper,
                    onChanged: (on) => c.setAiHelper(on),
                  ),
                  const SizedBox(height: 16),
                  Text('Answer by', style: text.titleLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(Size(0, 56)),
                      textStyle: WidgetStatePropertyAll(text.titleMedium),
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
                  const SizedBox(height: 24),
                  BigButton(label: 'Done', filled: true, onTap: () => Navigator.of(sheet).pop()),
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
    // The screen pads 24 on each side.
    final width = MediaQuery.sizeOf(context).width - 48;
    const gap = 12.0;
    final perRow = MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 1 : 2;
    final w = (width - gap * (perRow - 1)) / perRow;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final (label, say) in answers)
          SizedBox(
            width: w,
            child: BigButton(label: label, filled: false, onTap: busy ? null : () => c.submitQuick(say)),
          ),
      ],
    );
  }

  Widget _hearAgain() => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      onPressed: c.hearAgain,
      icon: const Icon(Icons.volume_up),
      label: Text('Hear it again', style: Theme.of(context).textTheme.titleMedium),
      style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
    ),
  );
}

/// Tap to start talking and tap again when done; holding and letting go also works.
class TalkButton extends StatefulWidget {
  const TalkButton({super.key, required this.controller});
  final VoiceOnboardingController controller;

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

  @override
  Widget build(BuildContext context) {
    final listening = c.phase == VoicePhase.listening;
    final busy = c.phase == VoicePhase.interpreting;
    final left = c.listenSecondsLeft;
    final label = busy
        ? 'One moment…'
        : listening
        ? 'Listening… tap when done${left == null ? '' : ' ($left s left)'}'
        : c.phase == VoicePhase.speaking
        ? 'Tap to answer'
        : 'Tap to talk';
    final scheme = Theme.of(context).colorScheme;
    final fg = busy ? scheme.onSurfaceVariant : (listening ? scheme.onTertiary : scheme.onPrimary);
    return Semantics(
      button: true,
      enabled: !busy,
      label: busy ? label : (listening ? 'Stop listening' : 'Talk'),
      value: listening ? 'Listening' : 'Not listening',
      hint: busy ? null : (listening ? 'Double tap when you are done' : 'Double tap, then speak'),
      excludeSemantics: true,
      onTap: busy ? null : () => listening ? c.stopTalk() : c.startTalk(),
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: busy
                ? scheme.surfaceContainerHighest
                : listening
                ? scheme.tertiary
                : scheme.primary,
            borderRadius: BorderRadius.circular(44),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (listening)
                MediaQuery.disableAnimationsOf(context) ? const RecordingDot() : const _Pulse(child: RecordingDot())
              else
                Icon(Icons.mic_none, size: 36, color: fg),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The red "recording" dot shown while the microphone is open.
class RecordingDot extends StatelessWidget {
  const RecordingDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: const Color(0xFFD32F2F),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
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
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: scheme.onSecondaryContainer, height: 1.35),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              BigButton(label: 'Try again', filled: false, onTap: onRetry),
            ],
            if (onOpenSettings != null) ...[
              const SizedBox(height: 12),
              BigButton(label: 'Open Settings', filled: false, onTap: onOpenSettings),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-width button, at least 72 pt tall. The outlined kind has a 2 pt
/// border and dark text so it is easy to see.
class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.label, required this.onTap, required this.filled});

  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(72)),
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.titleLarge),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
    );
    final child = Text(label, textAlign: TextAlign.center);
    return filled
        ? FilledButton(onPressed: onTap, style: style, child: child)
        : OutlinedButton(onPressed: onTap, style: style.merge(secondaryStyle(scheme)), child: child);
  }

  /// 2 pt border and dark text for outlined (secondary) buttons.
  static ButtonStyle secondaryStyle(ColorScheme scheme) => ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.45) : scheme.onSurface,
    ),
    side: WidgetStateProperty.resolveWith(
      (s) => BorderSide(
        width: 2,
        color: s.contains(WidgetState.disabled) ? scheme.onSurface.withValues(alpha: 0.2) : scheme.outline,
      ),
    ),
  );
}

/// Full-width outlined button, at least 56 pt tall, with an icon.
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon),
    label: Text(label, textAlign: TextAlign.center),
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(56)),
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.titleMedium),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
    ).merge(BigButton.secondaryStyle(Theme.of(context).colorScheme)),
  );
}
