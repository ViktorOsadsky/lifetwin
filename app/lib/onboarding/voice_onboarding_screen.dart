import 'package:flutter/material.dart';

import '../forecast/forecast_client.dart' show forecastProfileFields;
import '../forecast/profile_labels.dart';
import '../health/readback.dart' show usesImperial;
import '../ui/swoosh_route.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart';
import 'voice_onboarding_controller.dart';

/// Mascot conversation by voice or typing (V-2 / V-3). One action per screen,
/// large type, captions always on, nothing disappears by itself. The twin
/// asks in the window's bubble; the controls live on the sheet.
class VoiceOnboardingScreen extends StatefulWidget {
  const VoiceOnboardingScreen({
    super.key,
    required this.controller,
    required this.onDone,
    this.onUseHealth,
    this.appearance = const TwinAppearance(),
  });

  final VoiceOnboardingController controller;

  /// Called with the confirmed profile when the conversation is finished.
  final void Function(Map<String, dynamic> confirmedProfile) onDone;

  /// Opens the Apple Health import. The chip is hidden when null.
  final VoidCallback? onUseHealth;

  /// Cosmetic look of the twin in the window.
  final TwinAppearance appearance;

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

  static const _voiceConsent =
      'Your voice is sent to Cartesia, a voice service, only while you hold the Talk button. '
      'It turns your words into text and speaks my answers. LifeTwin does not keep recordings.\n\n'
      'You can type instead at any time.';

  @override
  Widget build(BuildContext context) {
    return SwooshStage(
      builder: (context, frame) {
        // During the swoosh the Room shows through until the mint wash is in.
        final route = ModalRoute.of(context)?.animation;
        final reduced = MediaQuery.disableAnimationsOf(context);
        final wash = reduced || route == null ? 1.0 : const Interval(0, 0.3).transform(route.value);
        final window = reduced || route == null ? 1.0 : const Interval(0.12, 0.4).transform(route.value);
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: wash,
                  child: DecoratedBox(decoration: BoxDecoration(gradient: LtMode.onboarding.gradient)),
                ),
              ),
              SafeArea(
                // Tapping anywhere that is not a control puts the keyboard away.
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: ListenableBuilder(listenable: c, builder: (context, _) => _page(context, frame, window)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool get _consentShown => c.phase == VoicePhase.consent && c.turn == null && !c.canRetry;

  Widget _page(BuildContext context, SwooshFrame frame, double windowOpacity) {
    final String bubble;
    final bool header;
    final Widget body;
    if (c.askingVoice) {
      bubble = 'Talk with me?';
      header = true;
      body = _voiceAgain(context);
    } else if (_consentShown && _voiceChoice != null) {
      bubble = 'Turn on the AI helper?';
      header = true;
      body = _aiConsent(context, _voiceChoice!);
    } else if (_consentShown) {
      bubble = 'Talk with me?';
      header = true;
      body = _consent(context);
    } else {
      final busy = c.phase == VoicePhase.interpreting;
      bubble = c.mascotLine.isEmpty ? (busy ? 'One moment…' : '') : c.mascotLine;
      header = false;
      body = _talk(context);
    }
    final canBack = Navigator.of(context).canPop();
    return PlateSheetLayout(
      minWindow: 160,
      window: Opacity(
        opacity: windowOpacity,
        child: PlateWindow(
          name: widget.appearance.name,
          plate: PlateScene(
            asset: ScenePlate.room.asset,
            focus: const Offset(0.5, 0.554),
            focusTarget: const Offset(0.3, 0.84),
            zoom: 1.38,
            twinBuilder: (feet, scale, box) => plantTwin(
              feet,
              TwinSprite(
                appearance: widget.appearance,
                pose: TwinPose.wave,
                height: (185 * scale).clamp(60.0, box.height * 0.82 < 60 ? 60.0 : box.height * 0.82),
                hero: true,
                isRoom: false,
              ),
            ),
          ),
          overlay: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                if (canBack)
                  Positioned(
                    left: 14,
                    top: 18,
                    child: Opacity(
                      opacity: frame.backOpacity.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: frame.backScale,
                        child: RoundBackButton(label: 'Back to room', onTap: () => Navigator.of(context).maybePop()),
                      ),
                    ),
                  ),
                if (bubble.isNotEmpty)
                  Positioned(
                    top: 34,
                    right: 8,
                    width: box.maxWidth * 0.58,
                    child: Opacity(
                      opacity: frame.bubbleOpacity.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: frame.bubbleScale,
                        alignment: Alignment.centerLeft,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Bubble(
                            text: bubble,
                            tail: BubbleTail.left,
                            tailAt: 0.3,
                            fontSize: bubble.length <= 24 ? 26 : 22,
                            liveRegion: !header,
                            header: header,
                            maxHeight: (box.maxHeight - 56).clamp(60.0, double.infinity),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      sheet: SwooshSheetTransform(
        frame: frame,
        child: Sheet(child: body),
      ),
    );
  }

  Widget _consent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_voiceConsent, style: LtText.body(size: 18)),
        const SizedBox(height: 20),
        BigButton(label: 'Yes, I can talk', filled: true, onTap: () => setState(() => _voiceChoice = true)),
        const SizedBox(height: 14),
        BigButton(label: 'Type instead', filled: false, onTap: () => setState(() => _voiceChoice = false)),
      ],
    );
  }

  /// Same question as the first screen, asked when someone who started by
  /// typing wants to talk.
  Widget _voiceAgain(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_voiceConsent, style: LtText.body(size: 18)),
        const SizedBox(height: 20),
        BigButton(label: 'Yes, I can talk', filled: true, onTap: () => c.answerVoiceAgain(true)),
        const SizedBox(height: 14),
        BigButton(label: 'Keep typing', filled: false, onTap: () => c.answerVoiceAgain(false)),
      ],
    );
  }

