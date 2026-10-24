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
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: c.phase == VoicePhase.consent && c.turn == null && !c.canRetry ? _consent(context) : _talk(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _consent(BuildContext context) {
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
        BigButton(label: 'Yes, I can talk', filled: true, onTap: () => c.answerConsent(true)),
        const SizedBox(height: 16),
        BigButton(label: 'Type instead', filled: false, onTap: () => c.answerConsent(false)),
      ],
    );
  }

  Widget _talk(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final busy = c.phase == VoicePhase.interpreting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        ),
        const SizedBox(height: 24),
        if (c.caption.isNotEmpty)
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
    );
  }

  List<Widget> _controls(BuildContext context) {
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
      if (c.typing) ..._typingControls(busy) else TalkButton(controller: c),
      const SizedBox(height: 12),
      if (c.canHearAgain) _hearAgain(),
      _modeSwitch(),
      if (widget.onUseHealth != null)
        TextButton.icon(
          onPressed: widget.onUseHealth,
          icon: const Icon(Icons.favorite_border),
          label: Text('Use my Health app instead', style: Theme.of(context).textTheme.titleMedium),
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
    ];
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
      ];

  Widget _hearAgain() => TextButton.icon(
        onPressed: c.hearAgain,
        icon: const Icon(Icons.volume_up),
        label: Text('Hear it again', style: Theme.of(context).textTheme.titleMedium),
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      );

  Widget _modeSwitch() {
    if (c.typing && !c.voiceUsable) return const SizedBox.shrink();
    final toVoice = c.typing;
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
              Icon(listening ? Icons.mic : Icons.mic_none,
                  size: 36, color: busy ? scheme.onSurfaceVariant : (listening ? scheme.onTertiary : scheme.onPrimary)),
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
            Text(message,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSecondaryContainer, height: 1.35)),
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
