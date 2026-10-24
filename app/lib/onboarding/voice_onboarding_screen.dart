import 'package:flutter/material.dart';

import 'voice_onboarding_controller.dart';

/// Mascot conversation by voice or typing. One action per screen, large type,
/// captions always on, nothing disappears by itself.
class VoiceOnboardingScreen extends StatefulWidget {
  const VoiceOnboardingScreen({super.key, required this.controller, required this.onDone, this.onUseHealth});

  final VoiceOnboardingController controller;

  /// Called with the confirmed profile when the conversation is finished.
  final void Function(Map<String, dynamic> confirmedProfile) onDone;

  /// Opens the Apple Health import. The button is hidden when null.
  final VoidCallback? onUseHealth;

  @override
  State<VoiceOnboardingScreen> createState() => _VoiceOnboardingScreenState();
}

class _VoiceOnboardingScreenState extends State<VoiceOnboardingScreen> {
  final _text = TextEditingController();

  /// The voice answer from the first consent question, kept until the second is answered.
  bool? _voiceChoice;

  VoiceOnboardingController get c => widget.controller;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text;
    if (t.trim().isEmpty) return;
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
                ? Padding(padding: const EdgeInsets.all(24), child: _talk(context))
                : CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: c.askingVoice
                              ? _voiceAgain(context)
                              : c.phase == VoicePhase.consent && c.turn == null && !c.canRetry
                              ? _consent(context)
                              : _talk(context),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _consent(BuildContext context) {
    final voice = _voiceChoice;
    if (voice != null) return _aiConsent(context, voice);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Talk with me?', style: text.headlineMedium)),
        const SizedBox(height: 24),
        Text(
          'Your voice is sent to Cartesia, a voice service, only while you hold the Talk button. '
          'It turns your words into text and speaks my answers. LifeTwin does not keep recordings.\n\n'
          'You can type instead at any time.',
          style: text.titleLarge?.copyWith(height: 1.4),
        ),
        const Spacer(),
        const SizedBox(height: 24),
        BigButton(label: 'Yes, I can talk', filled: true, onTap: () => setState(() => _voiceChoice = true)),
        const SizedBox(height: 16),
        BigButton(label: 'Type instead', filled: false, onTap: () => setState(() => _voiceChoice = false)),
      ],
    );
  }

  /// Same question as the first screen, asked when someone who started by
  /// typing wants to talk.
  Widget _voiceAgain(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Talk with me?', style: text.headlineMedium)),
        const SizedBox(height: 24),
        Text(
          'Your voice is sent to Cartesia, a voice service, only while you hold the Talk button. '
          'It turns your words into text and speaks my answers. LifeTwin does not keep recordings.\n\n'
          'You can type instead at any time.',
          style: text.titleLarge?.copyWith(height: 1.4),
        ),
        const Spacer(),
        const SizedBox(height: 24),
        BigButton(label: 'Yes, I can talk', filled: true, onTap: () => c.answerVoiceAgain(true)),
        const SizedBox(height: 16),
        BigButton(label: 'Keep typing', filled: false, onTap: () => c.answerVoiceAgain(false)),
      ],
    );
  }

  /// Second question: may an AI helper read the answers? We encourage yes, but
  /// "Not now" works fully, and it can be turned on later.
  Widget _aiConsent(BuildContext context, bool voice) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Turn on the AI helper?', style: text.headlineMedium)),
        const SizedBox(height: 24),
        Text(
          'It lets you answer in your own words, like "about five foot eight".\n\n'
          "Your answers go to an outside AI service. LifeTwin doesn't keep them, "
          'and I still check each one with you.\n\n'
          'You can change this any time.',
          style: text.titleLarge?.copyWith(height: 1.4),
        ),
        const Spacer(),
        const SizedBox(height: 24),
        BigButton(label: 'Yes, turn it on', filled: true, onTap: () => c.answerConsent(voice, aiHelper: true)),
        const SizedBox(height: 16),
        BigButton(label: 'Not now', filled: false, onTap: () => c.answerConsent(voice)),
      ],
    );
  }

  Widget _talk(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final busy = c.phase == VoicePhase.interpreting;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final header =
        // Mascot line: always visible as a caption, announced when it changes.
        Semantics(
          liveRegion: true,
          container: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExcludeSemantics(child: Icon(Icons.pets, size: 48)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  c.mascotLine.isEmpty ? (busy ? 'One moment…' : '') : c.mascotLine,
                  style: text.headlineSmall?.copyWith(height: 1.35),
                ),
              ),
            ],
          ),
        );
    // The question stays put while the rest scrolls, so the keyboard never hides it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
          child: SingleChildScrollView(child: header),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    if (c.caption.isNotEmpty && !keyboard)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          c.phase == VoicePhase.listening ? 'Hearing: ${c.caption}' : 'You said: ${c.caption}',
                          style: text.titleLarge?.copyWith(fontStyle: FontStyle.italic, height: 1.35),
                        ),
                      ),
                    if (c.notice != null) ...[
                      const SizedBox(height: 16),
                      _NoticeBox(message: c.notice!, onRetry: c.canRetry ? c.retry : null),
                    ],
                    const Spacer(),
                    const SizedBox(height: 24),
                    ..._controls(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _controls(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final busy = c.phase == VoicePhase.interpreting;
    if (c.phase == VoicePhase.done) {
      return [
        BigButton(label: 'Continue', filled: true, onTap: () => widget.onDone(c.confirmedProfile)),
        if (widget.onUseHealth != null) ...[
          const SizedBox(height: 16),
          BigButton(label: 'Use my Health app', filled: false, onTap: widget.onUseHealth!),
        ],
        if (c.canHearAgain) ...[const SizedBox(height: 12), _hearAgain()],
      ];
    }
    if (c.confirming && c.correcting) {
      return [
        Text('Okay. What is the right answer?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        if (c.typing) ..._typingControls(busy) else TalkButton(controller: c),
        const SizedBox(height: 12),
        if (!busy) BigButton(label: 'Never mind', filled: false, onTap: c.keepAnswer),
        _modeSwitch(),
      ];
    }
    if (c.confirming && !busy) {
      return [
        BigButton(label: 'Yes', filled: true, onTap: c.confirm),
        const SizedBox(height: 16),
        BigButton(label: 'Change', filled: false, onTap: c.change),
        const SizedBox(height: 12),
        if (c.canHearAgain) _hearAgain(),
        _modeSwitch(),
      ];
    }
    return [
      if (c.helperWouldHelp && !busy) ...[
        BigButton(label: 'Yes, let the AI helper read it', filled: true, onTap: () => c.setAiHelper(true)),
        const SizedBox(height: 16),
      ],
      if (c.quickAnswers.isNotEmpty) ...[_quickAnswers(busy), const SizedBox(height: 16)],
      if (c.typing) ..._typingControls(busy) else TalkButton(controller: c),
      const SizedBox(height: 12),
      if (!keyboard) ...[
        if (c.canHearAgain) _hearAgain(),
        _modeSwitch(),
        _helperSwitch(),
        if (widget.onUseHealth != null)
          TextButton.icon(
            onPressed: widget.onUseHealth,
            icon: const Icon(Icons.favorite_border),
            label: Text('Use my Health app instead', style: Theme.of(context).textTheme.titleMedium),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
      ],
    ];
  }

  /// Two per row when they fit, one per row when the text is large.
  Widget _quickAnswers(bool busy) {
    final answers = c.quickAnswers;
    // The screen pads 24 on each side. LayoutBuilder can't sit in this scroll view.
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

  List<Widget> _typingControls(bool busy) => [
    TextField(
      controller: _text,
      enabled: !busy,
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
    BigButton(label: busy ? 'One moment…' : 'Send', filled: true, onTap: busy ? null : _send),
    if (MediaQuery.viewInsetsOf(context).bottom > 0) ...[
      const SizedBox(height: 12),
      BigButton(label: 'Hide keyboard', filled: false, onTap: () => FocusManager.instance.primaryFocus?.unfocus()),
    ],
  ];

  Widget _hearAgain() => TextButton.icon(
    onPressed: c.hearAgain,
    icon: const Icon(Icons.volume_up),
    label: Text('Hear it again', style: Theme.of(context).textTheme.titleMedium),
    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
  );

  Widget _helperSwitch() => TextButton.icon(
    onPressed: () => c.setAiHelper(!c.aiHelper),
    icon: Icon(c.aiHelper ? Icons.auto_awesome : Icons.auto_awesome_outlined),
    label: Text(
      c.aiHelper ? 'Turn off AI helper' : 'Turn on AI helper',
      style: Theme.of(context).textTheme.titleMedium,
    ),
    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
  );

  Widget _modeSwitch() {
    final toVoice = c.typing;
    if (toVoice) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: BigButton(label: 'Talk instead', filled: false, onTap: () => c.setTyping(false)),
      );
    }
    return TextButton.icon(
      onPressed: () => c.setTyping(!c.typing),
      icon: Icon(toVoice ? Icons.mic : Icons.keyboard),
      label: Text(toVoice ? 'Talk instead' : 'Type instead', style: Theme.of(context).textTheme.titleMedium),
      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
    );
  }
}

/// Hold to talk. Tap once to start and again to stop, for people who can't hold.
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
    final label = busy
        ? 'One moment…'
        : listening
        ? 'Listening. Tap or let go when done'
        : 'Hold to talk';
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: !busy,
      label: busy ? label : (listening ? 'Stop listening' : 'Talk'),
      hint: busy ? null : (listening ? 'Double tap to send' : 'Hold, or double tap to start and again to stop'),
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
              Icon(
                listening ? Icons.mic : Icons.mic_none,
                size: 36,
                color: busy ? scheme.onSurfaceVariant : (listening ? scheme.onTertiary : scheme.onPrimary),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: busy ? scheme.onSurfaceVariant : (listening ? scheme.onTertiary : scheme.onPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

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
          ],
        ),
      ),
    );
  }
}

/// Full-width button, at least 72 pt tall.
class BigButton extends StatelessWidget {
  const BigButton({super.key, required this.label, required this.onTap, required this.filled});

  final String label;
  final VoidCallback? onTap;
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
