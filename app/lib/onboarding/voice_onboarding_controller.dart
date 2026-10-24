import 'dart:async';

import 'package:flutter/foundation.dart';

import '../voice/speech.dart';

enum VoicePhase {
  /// Asking permission to use voice. Nothing is sent yet.
  consent,

  /// Mascot is talking (or about to).
  speaking,

  /// Waiting for the person.
  idle,

  /// Microphone is open.
  listening,

  /// Waiting for the server.
  interpreting,

  /// The conversation is finished.
  done,
}

const emptyTranscriptNotice = "I didn't catch that. Please try again, or type it.";
const micDeniedNotice = "I can't use the microphone, so please type your answers instead. "
    'To turn it on, open Settings, then LifeTwin, then Microphone.';
const voiceOffNotice = 'Talking is not available right now, so please type your answers.';
const noNetworkNotice = "I can't reach LifeTwin right now. Your answers are kept. Please try again.";
const voiceTroubleNotice = "I couldn't use the voice just now. You can try again, or type your answer.";
const speakTroubleNotice = "I couldn't say that out loud. You can read my words above.";
const healthWaitNotice = 'Please answer Yes or Change first. Then you can add your Health app answers.';
const healthNoneNotice = "No Health app answers were added, so I'll keep asking you. That's okay.";
const healthRejectedPrefix = "I couldn't add your Health app answers. ";

/// Runs the conversation loop. The server decides what happens; this class only
/// holds the caller-owned state, moves audio in and out, and keeps answers safe
/// when voice fails.
class VoiceOnboardingController extends ChangeNotifier {
  VoiceOnboardingController({required this.guide, required this.input, required this.output});

  final ConversationGuide guide;
  final SpeechInput input;
  final SpeechOutput output;

  VoicePhase phase = VoicePhase.consent;

  /// True while the person answers by typing. Same conversation either way.
  bool typing = false;

  /// False after "No", or when the server or phone says voice cannot be used.
  bool voiceUsable = true;

  /// The person agreed that the server's AI helper may read their replies.
  /// Asked at the start; can be turned on or off at any time.
  bool aiHelper = false;

  String mascotLine = '';

  /// Live words while listening; the last thing heard afterwards.
  String caption = '';

  /// A message that stays until the next action. Never auto-dismissed.
  String? notice;

  GuideTurn? turn;
  bool _busy = false;
  int _speechGen = 0;
  Future<void>? _starting;
  Future<void> Function()? _retry;
  (String, bool)? _lastReply;
  bool _disposed = false;

  bool get confirming => turn?.isConfirming ?? false;

  /// The last answer could not be read because the AI helper was off.
  bool get helperWouldHelp => !aiHelper && turn?.providerStatus == 'consent_required';
  Map<String, dynamic>? get state => turn?.state;

  /// What the person has confirmed so far. Survives every voice failure.
  Map<String, dynamic> get confirmedProfile =>
      Map<String, dynamic>.from((turn?.state['confirmed_profile'] as Map?) ?? const {});

  bool get canRetry => _retry != null;
  bool get canHearAgain => voiceUsable && mascotLine.isNotEmpty && !typing && phase != VoicePhase.interpreting;

  void _set(void Function() change) {
    change();
    if (!_disposed) notifyListeners();
  }

  // ---- consent -----------------------------------------------------------

  Future<void> answerConsent(bool yes, {bool aiHelper = false}) async {
    if (phase != VoicePhase.consent || _busy) return;
    _set(() {
      voiceUsable = yes;
      typing = !yes;
      this.aiHelper = aiHelper;
    });
    await _send('start');
  }

  /// Turns the AI helper on or off. Turning it on right after an answer that
  /// needed it sends that same answer again, so the person doesn't repeat it.
  Future<void> setAiHelper(bool on) async {
    if (on == aiHelper || _busy) return;
    final resend = on && helperWouldHelp ? _lastReply : null;
    _set(() => aiHelper = on);
    if (resend != null) {
      await _stopSpeech();
      await _send('reply', text: resend.$1, fromTranscript: resend.$2);
    }
  }

  // ---- Apple Health --------------------------------------------------------

  /// Adds answers the person already checked on the Health screen. The server
  /// validates them and moves on to the next question that is still unanswered.
  Future<void> importHealth(Map<String, num> values) async {
    if (_busy || turn == null) return;
    if (values.isEmpty) {
      _set(() => notice = healthNoneNotice);
      return;
    }
    if (confirming) {
      _set(() => notice = healthWaitNotice);
      return;
    }
    await _stopSpeech();
    await _send('import', values: values);
  }

  // ---- talking -----------------------------------------------------------

  /// Opens the microphone. Pressing Talk while the mascot speaks stops the mascot first.
  Future<void> startTalk() {
    // Ignore a second press while we are already starting, listening or waiting.
    if (_starting != null) return _starting!;
    if (typing || !voiceUsable) return Future.value();
    if (phase != VoicePhase.idle && phase != VoicePhase.speaking) return Future.value();
    return _starting = _startTalk().whenComplete(() => _starting = null);
  }

