import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../forecast/profile_labels.dart';
import '../health/readback.dart' show usesImperial;
import '../ui/swoosh_route.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart';
import '../voice/speech.dart';
import '../widgets/whole_word_text.dart';
import 'voice_onboarding_controller.dart';

/// Fields whose answer is a number: the keyboard opens on the number pad.
const numberFields = {'age', 'weight_kg', 'sleep_hours', 'exercise_minutes_weekly', 'alcohol_drinks_weekly'};

/// Opens this app's page in the iPhone Settings app (to turn the microphone on).
Future<void> openAppSettings() async {
  try {
    await launchUrl(Uri.parse('app-settings:'));
  } catch (_) {}
}

/// Text is enlarged enough that the layout changes: the window shrinks, the
/// bubble moves under it and buttons stack.
bool largeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(1) > 1.3;

/// The screen's side gutter.
const double _gutter = 16;

Widget _pad(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: _gutter),
  child: child,
);

/// Mascot conversation by voice or typing (V-2 / V-3). One action per screen,
/// large type, captions always on, nothing disappears by itself. The twin
/// stands in the window; its words are in the bubble; the controls sit on
/// the sheet at the bottom, always in reach.
class VoiceOnboardingScreen extends StatefulWidget {
  const VoiceOnboardingScreen({
    super.key,
    required this.controller,
    required this.onDone,
    this.onUseHealth,
    this.onOpenSettings = openAppSettings,
    this.appearance = const TwinAppearance(),
  });

  final VoiceOnboardingController controller;

  /// Called with the confirmed profile when the conversation is finished.
  final void Function(Map<String, dynamic> confirmedProfile) onDone;

  /// Opens the Apple Health import. The chip is hidden when null.
  final VoidCallback? onUseHealth;

  /// Opens the phone's Settings app after the microphone was not allowed.
  final Future<void> Function() onOpenSettings;

  /// Cosmetic look of the twin in the window.
  final TwinAppearance appearance;

  @override
  State<VoiceOnboardingScreen> createState() => _VoiceOnboardingScreenState();
}

class _VoiceOnboardingScreenState extends State<VoiceOnboardingScreen> with WidgetsBindingObserver {
  final _text = TextEditingController();

  /// Owned here, not by the TextField, so the typing box keeps focus (and the
  /// keyboard stays up) whatever else on the screen changes.
  final _focus = FocusNode(debugLabel: 'answer');

  /// The voice answer from the first consent question, kept until the second is answered.
  bool? _voiceChoice;

  /// Briefly true after the AI-helper question replaced the voice one. Its buttons sit
  /// where the voice buttons were, so a double tap (or a tremor) must not answer it
  /// unseen, least of all agree to the helper. As on the Health screen.
  static const secondTapGuard = Duration(milliseconds: 700);
  Timer? _aiLock;

  void _chooseVoice(bool voice) {
    _aiLock?.cancel();
    _aiLock = Timer(secondTapGuard, () {});
    setState(() => _voiceChoice = voice);
  }

  void _answerAi(bool voice, {bool aiHelper = false}) {
    if (_aiLock?.isActive ?? false) return;
    c.answerConsent(voice, aiHelper: aiHelper);
  }

  /// The same after each new question for the controls that stay in place from one
  /// question to the next: a double tap on "Skip this question" or "Go back" must not
  /// also skip (or reopen) the next one unseen, and the first question's Health chip
  /// must not open the Health import.
  Timer? _turnLock;
  late GuideTurn? _shownTurn = c.turn;

  bool get _justChanged => _turnLock?.isActive ?? false;

  final _noticeKey = GlobalKey(debugLabel: 'notice');
  final _quickKey = GlobalKey(debugLabel: 'quick answers');
  final _lineKey = GlobalKey(debugLabel: "the twin's line");

  /// The controls scroll when the text is very large; each new turn starts at the top, so
  /// its first button (Yes, the quick answers) is not left scrolled out of sight.
  final _controlsScroll = ScrollController();
  String? _shownNotice;

  void _useHealth() {
    if (!_justChanged) widget.onUseHealth?.call();
  }

  /// Back to the Room, as the swipe-back does: the route is popped, the controller (and
  /// every confirmed answer) stays with the app. The guard keeps a double tap from also
  /// popping the Room's own route.
  Timer? _leaveLock;