  /// Second question: may an AI helper read the answers? We encourage yes, but
  /// "Not now" works fully, and it can be turned on later.
  Widget _aiConsent(BuildContext context, bool voice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'It lets you answer in your own words, like "about five foot eight".\n\n'
          "Your answers go to an outside AI service. LifeTwin doesn't keep them, "
          'and I still check each one with you.\n\n'
          'You can change this any time.',
          style: LtText.body(size: 18),
        ),
        const SizedBox(height: 20),
        BigButton(label: 'Yes, turn it on', filled: true, onTap: () => c.answerConsent(voice, aiHelper: true)),
        const SizedBox(height: 14),
        BigButton(label: 'Not now', filled: false, onTap: () => c.answerConsent(voice)),
      ],
    );
  }

  Widget _talk(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final state = c.state ?? const {};
    final skipped = (state['skipped_fields'] as List?)?.length ?? 0;
    final total = forecastProfileFields.length;
    final done = c.phase == VoicePhase.done ? total : (c.confirmedProfile.length + skipped).clamp(0, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProgressDots(done: done, total: total),
        if (c.caption.isNotEmpty && !keyboard) ...[
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              c.phase == VoicePhase.listening ? 'Hearing: ${c.caption}' : 'You said: ${c.caption}',
              style: LtText.body(size: 18).copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ],
        if (c.notice != null) ...[
          const SizedBox(height: 14),
          _NoticeBox(message: c.notice!, onRetry: c.canRetry ? c.retry : null),
        ],
        const SizedBox(height: 18),
        ..._controls(context),
      ],
    );
  }

  List<Widget> _controls(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final busy = c.phase == VoicePhase.interpreting;
    if (c.phase == VoicePhase.done) {
      return [
        BigButton(label: 'Continue', filled: true, onTap: () => widget.onDone(c.confirmedProfile)),
        if (widget.onUseHealth != null) ...[const SizedBox(height: 12), _healthChip()],
        if (c.canHearAgain) ...[const SizedBox(height: 8), _hearAgain()],
      ];
    }
    if (c.confirming && c.correcting) {
      return [
        Text('Okay. What is the right answer?', style: LtText.body(size: 20, weight: FontWeight.w700)),
        const SizedBox(height: 14),
        if (c.typing) ..._typingControls(busy) else TalkButton(controller: c),
        const SizedBox(height: 12),
        if (!busy) BigButton(label: 'Never mind', filled: false, height: 60, onTap: c.keepAnswer),
        _modeSwitch(),
      ];
    }
    if (c.confirming && !busy) {
      final pending = Map<String, dynamic>.from((c.state?['pending_profile'] as Map?) ?? const {});
      final imperial = usesImperial(WidgetsBinding.instance.platformDispatcher.locale.countryCode);
      final labels = [for (final (_, l) in profileLabels(pending, imperial: imperial)) l];
      return [
        if (labels.isNotEmpty) ...[_ValueCard(text: labels.join(' · ')), const SizedBox(height: 18)],
        BigButton(label: 'Yes', filled: true, icon: Icons.check_rounded, onTap: c.confirm),
        const SizedBox(height: 14),
        BigButton(label: 'Change', filled: false, height: 60, icon: Icons.edit_rounded, onTap: c.change),
        const SizedBox(height: 8),
        if (c.canHearAgain) _hearAgain(),
        _modeSwitch(),
      ];
    }
    return [
      if (c.helperWouldHelp && !busy) ...[
        BigButton(label: 'Yes, let the AI helper read it', filled: true, onTap: () => c.setAiHelper(true)),
        const SizedBox(height: 14),
      ],
      if (c.typing) ..._typingControls(busy) else TalkButton(controller: c),
      const SizedBox(height: 4),
      if (!keyboard) ...[
        if (c.canHearAgain) _hearAgain(),
        _modeSwitch(),
        const SizedBox(height: 8),
        if (widget.onUseHealth != null) ...[_healthChip(), const SizedBox(height: 10)],
        LtToggleChip(
          label: c.aiHelper ? 'AI helper: On' : 'AI helper: Off',
          semanticLabel: 'AI helper',
          icon: Icons.auto_awesome_outlined,
          value: c.aiHelper,
          onChanged: (on) => c.setAiHelper(on),
        ),
      ],
    ];
  }

  Widget _healthChip() => LtChip(
    label: 'Use my Health app',
    icon: Icons.favorite_border_rounded,
    trailing: const Icon(Icons.chevron_right_rounded, color: LtColors.ink),
    onTap: widget.onUseHealth,
  );

  List<Widget> _typingControls(bool busy) => [
    TextField(
      controller: _text,
      enabled: !busy,
      style: LtText.body(size: 20),
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _send(),
      minLines: 1,
      maxLines: 3,
      decoration: const InputDecoration(labelText: 'Type your answer', contentPadding: EdgeInsets.all(18)),
    ),
    const SizedBox(height: 14),
    BigButton(label: busy ? 'One moment…' : 'Send', filled: true, onTap: busy ? null : _send),
    if (MediaQuery.viewInsetsOf(context).bottom > 0) ...[
      const SizedBox(height: 12),
      BigButton(label: 'Hide keyboard', filled: false, onTap: () => FocusManager.instance.primaryFocus?.unfocus()),
    ],
  ];

  Widget _hearAgain() => Center(child: LinkButton(label: 'Hear it again', icon: Icons.volume_up_rounded, onTap: c.hearAgain));

  Widget _modeSwitch() {
    if (c.typing) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: BigButton(label: 'Talk instead', filled: false, icon: Icons.mic_none_rounded, onTap: () => c.setTyping(false)),
      );
    }
    return Center(child: LinkButton(label: 'Type instead', icon: Icons.keyboard_outlined, onTap: () => c.setTyping(true)));
  }
}