  Future<void> _startTalk() async {
    if (phase == VoicePhase.speaking) {
      _speechGen++;
      await output.stop();
    }
    _set(() {
      phase = VoicePhase.listening;
      caption = '';
      notice = null;
      _retry = null;
    });
    try {
      await input.start((text) => _set(() => caption = text));
    } on MicDeniedException {
      _set(() {
        phase = VoicePhase.idle;
        typing = true;
        notice = micDeniedNotice;
      });
    } on VoiceUnavailableException {
      _set(() {
        phase = VoicePhase.idle;
        typing = true;
        voiceUsable = false;
        notice = voiceOffNotice;
      });
    } catch (_) {
      _set(() {
        phase = VoicePhase.idle;
        notice = voiceTroubleNotice;
      });
    }
  }

  /// Closes the microphone and sends what was heard.
  Future<void> stopTalk() async {
    await _starting;
    if (phase != VoicePhase.listening) return;
    _set(() => phase = VoicePhase.interpreting);
    String text;
    try {
      text = (await input.finish()).trim();
    } on VoiceUnavailableException {
      _set(() {
        phase = VoicePhase.idle;
        typing = true;
        voiceUsable = false;
        notice = voiceOffNotice;
      });
      return;
    } catch (_) {
      _set(() {
        phase = VoicePhase.idle;
        notice = voiceTroubleNotice;
      });
      return;
    }
    if (text.isEmpty) {
      _set(() {
        phase = VoicePhase.idle;
        caption = '';
        notice = emptyTranscriptNotice;
      });
      return;
    }
    _set(() => caption = text);
    await _send('reply', text: text, fromTranscript: true);
  }

  /// Closes the microphone and throws away what was heard.
  Future<void> cancelTalk() async {
    await _starting;
    if (phase != VoicePhase.listening) return;
    await input.cancel();
    _set(() {
      phase = VoicePhase.idle;
      caption = '';
    });
  }

  // ---- typing and buttons ---------------------------------------------------

  Future<void> submitTyped(String text) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    if (phase != VoicePhase.idle && phase != VoicePhase.speaking) return;
    await _stopSpeech();
    _set(() => caption = t);
    await _send('reply', text: t);
  }

  Future<void> confirm() => _button('confirm');
  Future<void> change() => _button('correct');
  Future<void> skip() => _button('skip');

  Future<void> _button(String action) async {
    if (_busy || (phase != VoicePhase.idle && phase != VoicePhase.speaking)) return;
    await _stopSpeech();
    await _send(action);
  }

  /// Repeats the request that failed.
  Future<void> retry() async {
    final r = _retry;
    if (r == null || _busy) return;
    await r();
  }

  Future<void> setTyping(bool value) async {
    if (value == typing) return;
    if (!value && !voiceUsable) return;
    if (value) {
      if (phase == VoicePhase.listening) await cancelTalk();
      await _stopSpeech();
    }
    _set(() => typing = value);
  }

  Future<void> hearAgain() async {
    if (!canHearAgain) return;
    if (phase == VoicePhase.listening) await cancelTalk();
    final line = mascotLine;
    await _speak(line, replay: output.canReplay);
  }

  // ---- server turn -----------------------------------------------------------

  Future<void> _send(String action, {String? text, bool fromTranscript = false, Map<String, num>? values}) async {
    if (_busy) return;
    _busy = true;
    if (action == 'reply' && text != null) _lastReply = (text, fromTranscript);
    _set(() {
      phase = VoicePhase.interpreting;
      notice = null;
      _retry = null;
    });
    final GuideTurn t;
    try {
      t = await guide.turn(
        action: action,
        state: turn?.state,
        text: text,
        fromTranscript: fromTranscript,
        values: values,
        aiHelper: aiHelper,
      );
    } on GuideRejected catch (e) {
      // The server explained what is wrong; show its words. Nothing was changed.
      _busy = false;
      _set(() {
        phase = turn?.complete == true ? VoicePhase.done : VoicePhase.idle;
        notice = action == 'import' ? '$healthRejectedPrefix${e.message}' : e.message;
      });
      return;
    } catch (_) {
      _busy = false;
      _set(() {
        phase = VoicePhase.idle;
        notice = noNetworkNotice;
        _retry = () => _send(action, text: text, fromTranscript: fromTranscript, values: values);
      });
      return;
    }
    _busy = false;
    _set(() {
      turn = t;
      mascotLine = t.message;
      phase = t.complete ? VoicePhase.done : VoicePhase.idle;
    });
    if (!typing && voiceUsable) await _speak(t.message);
  }

  // ---- speaking --------------------------------------------------------------

  Future<void> _stopSpeech() async {
    if (phase == VoicePhase.speaking) {
      _speechGen++;
      await output.stop();
      _set(() => phase = turn?.complete == true ? VoicePhase.done : VoicePhase.idle);
    }
  }

  Future<void> _speak(String line, {bool replay = false}) async {
    final gen = ++_speechGen;
    _set(() => phase = VoicePhase.speaking);
    try {
      await (replay ? output.replay() : output.speak(line));
    } on VoiceUnavailableException {
      if (gen == _speechGen) {
        _set(() {
          typing = true;
          voiceUsable = false;
          notice = voiceOffNotice;
        });
      }
    } catch (_) {
      if (gen == _speechGen) _set(() => notice = speakTroubleNotice);
    }
    if (gen == _speechGen && phase == VoicePhase.speaking) {
      _set(() => phase = turn?.complete == true ? VoicePhase.done : VoicePhase.idle);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    input.dispose();
    output.dispose();
    super.dispose();
  }
}