  void _home() {
    if (_leaveLock?.isActive ?? false) return;
    _leaveLock = Timer(secondTapGuard, () {});
    Navigator.of(context).maybePop();
  }

  /// However the screen is left (Home, swipe-back), the microphone closes and speech stops.
  void _left(bool didPop, Object? result) {
    if (!didPop) return;
    c.cancelTalk();
    c.stopSpeaking();
  }

  void _skip() {
    if (!_justChanged) c.skip();
  }

  void _goBack() {
    if (!_justChanged) c.goBack();
  }

  bool _wasListening = false;

  VoiceOnboardingController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  /// The keyboard going up or down (or a rotation) resizes the story: once it settles,
  /// the end of the twin's line is brought back into view.
  Timer? _resized;

  @override
  void didChangeMetrics() {
    _resized?.cancel();
    _resized = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _reveal(_lineKey);
    });
  }

  /// Leaving LifeTwin (home screen, another app, a call) closes the microphone and stops
  /// speech: nothing is heard or said while the app is not on screen, and words heard so
  /// far are dropped, not sent. Coming back shows the same question, ready to answer.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Every way out passes through hidden (before paused), so this runs once.
    if (state == AppLifecycleState.hidden) {
      c.cancelTalk();
      c.stopSpeaking();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _aiLock?.cancel();
    _turnLock?.cancel();
    _leaveLock?.cancel();
    _resized?.cancel();
    _controlsScroll.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A short buzz when the microphone opens or closes, however it happened.
  void _changed() {
    final listening = c.phase == VoicePhase.listening;
    if (listening != _wasListening) HapticFeedback.mediumImpact();
    _wasListening = listening;
    // With large text the story above the controls is short. A new turn scrolls the end
    // of the twin's line (the question or "Is that right?") into view; then, when there
    // is room, the quick answers under it. A new notice scrolls into view with its button.
    if (!identical(c.turn, _shownTurn)) {
      _shownTurn = c.turn;
      _turnLock?.cancel();
      _turnLock = Timer(secondTapGuard, () {});
      _reveal(_lineKey);
      if (_quickInStory && !largeText(context)) _reveal(_quickKey);
      if (_controlsScroll.hasClients) _controlsScroll.jumpTo(0);
    }
    if (c.notice != null && c.notice != _shownNotice) _reveal(_noticeKey);
    _shownNotice = c.notice;
  }

  void _reveal(GlobalKey key) => WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = key.currentContext;
    if (target == null || !target.mounted) return;
    Scrollable.ensureVisible(
      target,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      duration: MediaQuery.disableAnimationsOf(target) ? Duration.zero : const Duration(milliseconds: 250),
    );
  });

  void _send() {
    final t = _text.text;
    if (t.trim().isEmpty || c.phase == VoicePhase.interpreting) return;
    _text.clear();
    c.submitTyped(t);
  }

  TwinMood get _mood {
    if (c.phase == VoicePhase.listening) return TwinMood.listening;
    if (c.phase == VoicePhase.done || (c.confirming && !c.correcting) || c.mascotLine.startsWith('Got it')) {
      return TwinMood.pleased;
    }
    return TwinMood.asking;
  }

  bool get _keyboard => MediaQuery.viewInsetsOf(context).bottom > 0;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: _left,
      child: SwooshStage(
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
                    // Not a control for VoiceOver (it would be an unnamed, screen-sized button);
                    // "Hide keyboard" does the same for everyone.
                    excludeFromSemantics: true,
                    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                    child: ListenableBuilder(
                      listenable: c,
                      builder: (context, _) => c.askingVoice
                          ? _voiceAgain(frame, window)
                          : c.phase == VoicePhase.consent && c.turn == null && !c.canRetry
                          ? _consent(frame, window)
                          : _talk(frame, window),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The painted window: the twin on the room plate, Home in the corner and, when
  /// [bubble] is set, the twin's words beside it.
  Widget _window(SwooshFrame frame, double opacity, {required bool compact, Widget? bubble}) {
    final mood = _mood;
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        height: compact ? 150 : 250,
        child: PlateWindow(
          name: widget.appearance.name,
          showBanner: !compact,
          plate: PlateScene(
            asset: ScenePlate.room.asset,
            focus: const Offset(0.5, 0.554),
            focusTarget: Offset(compact ? 0.5 : 0.28, 0.86),
            zoom: 1.38,
            twinBuilder: (feet, scale, box) => plantTwin(
              feet,
              TwinSprite(
                appearance: widget.appearance,
                pose: mood.pose,
                height: (185 * scale).clamp(60.0, box.height * 0.82 < 60 ? 60.0 : box.height * 0.82),
                hero: true,
                isRoom: false,
              ),
            ),
          ),
          overlay: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                if (bubble != null)
                  Positioned(
                    top: 26,
                    right: 8,
                    width: box.maxWidth * 0.6,
                    child: Opacity(
                      opacity: frame.bubbleOpacity.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: frame.bubbleScale,
                        alignment: Alignment.centerLeft,
                        child: Align(alignment: Alignment.topLeft, child: bubble),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The twin's words. Short ones sit in the window beside the twin; long ones, large
  /// text and a crowded screen put them under the window at full width.
  Widget _bubble(String line, {required bool inWindow, bool header = false}) {
    final long = line.length > 80;
    return Semantics(
      key: _lineKey,
      liveRegion: !header,
      container: true,
      child: Bubble(
        text: line,
        tail: inWindow ? BubbleTail.left : BubbleTail.none,
        tailAt: 0.3,
        header: header,
        fontSize: long ? 20 : (inWindow && line.length > 24 ? 22 : 26),
      ),
    );
  }

  /// The shared page: the story (window, words, notices) scrolls; the sheet with the
  /// controls stays at the bottom. "Hide keyboard" sits outside the sheet's scroll
  /// area so it can never be clipped.
  Widget _page({
    required SwooshFrame frame,
    required double windowOpacity,
    required String line,
    required List<Widget> story,
    required List<Widget> controls,
    List<Widget> top = const [],
    Widget? trailing,
    bool header = false,
    bool crowded = false,
    bool hideKeyboard = false,
  }) {
    final keyboard = _keyboard;
    final compact = largeText(context) || crowded;
    final inWindow = line.isNotEmpty && !compact && line.length <= 70;
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Home always in the same place, clearly named; hidden only while the keyboard is up.
          if (!keyboard)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
              child: Row(
                children: [
                  Opacity(
                    opacity: frame.backOpacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: frame.backScale,
                      child: RoundBackButton(label: 'Home', icon: Icons.home_rounded, onTap: _home),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(alignment: Alignment.centerRight, child: trailing ?? const SizedBox.shrink()),
                  ),
                ],
              ),
            ),
          Expanded(
            // Keyed, like the sheet: the rows around them come and go with the keyboard, and
            // the typing box inside must keep its state (and focus) when they do.
            key: const ValueKey('story'),
            child: _StoryScroll(
              children: [
                // With the keyboard up the room goes to the question and the typing box.
                if (!keyboard)
                  _pad(
                    _window(
                      frame,
                      windowOpacity,
                      compact: compact,
                      bubble: inWindow ? _bubble(line, inWindow: true, header: header) : null,
                    ),
                  ),
                if (!keyboard) const SizedBox(height: 10),
                ...top,
                if (line.isNotEmpty && !inWindow) ...[_pad(_bubble(line, inWindow: false, header: header))],
                ...story,
              ],
            ),
          ),
          ConstrainedBox(
            key: const ValueKey('sheet'),
            constraints: BoxConstraints(maxHeight: box.maxHeight * (hideKeyboard ? 0.5 : 0.6)),
            child: SwooshSheetTransform(
              frame: frame,
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, 0, 10, hideKeyboard ? 6 : 10),
                child: Sheet(
                  padding: EdgeInsets.zero,
                  child: SingleChildScrollView(
                    controller: _controlsScroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: controls),
                  ),
                ),
              ),
            ),
          ),
          if (hideKeyboard)
            Padding(
              padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, 12),
              child: LipButton(
                label: 'Hide keyboard',
                icon: Icons.keyboard_hide_rounded,
                kind: LipKind.secondary,
                height: 72,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              ),
            ),
        ],
      ),
    );
  }

  static const _voiceCopy =
      'You can talk to me, or type. While you talk, your voice is sent to Cartesia, '
      'a speech service, to turn it into words.';

  /// A consent question: the question in the bubble, the plain facts under it, two
  /// big buttons on the sheet.
  Widget _question(
    SwooshFrame frame,
    double windowOpacity, {
    required String title,
    required String body,
    required List<Widget> buttons,
  }) => _page(
    frame: frame,
    windowOpacity: windowOpacity,
    line: title,
    header: true,
    story: [
      const SizedBox(height: 4),
      _pad(_Card(child: Text(body, style: LtText.body(size: 19)))),
      const SizedBox(height: 12),
    ],
    controls: buttons,
  );

  Widget _consent(SwooshFrame frame, double w) {
    final voice = _voiceChoice;
    if (voice != null) return _aiConsent(frame, w, voice);
    return _question(
      frame,
      w,
      title: 'Talk with me?',
      body: _voiceCopy,
      buttons: [
        LipButton(label: "Yes, I'll talk", icon: Icons.mic_none_rounded, height: 72, onTap: () => _chooseVoice(true)),
        const SizedBox(height: 14),
        LipButton(
          label: "No, I'll type",
          icon: Icons.keyboard_outlined,
          kind: LipKind.secondary,
          height: 72,
          onTap: () => _chooseVoice(false),
        ),
      ],
    );
  }

  /// Same question as the first screen, asked when someone who started by
  /// typing wants to talk.
  Widget _voiceAgain(SwooshFrame frame, double w) => _question(
    frame,
    w,
    title: 'Talk with me?',
    body: _voiceCopy,
    buttons: [
      LipButton(
        label: "Yes, I'll talk",
        icon: Icons.mic_none_rounded,
        height: 72,
        onTap: () => c.answerVoiceAgain(true),
      ),
      const SizedBox(height: 14),
      LipButton(
        label: 'Keep typing',
        icon: Icons.keyboard_outlined,
        kind: LipKind.secondary,
        height: 72,
        onTap: () => c.answerVoiceAgain(false),
      ),
    ],
  );

  /// Second question: may an AI helper read the answers? "Not now" works
  /// fully, and it can be turned on later.
  Widget _aiConsent(SwooshFrame frame, double w, bool voice) => _question(
    frame,
    w,
    title: 'Let an AI helper read hard answers?',
    body:
        "If I can't understand an answer, an AI service can read your words. "
        "It's off unless you say yes. You can change this in Settings.",
    buttons: [
      LipButton(
        label: 'Yes, turn it on',
        icon: Icons.check_rounded,
        height: 72,
        onTap: () => _answerAi(voice, aiHelper: true),
      ),
      const SizedBox(height: 14),
      LipButton(label: 'Not now', kind: LipKind.secondary, height: 72, onTap: () => _answerAi(voice)),
    ],
  );

  /// The value being read back, big, so it can be checked by eye (V-3).
  String get _readBackValue {
    final pending = Map<String, dynamic>.from((c.state?['pending_profile'] as Map?) ?? const {});
    final imperial = usesImperial(WidgetsBinding.instance.platformDispatcher.locale.countryCode);
    return [for (final (_, l) in profileLabels(pending, imperial: imperial)) l].join(' · ');
  }

  /// Typing: quick answers stay under the question. By voice they join the controls.
  bool get _quickInStory => c.typing && !c.confirming && c.phase != VoicePhase.done && c.quickAnswers.isNotEmpty;

  bool get _showsTypingBox => c.typing && c.phase != VoicePhase.done && (!c.confirming || c.correcting);

  Widget _talk(SwooshFrame frame, double windowOpacity) {
    final keyboard = _keyboard;
    final busy = c.phase == VoicePhase.interpreting;
    final line = c.mascotLine.isEmpty ? (busy ? 'One moment…' : '') : c.mascotLine;
    final listening = c.phase == VoicePhase.listening;
    final n = c.questionNumber;
    final quick = _quickInStory;
    // The read-back, a notice, the quick answers or the live caption need the room:
    // the window then shrinks so the words and buttons keep it.
    final readBack = c.confirming && !c.correcting && c.caption.isNotEmpty;
    final crowded = readBack || c.notice != null || quick || (listening && c.caption.isNotEmpty);
    final links = c.phase != VoicePhase.done && !keyboard;
    final voiceLine = c.phase == VoicePhase.speaking
        ? _speaking()
        : c.canHearAgain && !listening
        ? LinkButton(label: 'Hear it again', icon: Icons.volume_up_rounded, onTap: c.hearAgain)
        : null;
    final goBack = !keyboard && c.canGoBack;
    return _page(
      frame: frame,
      windowOpacity: windowOpacity,
      line: line,
      crowded: crowded,
      hideKeyboard: keyboard && _showsTypingBox,
      trailing: links ? LinkButton(label: 'Settings', icon: Icons.settings_outlined, onTap: _openSettings) : null,
      top: [
        // "Go back" (also once done, so an answer can still be changed or a skipped one
        // added), then the progress.
        if (goBack)
          _pad(
            Align(
              alignment: Alignment.centerLeft,
              child: LinkButton(label: 'Go back', icon: Icons.undo_rounded, onTap: _goBack),
            ),
          ),
        if (n != null && !keyboard) ...[
          _pad(StepProgress(step: n, total: VoiceOnboardingController.questionCount)),
          const SizedBox(height: 12),
        ],
      ],
      story: [
        if (c.confirming && !c.correcting && _readBackValue.isNotEmpty) ...[
          const SizedBox(height: 10),
          _pad(_ValueCard(text: _readBackValue)),
        ],
        if (voiceLine != null) ...[
          const SizedBox(height: 4),
          _pad(Align(alignment: Alignment.centerLeft, child: voiceLine)),
        ],
        if (c.caption.isNotEmpty && !keyboard) ...[
          const SizedBox(height: 8),
          _pad(listening ? _hearing() : _youSaid()),
        ],
        if (c.notice != null) ...[
          const SizedBox(height: 14),
          _pad(
            _NoticeBox(
              key: _noticeKey,
              message: c.notice!,
              onRetry: c.canRetry ? c.retry : null,
              onOpenSettings: c.notice == micDeniedNotice ? widget.onOpenSettings : null,
            ),
          ),
        ],
        if (quick) ...[const SizedBox(height: 14), KeyedSubtree(key: _quickKey, child: _pad(_quickAnswers(busy)))],
        const SizedBox(height: 8),
      ],
      controls: _controls(keyboard),
    );
  }

  Widget _speaking() => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    children: [
      WholeWordText('Speaking…', style: LtText.body(size: 18, weight: FontWeight.w700)),
      LinkButton(label: 'Stop', icon: Icons.stop_circle_outlined, onTap: c.stopSpeaking),
    ],
  );

  /// The live caption, large, in its own card.
  Widget _hearing() => Semantics(
    liveRegion: true,
    container: true,
    child: _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: WholeWordText('Hearing:', style: LtText.body(size: 18, weight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              const ExcludeSemantics(child: _SoundBars()),
            ],
          ),
          const SizedBox(height: 8),
          Text(c.caption, style: LtText.display(32)),
        ],
      ),
    ),
  );

  Widget _youSaid() => Semantics(liveRegion: true, child: Text('You said: ${c.caption}', style: LtText.body(size: 19)));

  List<Widget> _controls(bool keyboard) {
    final busy = c.phase == VoicePhase.interpreting;
    if (c.phase == VoicePhase.done) {
      return [
        LipButton(label: 'Continue', height: 72, onTap: () => widget.onDone(c.confirmedProfile)),
        if (widget.onUseHealth != null) ...[const SizedBox(height: 14), _healthChip()],
      ];
    }
    if (c.confirming && c.correcting) {
      return [
        WholeWordText('Okay. What is the right answer?', style: LtText.body(size: 20, weight: FontWeight.w700)),
        const SizedBox(height: 14),
        ..._answerControls(busy, keyboard),
        if (!busy && !keyboard) ...[
          const SizedBox(height: 12),
          LipButton(label: 'Never mind', kind: LipKind.secondary, height: 72, onTap: c.keepAnswer),
        ],
        if (!keyboard) _switchMode(),
      ];
    }
    if (c.confirming) {
      return [
        LipButton(label: 'Yes', icon: Icons.check_rounded, height: 72, onTap: busy ? null : c.confirm),
        const SizedBox(height: 12),
        LipButton(
          label: 'No, change it',
          icon: Icons.edit_rounded,
          kind: LipKind.secondary,
          height: 72,
          onTap: busy ? null : c.change,
        ),
        // By voice, the person can also just say yes, no, or the right answer.
        if (!c.typing) ...[const SizedBox(height: 4), TalkButton(controller: c, compact: true)],
        _switchMode(),
      ];
    }
    final quick = !c.typing && c.quickAnswers.isNotEmpty;
    return [
      // The offer after an answer the server could not read, first so it is seen.
      if (c.helperWouldHelp && !busy) ...[
        LipButton(
          label: 'Yes, let the AI helper read it',
          kind: LipKind.secondary,
          height: 72,
          onTap: () => c.setAiHelper(true),
        ),
        const SizedBox(height: 12),
      ],
      if (quick) ...[_quickAnswers(busy), const SizedBox(height: 8)],
      // With quick answers on screen they are the big choices; Talk is the smaller one.
      if (quick) TalkButton(controller: c, compact: true) else ..._answerControls(busy, keyboard),
      if (!keyboard) _switchMode(),
      LinkButton(label: 'Skip this question', onTap: busy ? null : _skip),
      if (!keyboard) ..._chips(),
    ];
  }

  /// V-2's chips: the Health app (first question only) and the AI helper switch.
  List<Widget> _chips() => [
    if (widget.onUseHealth != null && c.questionNumber == 1 && c.phase != VoicePhase.listening) ...[
      const SizedBox(height: 8),
      _healthChip(),
    ],
    const SizedBox(height: 10),
    LtToggleChip(
      label: c.aiHelper ? 'AI helper: On' : 'AI helper: Off',
      semanticLabel: 'AI helper',
      icon: Icons.auto_awesome_outlined,
      value: c.aiHelper,
      onChanged: (on) => c.setAiHelper(on),
    ),
  ];

  Widget _healthChip() => LtChip(
    label: 'Use my Health app',
    icon: Icons.favorite_border_rounded,
    trailing: const Icon(Icons.chevron_right_rounded, color: LtColors.ink),
    onTap: _useHealth,
  );

  /// The typing box and Send, or the Talk button.
  List<Widget> _answerControls(bool busy, bool keyboard) {
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
        style: LtText.body(size: 22),
        cursorColor: LtColors.ink,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _send(),
        minLines: 1,
        maxLines: 3,
        // With large text a one-line floating label would be cut off; a hint can wrap.
        decoration: InputDecoration(
          labelText: largeText(context) ? null : 'Type your answer',
          hintText: largeText(context) ? 'Type your answer' : null,
          hintMaxLines: 3,
          labelStyle: LtText.body(size: 18),
          contentPadding: const EdgeInsets.all(18),
        ),
      ),
      const SizedBox(height: 12),
      LipButton(
        key: const ValueKey('send'),
        label: busy ? 'One moment…' : 'Send',
        icon: busy ? null : Icons.send_rounded,
        height: 72,
        onTap: busy ? null : _send,
      ),
    ];
  }

  /// "Type instead" (V-2) or "Talk instead": the same underlined link either way.
  Widget _switchMode() => Center(
    child: LinkButton(
      label: c.typing ? 'Talk instead' : 'Type instead',
      icon: c.typing ? Icons.mic_none_rounded : Icons.keyboard_outlined,
      onTap: () => c.setTyping(!c.typing),
    ),
  );

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: LtColors.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(LtRadii.panel))),
      builder: (sheet) => SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (sheet, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(header: true, child: WholeWordText('Settings', style: LtText.display(30))),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: LtColors.mint,
                    activeThumbColor: LtColors.ink,
                    title: WholeWordText('AI helper', style: LtText.body(size: 20, weight: FontWeight.w700)),
                    subtitle: Text('Reads answers I can’t understand', style: LtText.body()),
                    value: c.aiHelper,
                    onChanged: (on) => c.setAiHelper(on),
                  ),
                  const SizedBox(height: 16),
                  WholeWordText('Answer by', style: LtText.body(size: 20, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(Size(0, 56)),
                      textStyle: WidgetStatePropertyAll(LtText.body(size: 18, weight: FontWeight.w700)),
                      foregroundColor: const WidgetStatePropertyAll(LtColors.ink),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (s) => s.contains(WidgetState.selected) ? LtColors.mint : LtColors.paper,
                      ),
                      side: const WidgetStatePropertyAll(BorderSide(color: LtColors.control, width: LtBorders.control)),
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
                  const SizedBox(height: 28),
                  LipButton(label: 'Done', height: 72, onTap: () => Navigator.of(sheet).pop()),
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
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 12.0;
        final perRow = largeText(context) ? 1 : 2;
        final w = (box.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, say) in answers)
              SizedBox(
                width: w,
                child: LipButton(
                  label: label,
                  kind: LipKind.secondary,
                  height: 72,
                  onTap: busy ? null : () => c.submitQuick(say),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A scrolling column whose content starts at the top.
class _StoryScroll extends StatelessWidget {
  const _StoryScroll({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

/// A paper card for plain words under the window.
class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
    decoration: BoxDecoration(
      color: LtColors.paper,
      borderRadius: BorderRadius.circular(LtRadii.tile),
      border: Border.all(color: LtColors.container, width: LtBorders.container),
    ),
    child: child,
  );
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
        constraints: const BoxConstraints(minHeight: 80),
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
              child: WholeWordText(
                text,
                textAlign: TextAlign.center,
                style: LtText.display(text.length <= 12 ? 36 : 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
/// [compact] is the read-back's smaller Talk, under Yes and "No, change it", so Yes
/// stays the one big mint button.
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

    Widget lay(Widget icon, Widget text) => big
        ? Column(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(height: 6), text])
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 16),
              Flexible(child: text),
            ],
          );

    final Widget face;
    if (listening) {
      final dot = MediaQuery.disableAnimationsOf(context) ? const RecordingDot() : const _Pulse(child: RecordingDot());
      face = LipSurface(
        kind: LipKind.active,
        minHeight: widget.compact ? 72 : 88,
        lip: 5,
        pressed: true,
        radius: 30,
        child: lay(
          dot,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: big ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              WholeWordText('Listening…', style: LtText.display(26)),
              WholeWordText(
                'tap when done${left == null ? '' : ' ($left s left)'}',
                textAlign: big ? TextAlign.center : TextAlign.start,
                style: LtText.body(size: 18, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    } else if (widget.compact) {
      // Read-back and quick answers: an underlined "Tap to talk", at least 56 pt tall.
      final ink = busy ? LtColors.control : LtColors.ink;
      face = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56, minWidth: double.infinity),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic_none_rounded, size: 26, color: ink),
              const SizedBox(width: 8),
              Flexible(
                child: WholeWordText(
                  label,
                  textAlign: TextAlign.center,
                  style: LtText.body(
                    size: 18,
                    weight: FontWeight.w700,
                    color: ink,
                  ).copyWith(decoration: TextDecoration.underline, decorationThickness: 2, decorationColor: ink),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // V-2: the 88 pt mint button, the mic in a paper circle beside the words.
      final mic = Opacity(
        opacity: busy ? .5 : 1,
        child: Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LtColors.paper,
            shape: BoxShape.circle,
            border: Border.all(color: LtColors.controlOnMint, width: LtBorders.control),
          ),
          child: const Icon(Icons.mic_none_rounded, size: 32, color: LtColors.ink),
        ),
      );
      face = LipSurface(
        kind: LipKind.primary,
        minHeight: 88,
        lip: 5,
        radius: 30,
        enabled: !busy,
        child: lay(mic, WholeWordText(label, textAlign: TextAlign.center, style: LtText.display(26))),
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

/// The red "recording" dot shown while the microphone is open.
class RecordingDot extends StatelessWidget {
  const RecordingDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    margin: const EdgeInsets.all(8), // room for the halo
    decoration: const BoxDecoration(
      color: Color(0xFFD7402B),
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
  const _NoticeBox({super.key, required this.message, this.onRetry, this.onOpenSettings});
  final String message;
  final VoidCallback? onRetry;
  final Future<void> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: LtColors.cream,
          borderRadius: BorderRadius.circular(LtRadii.tile),
          border: Border.all(color: LtColors.control, width: LtBorders.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: LtText.body(size: 19, weight: FontWeight.w700)),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              LipButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                kind: LipKind.secondary,
                height: 72,
                onTap: onRetry,
              ),
            ],
            if (onOpenSettings != null) ...[
              const SizedBox(height: 14),
              LipButton(label: 'Open Settings', kind: LipKind.secondary, height: 72, onTap: onOpenSettings),
            ],
          ],
        ),
      ),
    );
  }
}
