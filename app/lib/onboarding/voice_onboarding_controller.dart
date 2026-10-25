import 'dart:async';

import 'package:flutter/foundation.dart';

import '../voice/speech.dart';
import '../voice/spoken_text.dart';

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

const emptyTranscriptNotice = "I didn't hear anything. Tap Talk and try again, or type.";
const micDeniedNotice =
    "I can't use the microphone, so please type your answers instead. "
    'To turn it on, open Settings, then LifeTwin, then Microphone.';
const voiceOffNotice = 'Talking is not available right now, so please type your answers.';
const noNetworkNotice = "I can't reach LifeTwin right now. Your answers are kept. Please try again.";
const voiceTroubleNotice = "I couldn't use the voice just now. You can try again, or type your answer.";
const speakTroubleNotice = "I couldn't say that out loud. You can read my words above.";
const healthWaitNotice = 'Please answer Yes or No first. Then you can add your Apple Health answers.';
const healthNoneNotice = "No Apple Health answers were added, so I'll keep asking you. That's okay.";
const documentWaitNotice = 'Please answer Yes or No first. Then you can add the answers from your document.';
const documentNoneNotice = "No answers from your document were added, so I'll keep asking you. That's okay.";
const healthRejectedPrefix = "I couldn't add your Apple Health answers. ";

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

  /// "Change" was pressed: the next answer replaces the one being checked.
  /// The server needs the new answer along with the correction, so Change by
  /// itself sends nothing.
  bool correcting = false;

  /// Shown when the person asks to talk but never agreed to send their voice.
  bool askingVoice = false;

  /// A screen reader (VoiceOver) is on. It already reads the mascot's words
  /// aloud, so the mascot does not speak them a second time. Set by the screen.
  bool screenReader = false;

  /// The fields the intake asks about, in the server's order (its ASKED list). Blood pressure
  /// comes from Apple Health or a reading, not from a question.
  static const askedFields = [
    'age',
    'sex',
    'smoking_status',
    'height_cm',
    'weight_kg',
    'sleep_hours',
    'general_health',
    'hypertension_diagnosed',
    'diabetes',
    'sedentary_min_day',
    'moderate_recreation_min_week',
    'vigorous_recreation_min_week',
  ];

  /// How many questions the intake has (one per asked field).
  static int get questionCount => askedFields.length;

  /// The microphone closes by itself after this long with no new words, or
  /// after [listenLimit] in all, so it is never left open by mistake.
  static const silenceLimit = Duration(seconds: 8);
  static const listenLimit = Duration(seconds: 30);
  Timer? _listenClock;
  int _listenedSeconds = 0;
  int _silentSeconds = 0;

  /// Nothing the microphone, the speaker or the network does may keep the
  /// screen waiting for ever: every wait ends, and the person can carry on.
  static const _micStartLimit = Duration(seconds: 10);
  static const _micFinishLimit = Duration(seconds: 20);
  static const _quickLimit = Duration(seconds: 4);
  static const _speakLimit = Duration(seconds: 60);
  static const _turnLimit = Duration(seconds: 30);
  int _speechGen = 0;
  Future<void>? _starting;
  Future<void> Function()? _retry;
  (String, bool)? _lastReply;
  bool _disposed = false;

  /// The last thing spoken was the mascot line (not a notice), so it can be replayed.
  bool _spokeMascotLine = false;

  bool get confirming => turn?.isConfirming ?? false;

  /// The last answer could not be read because the AI helper was off.
  bool get helperWouldHelp => !aiHelper && turn?.providerStatus == 'consent_required';
  Map<String, dynamic>? get state => turn?.state;

  /// What the person has confirmed so far. Survives every voice failure.
  Map<String, dynamic> get confirmedProfile =>
      Map<String, dynamic>.from((turn?.state['confirmed_profile'] as Map?) ?? const {});

  /// Mochi is offering Apple Health (after age, sex and smoking), or the person said yes
  /// and the server asked the app to open the import: show the Apple Health button.
  bool get healthOffer => turn?.clientAction == 'open_health_import' || turn?.phase == 'offering';

  /// The latest turn's `model_inputs` (see GuideTurn.modelInputs).
  Map<String, dynamic>? get modelInputs => turn?.modelInputs;

  bool get canRetry => _retry != null;
  bool get canHearAgain => voiceUsable && mascotLine.isNotEmpty && !typing && phase != VoicePhase.interpreting;

  /// Seconds until the microphone closes by itself, shown only near the end.
  int? get listenSecondsLeft {
    if (phase != VoicePhase.listening || _listenClock == null) return null;
    final left = listenLimit.inSeconds - _listenedSeconds;
    return left <= 10 ? left : null;
  }

  /// Questions answered, skipped or marked "I don't know", not counting one reopened by "go back".
  Set<String> get _doneFields {
    final s = state;
    if (s == null) return {};
    final confirmed = (s['confirmed_profile'] as Map?) ?? const {};
    return {
      for (final e in confirmed.entries)
        if (e.value != null) '${e.key}',
      for (final f in (s['skipped_fields'] as List?) ?? const []) '$f',
      for (final f in (s['unknown_fields'] as List?) ?? const []) '$f',
    }..remove(s['current_field']);
  }

  /// "Question N of 12", worked out from the server's state. Null when there is no question
  /// (done, or a habit follow-up). Only the asked fields count, so a follow-up or a blood
  /// pressure reading never moves the number past the last question.
  int? get questionNumber {
    final t = turn;
    if (t == null || t.complete || t.phase == 'probing') return null;
    final done = _doneFields.where(askedFields.contains).length;
    return (done + 1).clamp(1, questionCount);
  }

  /// "Go back" reopens the answer before this question; once done, the last one, so an
  /// answer can still be changed or a skipped one added.
  bool get canGoBack => turn != null && !confirming && _doneFields.isNotEmpty;

  void _set(void Function() change) {
    change();
    if (!_disposed) notifyListeners();
  }

  // ---- consent -----------------------------------------------------------

  /// After "Delete my data": forget the conversation and the choices made in it, so the next Talk starts fresh.
  void resetConversation() => _set(() {
    turn = null;
    correcting = false;
    askingVoice = false;
    aiHelper = false;
    notice = null;
    caption = '';
    mascotLine = '';
  });

  Future<void> answerConsent(bool yes, {bool aiHelper = false}) async {
    if (phase != VoicePhase.consent || _busy) return;
    _set(() {
      voiceUsable = yes;
      typing = !yes;
      this.aiHelper = aiHelper;
    });
    if (yes) _warmUp(); // the token is ready by the time the first question is spoken
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

  /// Confirmed Apple Health or document answers waiting for the conversation to start.
  Map<String, Object>? _pendingHealth;
  String _pendingSource = 'apple_health';

  /// True while Apple Health values wait for the conversation to start.
  bool get hasPendingHealth => _pendingHealth != null;

  /// Adds answers the person already checked on the Health screen. The server
  /// validates them and moves on to the next question that is still unanswered.
  ///
  /// Values checked before the conversation started (the Room's "Use my Apple Health")
  /// are kept and added as soon as its first question arrives.
  ///
  /// True when the values were taken: queued for the start, or sent and accepted. False
  /// when nothing was added (none checked, busy, an answer still being confirmed, or the
  /// server refused them or could not be reached); the reason is in [notice].
  Future<bool> importHealth(Map<String, num> values) =>
      _importConfirmed(values, source: 'apple_health', none: healthNoneNotice, wait: healthWaitNotice);

  /// Adds answers the person confirmed one by one from an uploaded document
  /// (app/lib/documents/). Same rules as [importHealth]; a separate source.
  Future<bool> importDocument(Map<String, Object> values) =>
      _importConfirmed(values, source: 'document', none: documentNoneNotice, wait: documentWaitNotice);

  /// The last import that was taken: how many answers and from where (`apple_health` or `document`), for the
  /// quiet "Added N things" note. A new record each time.
  ({int count, String source})? lastImport;

  Future<bool> _importConfirmed(
    Map<String, Object> values, {
    required String source,
    required String none,
    required String wait,
  }) async {
    if (turn == null) {
      if (values.isEmpty) return false;
      _pendingHealth = {...?_pendingHealth, ...values};
      _pendingSource = source;
      _set(() => lastImport = (count: values.length, source: source));
      return true;
    }
    if (_busy) return false;
    if (values.isEmpty) {
      // Once every question is answered there is nothing left to "keep asking".
      if (turn?.complete != true) _set(() => notice = none);
      return false;
    }
    if (confirming) {
      _set(() => notice = wait);
      return false;
    }
    await _stopSpeech();
    final before = turn;
    await _send('import', values: values, importSource: source);
    final taken = notice == null && !identical(turn, before);
    if (taken) _set(() => lastImport = (count: values.length, source: source));
    return taken;
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
      await _stopOutput();
    }
    _set(() {
      phase = VoicePhase.listening;
      caption = '';
      notice = null;
      _retry = null;
    });
    try {
      // The system's "Allow microphone?" question waits for the person, however long they
      // take to read it; only connecting afterwards is held to the start limit.
      if (!await input.hasPermission()) throw const MicDeniedException();
      if (phase != VoicePhase.listening) return; // cancelled (or the app left) meanwhile
      await input
          .start((text) {
            if (text != caption) _silentSeconds = 0;
            _set(() => caption = text);
          }, onDropped: (_) => _inputDropped())
          .timeout(_micStartLimit);
      if (phase == VoicePhase.listening) _startListenClock();
    } on MicDeniedException {
      _set(() {
        phase = VoicePhase.idle;
        typing = true;
        notice = micDeniedNotice;
      });
      await _speakNotice(micDeniedNotice);
    } on VoiceUnavailableException {
      _set(() {
        phase = VoicePhase.idle;
        typing = true;
        _voiceOut();
      });
    } on TimeoutException {
      _set(() {
        phase = VoicePhase.idle;
        notice = voiceTroubleNotice;
      });
      try {
        await input.cancel().timeout(_quickLimit); // a start that never answered must not leave the mic on
      } catch (_) {}
    } catch (_) {
      _set(() {
        phase = VoicePhase.idle;
        notice = voiceTroubleNotice;
      });
    }
  }

  /// The connection was lost while listening. The input has already stopped the mic.
  void _inputDropped() {
    if (phase != VoicePhase.listening) return;
    _stopListenClock();
    _set(() {
      phase = VoicePhase.idle;
      notice = voiceTroubleNotice;
    });
  }

  void _startListenClock() {
    _listenClock?.cancel();
    _listenedSeconds = 0;
    _silentSeconds = 0;
    _listenClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (phase != VoicePhase.listening) return _stopListenClock();
      _listenedSeconds++;
      _silentSeconds++;
      if (_silentSeconds >= silenceLimit.inSeconds || _listenedSeconds >= listenLimit.inSeconds) {
        _stopListenClock();
        unawaited(stopTalk());
      } else if (listenSecondsLeft != null) {
        _set(() {});
      }
    });
  }

  void _stopListenClock() {
    _listenClock?.cancel();
    _listenClock = null;
  }

  /// Closes the microphone and sends what was heard.
  Future<void> stopTalk() async {
    await _starting;
    if (phase != VoicePhase.listening) return;
    _stopListenClock();
    _set(() => phase = VoicePhase.interpreting);
    String text;
    try {
      text = (await input.finish().timeout(_micFinishLimit)).trim();
    } on VoiceUnavailableException {
      _set(() {
        phase = VoicePhase.idle;
        typing = true;
        _voiceOut();
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
      await _speakNotice(emptyTranscriptNotice);
      return;
    }
    _set(() => caption = text);
    await _send('reply', text: text, fromTranscript: true);
  }

  /// Closes the microphone and throws away what was heard.
  Future<void> cancelTalk() async {
    await _starting;
    if (phase != VoicePhase.listening) return;
    _stopListenClock();
    try {
      await input.cancel().timeout(_quickLimit);
    } catch (_) {}
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

  /// Tap-to-answer choices for short categorical questions, which voice
  /// mishears ("female" as "email"). Label shown, and the words sent.
  /// Empty unless the server is asking (not confirming) one of these fields.
  List<(String, String)> get quickAnswers {
    final t = turn;
    if (t == null || t.complete || t.phase != 'asking' || correcting) return const [];
    return switch (t.state['current_field']) {
      'sex' => const [('Female', 'female'), ('Male', 'male')],
      'diabetes' => const [('Yes', 'yes'), ('No', 'no'), ('Not sure', "I don't know")],
      'smoking_status' => const [
        ('I smoke now', 'I smoke now'),
        ('I used to smoke', 'I used to smoke'),
        ('I never smoked', 'I have never smoked'),
      ],
      _ => const [],
    };
  }

  /// A tapped quick answer: stops the mascot or the microphone, then sends the
  /// same words a person would say.
  Future<void> submitQuick(String text) async {
    if (_busy || phase == VoicePhase.interpreting) return;
    if (phase == VoicePhase.listening) await cancelTalk();
    await submitTyped(text);
  }

  Future<void> confirm() => _button('confirm');
  Future<void> change() async {
    if (_busy || !confirming || (phase != VoicePhase.idle && phase != VoicePhase.speaking)) return;
    await _stopSpeech();
    _set(() {
      correcting = true;
      notice = null;
    });
  }

  /// Goes back to Yes / No without changing anything.
  void keepAnswer() => _set(() => correcting = false);
  Future<void> skip() => _button('skip');

  /// Reopens the answer before this question. The server understands the words "go back".
  Future<void> goBack() async {
    if (!canGoBack) return;
    await _button('reply', text: 'go back');
  }

  /// The conversation is paused because something urgent was said.
  bool get emergency => turn?.emergency == true;

  /// Continue after the pause: the server repeats the same question.
  Future<void> continueAfterEmergency() async {
    if (!emergency) return;
    await _button('resume');
  }

  /// Stops the mascot talking.
  Future<void> stopSpeaking() => _stopSpeech();

  Future<void> _button(String action, {String? text}) async {
    if (_busy) return;
    if (phase == VoicePhase.listening) await cancelTalk();
    if (phase != VoicePhase.idle && phase != VoicePhase.speaking && phase != VoicePhase.done) return;
    await _stopSpeech();
    await _send(action, text: text);
  }

  /// Repeats the request that failed.
  Future<void> retry() async {
    final r = _retry;
    if (r == null || _busy) return;
    await r();
  }

  Future<void> setTyping(bool value) async {
    if (value == typing) return;
    if (!value && !voiceUsable) {
      // Voice was never agreed to (or stopped working): ask before any talking.
      _set(() => askingVoice = true);
      return;
    }
    if (!value) _warmUp();
    if (value) {
      if (phase == VoicePhase.listening) await cancelTalk();
      await _stopSpeech();
      // A microphone that never answered must not leave the field switched off.
      if (!_busy && phase == VoicePhase.interpreting) _set(() => phase = VoicePhase.idle);
    }
    _set(() => typing = value);
  }

  /// The answer to "Talk with me?" when asked after starting by typing.
  void answerVoiceAgain(bool yes) {
    _set(() {
      askingVoice = false;
      if (yes) {
        voiceUsable = true;
        typing = false;
        notice = null;
        _clearOutage();
      }
    });
    if (yes) _warmUp();
  }

  Future<void> hearAgain() async {
    if (!canHearAgain) return;
    if (phase == VoicePhase.listening) await cancelTalk();
    final line = mascotLine;
    await _speak(line, replay: output.canReplay && _spokeMascotLine);
  }

  // ---- server turn -----------------------------------------------------------

  Future<void> _send(
    String action, {
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    String? importSource,
  }) async {
    if (_busy) return;
    if (turn == null && action != 'start') {
      // The first question never arrived (e.g. no network), so there is nothing to answer
      // yet: the server would refuse it. Anything sent, Try again included, starts instead.
      return _send('start');
    }
    _busy = true;
    _tryVoiceAgain();
    if (action == 'reply' && text != null) _lastReply = (text, fromTranscript);
    // After "No, change it" the next answer is a correction. Otherwise a reply
    // to a read-back goes as a reply, so the server can hear "yes", "no" or a new value.
    final wire = action == 'reply' && confirming && correcting ? 'correct' : action;
    _set(() {
      phase = VoicePhase.interpreting;
      notice = null;
      _retry = null;
    });
    final GuideTurn t;
    try {
      t = await guide
          .turn(
            action: wire,
            state: turn?.state,
            text: text,
            fromTranscript: fromTranscript,
            values: values,
            aiHelper: aiHelper,
            importSource: importSource,
          )
          .timeout(_turnLimit);
    } on GuideRejected catch (e) {
      // The server explained what is wrong; show its words. Nothing was changed.
      _busy = false;
      _set(() {
        phase = turn?.complete == true ? VoicePhase.done : VoicePhase.idle;
        notice = action == 'import' ? '$healthRejectedPrefix${e.message}' : e.message;
      });
      return;
    } catch (e) {
      _busy = false;
      _set(() {
        phase = VoicePhase.idle;
        notice = e is GuideTooBusy ? e.message : noNetworkNotice;
        _retry = () =>
            _send(action, text: text, fromTranscript: fromTranscript, values: values, importSource: importSource);
      });
      if (!typing) await _speakNotice(notice!);
      return;
    }
    _busy = false;
    _set(() {
      if (_voiceBack) _voiceIn();
      correcting = false;
      turn = t;
      mascotLine = t.message;
      phase = t.complete ? VoicePhase.done : VoicePhase.idle;
    });
    final pending = _pendingHealth;
    if (action == 'start' && pending != null) {
      // The answer to the import asks the first open question, so only it is spoken.
      _pendingHealth = null;
      return _send('import', values: pending, importSource: _pendingSource);
    }
    if (!typing && voiceUsable && !screenReader) await _speak(t.message);
  }

  // ---- voice outage ----------------------------------------------------------

  /// Voice was switched off because the server said it is unavailable (not by the person).
  bool _voiceOutage = false;

  /// A token was minted since the outage: voice comes back on the next turn.
  bool _voiceBack = false;
  Future<void>? _recovering;

  /// Shows the "voice unavailable" notice and switches to typing; call inside [_set].
  /// A token is retried in the background, and again with every turn.
  void _voiceOut() {
    typing = true;
    voiceUsable = false;
    notice = voiceOffNotice;
    _voiceOutage = true;
    _voiceBack = false;
    _tryVoiceAgain();
  }

  void _tryVoiceAgain() {
    if (!_voiceOutage || _voiceBack || _recovering != null || _disposed) return;
    _recovering = input
        .warmUp()
        .then((_) => _voiceBack = _voiceOutage, onError: (Object _) => false)
        .whenComplete(() => _recovering = null);
  }

  /// Voice works again: back to talking, as before the outage. Call inside [_set].
  void _voiceIn() {
    voiceUsable = true;
    typing = false;
    _voiceOutage = false;
    _voiceBack = false;
  }

  /// The person chose voice again themselves; no outage to recover from.
  void _clearOutage() {
    _voiceOutage = false;
    _voiceBack = false;
  }

  // ---- speaking --------------------------------------------------------------

  /// Gets voice ready in the background; any problem shows up when voice is used.
  void _warmUp() => input.warmUp().ignore();

  Future<void> _stopOutput() async {
    try {
      await output.stop().timeout(_quickLimit);
    } catch (_) {}
  }

  Future<void> _stopSpeech() async {
    if (phase == VoicePhase.speaking) {
      _speechGen++;
      await _stopOutput();
      _set(() => phase = turn?.complete == true ? VoicePhase.done : VoicePhase.idle);
    }
  }

  /// Says an important notice out loud for someone using voice. A screen
  /// reader announces it already.
  Future<void> _speakNotice(String text) async {
    if (!voiceUsable || screenReader) return;
    await _speak(text, mascotLine: false);
  }

  Future<void> _speak(String line, {bool replay = false, bool mascotLine = true}) async {
    final gen = ++_speechGen;
    _spokeMascotLine = mascotLine;
    _set(() => phase = VoicePhase.speaking);
    try {
      await (replay ? output.replay() : output.speak(spokenText(line))).timeout(_speakLimit);
    } on VoiceUnavailableException {
      // A notice that could not be said aloud is still on screen; replacing it (say, "can't
      // reach LifeTwin" with "couldn't say that") would hide what went wrong.
      if (gen == _speechGen && mascotLine) {
        _set(() {
          typing = true;
          _voiceOut();
        });
      }
    } catch (_) {
      if (gen == _speechGen && mascotLine) _set(() => notice = speakTroubleNotice);
    }
    if (gen == _speechGen && phase == VoicePhase.speaking) {
      _set(() => phase = turn?.complete == true ? VoicePhase.done : VoicePhase.idle);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopListenClock();
    input.dispose();
    output.dispose();
    super.dispose();
  }
}