/// Progress: done steps solid, the current one a wide mint pill, the rest
/// outlined. Stays put until the answer is confirmed.
class ProgressDots extends StatelessWidget {
  const ProgressDots({super.key, required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final step = (done + 1).clamp(1, total);
    return Semantics(
      label: done >= total ? 'All $total steps done' : 'Step $step of $total',
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < total; i++)
            Container(
              width: i == done ? 30 : 12,
              height: 12,
              decoration: BoxDecoration(
                color: i < done ? LtColors.ink : (i == done ? LtColors.mint : LtColors.paper),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: i < done ? LtColors.ink : (i == done ? LtColors.controlOnMint : LtColors.control),
                  width: LtBorders.control,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The read-back value, big, so people can confirm by eye (V-3).
class _ValueCard extends StatelessWidget {
  const _ValueCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Your answer: $text',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: LtColors.mintWash,
          borderRadius: BorderRadius.circular(LtRadii.tile),
          border: Border.all(color: LtColors.controlOnMint, width: LtBorders.control),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 32, color: LtColors.ink),
            const SizedBox(width: 12),
            Flexible(
              child: Text(text, textAlign: TextAlign.center, style: LtText.display(text.length <= 12 ? 40 : 30)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hold to talk (88pt). Tap once to start and again to stop, for people who can't hold.
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
        child: LipSurface(
          kind: listening ? LipKind.active : LipKind.primary,
          minHeight: 88,
          lip: 5,
          pressed: listening,
          enabled: !busy,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(listening ? Icons.mic_rounded : Icons.mic_none_rounded, size: 34, color: LtColors.ink),
              const SizedBox(width: 12),
              Flexible(
                child: Text(label, textAlign: TextAlign.center, style: LtText.display(listening ? 22 : 26)),
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
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LtColors.cream,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: LtColors.container, width: LtBorders.container),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: LtText.body(size: 18)),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              BigButton(label: 'Try again', filled: false, height: 60, onTap: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-width lip button, at least 72pt tall by default.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.filled,
    this.height = 72,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final double height;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => LipButton(
    label: label,
    onTap: onTap,
    kind: filled ? LipKind.primary : LipKind.secondary,
    height: height,
    icon: icon,
    fontSize: height >= 72 ? 24 : 22,
  );
}
