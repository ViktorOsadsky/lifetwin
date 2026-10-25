import 'dart:async';

import 'package:flutter/foundation.dart';

import '../voice/speech.dart';
import '../voice/voice_log.dart';
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

/// Hands-free: said once after a long quiet; then Mochi just keeps listening.
const listeningNudge = "Take your time. I'm still listening.";

/// Runs the conversation loop. The server decides what happens; this class only
/// holds the caller-owned state, moves audio in and out, and keeps answers safe
/// when voice fails.
class VoiceOnboardingController extends ChangeNotifier {
  VoiceOnboardingController({
    required this.guide,
    required this.input,
    required this.output,
    this.handsFree = false,
    this.startState,
  });

  final ConversationGuide guide;
  final SpeechInput input;
  final SpeechOutput output;

  /// Voice mode is one continuous session, as in a phone call: whenever Mochi is not
  /// speaking, the microphone listens, and quiet never closes it. Typing pauses it until
  /// the person goes back to voice. Off (tap to talk) with VoiceOver on, and in tests that
  /// don't ask for it.
  final bool handsFree;

  /// Set by the screen: whether the microphone may open by itself now (the conversation is
  /// the top route and the app is in front). Null: no screen asks (controller tests).
  bool Function()? mayListen;

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

  /// The one current question is the server's: [turn]'s `current_field`. Everything the
  /// client does is checked against it.
  GuideTurn? turn;
  bool _busy = false;

  /// "Question N saved": the number of the question just answered. Set the moment the answer
  /// is sent (typed, spoken or tapped), before the reply, and kept beside the next question
  /// until the next answer. Cleared when the reply asks that same question again (not
  /// understood, read back for a yes, or Go back) or the request failed.
  int? savedNumber;

  /// The question being answered while its reply is on its way: already counted as done.
  String? _sending;

  /// Bumped whenever the open question changes hands: an answer is sent, a turn arrives, or
  /// heard words are dropped (Type instead, leaving). Voice work begun under an older token,
  /// a late caption, an end-of-turn timer, a recognizer still finishing or a dropped
  /// connection with words, belongs to a question that is no longer open, and is dropped.
  int _turnToken = 0;
  bool _stale(int token) => token != _turnToken;

  /// The turn whose line Mochi last said to the end. Its audio is what a replay plays, so a
  /// line that came while typing or out of sight is said fresh, never an older one replayed.
  GuideTurn? _saidTurn;

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
  static const silenceLimit = voiceQuietClose; // before the first word
  static const endOfTurn = voiceEndOfTurn; // after a word: send once this quiet
  Timer? _endOfTurnTimer;
  static const listenLimit = Duration(seconds: 30);
  Timer? _listenClock;
  int _listenedSeconds = 0;
  int _silentSeconds = 0;

  /// Hands-free: the one nudge for this question was said.
  bool _nudged = false;
  bool _nudging = false;

  /// "I think I heard someone else" was said for this question (server `off_topic`).
  bool _offTopicSaid = false;

  /// Read-only, for the voice indicator: the nudge was said for this question.
  bool get nudged => _nudged;

  /// Read-only, for the voice indicator: the nudge is being spoken now (the microphone is closed).
  bool get nudgeSpeaking => _nudging;

  /// Hands-free: connections lost in a row before anything was heard (restarted out of sight).
  /// A listen that stays up for [_healthyListen] starts the count again, so a recognizer
  /// that ends now and then during a long quiet is always restarted.
  int _drops = 0;
  static const _dropRestarts = 3;
  static const _healthyListen = 10; // seconds

  /// Hands-free: a microphone that failed to open (socket, token, recorder) is tried again,
  /// still "Listening", after 1 s, 2 s, then 3 s. Only then does the trouble notice show.
  int _startFailures = 0;
  static const _startRetries = 3;
  Timer? _startRetry;

  /// The screen is out of sight (left, or the app is in the background): nothing opens by itself.
  bool _paused = false;

  /// The person closed the microphone (separate from [_paused], so coming back on screen never
  /// reopens it). Nothing opens it by itself until [turnMicOn].
  bool _micOff = false;
  bool get micOff => _micOff;

  /// The conversation's first line has not been spoken yet; timed from [_openedAt].
  bool _firstLine = true;
  Stopwatch? _openedAt;
  static const firstAudioLimit = voiceFirstAudioLimit;
  static const nudgeAfter = voiceNudgeAfter;
  static const sessionRestart = voiceSessionRestart;

  /// Nothing the microphone, the speaker or the network does may keep the
  /// screen waiting for ever: every wait ends, and the person can carry on.
  static const _micStartLimit = Duration(seconds: 10);
  static const _micFinishLimit = Duration(seconds: 20);
  static const _quickLimit = Duration(seconds: 4);
  static const _speakLimit = Duration(seconds: 60);
  static const _turnLimit = Duration(seconds: 30);
  int _speechGen = 0;
  int _conversationGen = 0;
  Future<void>? _resetAudio;
  bool _currentConversation(int gen) => !_disposed && gen == _conversationGen;
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

  /// Mochi is offering Apple Health (after age, sex and smoking; the phase stays `offering`
  /// after a yes). Once the person just answers, the server moves on and the hint goes.
  bool get healthOffer => turn?.phase == 'offering';

  /// The latest turn's `model_inputs` (see GuideTurn.modelInputs).
  Map<String, dynamic>? get modelInputs => turn?.modelInputs;

  bool get canRetry => _retry != null;
  bool get canHearAgain => voiceUsable && mascotLine.isNotEmpty && !typing && phase != VoicePhase.interpreting;

  /// Hands-free is on now: the microphone opens by itself (VoiceOver uses a single tap instead).
  bool get continuous => handsFree && !screenReader;

  /// Seconds until the microphone closes by itself, shown only near the end.
  int? get listenSecondsLeft {
    if (phase != VoicePhase.listening || _listenClock == null || continuous) return null;
    final left = listenLimit.inSeconds - _listenedSeconds;
    return left <= 10 ? left : null;
  }

  /// Questions answered, skipped or marked "I don't know", not counting one reopened by "go back".
  Set<String> get _doneFields {
    final s = state;
    if (s == null) return {};
    return _doneIn(s)
      ..remove(s['current_field'])
      ..addAll([?_sending]);
  }

  /// "Question N of 12", worked out from the server's state. Null when there is no question
  /// (done, or a habit follow-up). Only the asked fields count, so a follow-up or a blood
  /// pressure reading never moves the number past the last question.
  int? get questionNumber {
    final t = turn;
    if (t == null || t.complete || t.phase == 'probing' || t.phase == 'missing') return null;
    final asked = _asked;
    final done = _doneFields.where(asked.contains).length;
    return (done + 1).clamp(1, asked.length);
  }

  /// The questions this conversation asks: the whole intake, or in "Answer N more questions"
  /// only the missing ones (`ask_only`).
  List<String> get _asked {
    final only = (turn?.state ?? startState)?['ask_only'];
    return only is List && only.isNotEmpty ? [for (final f in only) '$f'] : askedFields;
  }

  /// "of N" beside [questionNumber].
  int get questionTotal => _asked.length;

  /// "Answer N more questions": the conversation starts from this state (the saved profile and
  /// `ask_only`) instead of a fresh intake. Null: the whole intake.
  final Map<String, dynamic>? startState;

  /// "Go back" reopens the answer before this question; once done, the last one, so an
  /// answer can still be changed or a skipped one added.
  bool get canGoBack => turn != null && !confirming && _doneFields.isNotEmpty;

  void _set(void Function() change) {
    change();
    if (!_disposed) notifyListeners();
  }

  void _hf(String name, [String detail = '']) => voiceLog('onb', name, detail);

  // ---- consent -----------------------------------------------------------

  /// After "Delete my data": forget the conversation and the choices made in it, so the next Talk starts fresh.
  void resetConversation() {
    // Invalidate work before stopping audio: an old guide/recognizer completion
    // must never restore deleted answers, retries or captions in the new session.
    _conversationGen++;
    _speechGen++;
    _stopListenClock();
    _openedAt?.stop();
    _openedAt = null;
    _starting = null;
    // A second reset must also wait for any earlier bounded audio teardown.
    final previousCleanup = _resetAudio;
    _resetAudio = Future.wait([?previousCleanup, _cancelInput(), _stopOutput()]).then((_) {});
    _set(() {
      turn = null;
      phase = VoicePhase.consent;
      typing = false;
      voiceUsable = true;
      _busy = false;
      _firstLine = true;
      _nudged = false;
      _drops = 0;
      _startFailures = 0;
      _saidTurn = null;
      _sending = null;
      savedNumber = null;
      _turnToken++;
      _paused = false;
      _micOff = false;
      _retry = null;
      _lastReply = null;
      _pendingHealth = null;
      _pendingSource = 'apple_health';
      lastImport = null;
      _voiceOutage = false;
      _voiceBack = false;
      _recovering = null;
      correcting = false;
      askingVoice = false;
      aiHelper = false;
      notice = null;
      caption = '';
      mascotLine = '';
    });
  }

  Future<void> _cancelInput() async {
    try {
      await input.cancel().timeout(_quickLimit);
    } catch (_) {}
  }

  Future<void> answerConsent(bool yes, {bool aiHelper = false}) async {
    if (phase != VoicePhase.consent || _busy) return;
    final gen = _conversationGen;
    if (_resetAudio case final cleanup?) await cleanup;
    if (!_currentConversation(gen) || phase != VoicePhase.consent || _busy) return;
    _set(() {
      voiceUsable = yes;
      typing = !yes;
      this.aiHelper = aiHelper;
    });
    if (yes) {
      _warmUp(); // the token is ready by the time the first question is spoken
      _openedAt = Stopwatch()..start();
    }
    await _send('start');
  }

  /// "Yes, I'll talk" on the first consent question: voice was agreed to, so the token is
  /// fetched while the second question is read, and the first line need not wait for it.
  void prepareVoice() => _warmUp();

  /// Turns the AI helper on or off. Turning it on right after an answer that
  /// needed it sends that same answer again, so the person doesn't repeat it.
  Future<void> setAiHelper(bool on) async {
    final gen = _conversationGen;
    if (on == aiHelper || _busy) return;
    final resend = on && helperWouldHelp ? _lastReply : null;
    _set(() => aiHelper = on);
    if (resend != null) {
      if (phase == VoicePhase.listening) await cancelTalk();
      if (!_currentConversation(gen)) return;
      await _stopSpeech();
      if (!_currentConversation(gen)) return;
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
    final gen = _conversationGen;
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
      _listenAgain();
      return false;
    }
    if (confirming) {
      _set(() => notice = wait);
      _listenAgain();
      return false;
    }
    if (phase == VoicePhase.listening) await cancelTalk();
    if (!_currentConversation(gen)) return false;
    await _stopSpeech();
    if (!_currentConversation(gen)) return false;
    final before = turn;
    await _send('import', values: values, importSource: source);
    if (!_currentConversation(gen)) return false;
    final taken = notice == null && !identical(turn, before);
    if (taken) _set(() => lastImport = (count: values.length, source: source));
    return taken;
  }

  // ---- talking -----------------------------------------------------------

  /// Opens the microphone. Pressing Talk while the mascot speaks stops the mascot first.
  /// The microphone is still opening (permission or connecting): a release now is not "send".
  bool get micStarting => _starting != null;

  Future<void> startTalk({bool auto = false}) {
    // Ignore a second press while we are already starting, listening or waiting.
    if (_starting != null) return _starting!;
    if (typing || !voiceUsable) return Future.value();
    if (phase != VoicePhase.idle && phase != VoicePhase.speaking) return Future.value();
    final starting = _startTalk(auto: auto);
    _starting = starting;
    return starting.whenComplete(() {
      if (identical(_starting, starting)) _starting = null;
    });
  }

  Future<void> _startTalk({bool auto = false}) async {
    final gen = _conversationGen;
    if (_resetAudio case final cleanup?) await cleanup;
    if (!_currentConversation(gen)) return;
    if (phase == VoicePhase.speaking) {
      _speechGen++;
      await _stopOutput();
      if (!_currentConversation(gen)) return;
    }
    _set(() {
      phase = VoicePhase.listening;
      caption = '';
      // Opening by itself keeps a notice on screen (say, the server's reason) until the next answer.
      if (!auto) notice = null;
      _retry = null;
    });
    await _openMic();
  }

  /// Hands-free: opens the microphone when nothing else is going on (Mochi finished speaking,
  /// back to voice, back on screen). Never while Mochi speaks, so the loudspeaker is not heard.
  /// Not after a failed request (its Try again stays), in an emergency pause, once done, or
  /// before both the voice consent and the phone's microphone permission were given (the
  /// permission is asked by the first listen itself, and a no switches to typing for good).
  ///
  /// [sayFirst] (back in sight, back to voice): a question Mochi has not said to the end yet,
  /// say, one that came while typing or out of sight, is said once first. Never an older one.
  void _listenAgain({bool sayFirst = false}) {
    if (!continuous || _disposed) return;
    final t = turn;
    final why = _paused
        ? 'paused'
        : _micOff
        ? 'mic_off'
        : _busy
        ? 'busy'
        : typing
        ? 'typing'
        : !voiceUsable
        ? 'voice_off'
        : askingVoice
        ? 'asking_voice'
        : t == null || t.complete
        ? 'no_question'
        : t.emergency
        ? 'emergency'
        : _retry != null
        ? 'retry_shown'
        : phase != VoicePhase.idle
        ? 'phase_${phase.name}'
        : !(mayListen?.call() ?? true)
        ? 'not_on_screen'
        : null;
    if (why != null) return _hf('listen_skip', why);
    if (sayFirst && !identical(_saidTurn, t) && mascotLine.isNotEmpty) {
      unawaited(hearAgain());
      return;
    }
    unawaited(startTalk(auto: true));
  }

  /// The screen went out of sight (left, the app went to the background, a call): the
  /// microphone closes, words heard so far are dropped, and speech stops.
  Future<void> pauseVoice() async {
    final gen = _conversationGen;
    _paused = true;
    _stopListenClock(); // at once, so nothing keeps ticking after the screen is gone
    await cancelTalk();
    if (!_currentConversation(gen)) return;
    await _stopSpeech();
    if (!_currentConversation(gen)) return;
    if (!_paused) _listenAgain(); // back in sight meanwhile
  }

  /// "Turn off mic": words already heard go as the answer right away (as at the end-of-turn
  /// silence); with none, the microphone just closes. It then stays off until [turnMicOn].
  Future<void> turnMicOff() async {
    if (_micOff || _disposed) return;
    _set(() => _micOff = true);
    _hf('mic_off');
    _startRetry?.cancel();
    _startRetry = null;
    if (phase != VoicePhase.listening && _starting == null) return;
    if (caption.trim().isNotEmpty) return stopTalk();
    await cancelTalk();
  }

  /// "Turn on mic": hands-free listens again by itself.
  void turnMicOn() {
    if (!_micOff) return;
    _set(() => _micOff = false);
    _hf('mic_on');
    _listenAgain(sayFirst: true); // a question that came while it was off is said once first
  }

  /// The screen is in sight again: hands-free listens again by itself.
  void resumeVoice() {
    _paused = false;
    _listenAgain(sayFirst: true);
  }

  Future<void> _openMic() async {
    final gen = _conversationGen;
    final token = _turnToken;
    try {
      // The system's "Allow microphone?" question waits for the person, however long they
      // take to read it; only connecting afterwards is held to the start limit.
      if (!await input.hasPermission()) throw const MicDeniedException();
      if (!_currentConversation(gen) || phase != VoicePhase.listening) return; // cancelled (or the app left) meanwhile
      await input
          .start(
            (text) {
              if (!_currentConversation(gen) || _stale(token) || phase != VoicePhase.listening) return;
              if (text != caption) {
                _silentSeconds = 0;
                _hf('partial', heardForLog(text));
              }
              _set(() => caption = text);
              _armEndOfTurn(text);
            },
            onDropped: (e) {
              if (_currentConversation(gen) && !_stale(token)) _inputDropped(e);
            },
          )
          .timeout(_micStartLimit);
      if (!_currentConversation(gen)) return;
      if (phase == VoicePhase.listening && !_paused) {
        _hf('mic_open');
        _startFailures = 0;
        _startListenClock();
      }
    } on MicDeniedException {
      if (!_currentConversation(gen)) return;
      _hf('error', 'mic_denied');
      _set(() {
        phase = VoicePhase.idle;
        typing = true;
        notice = micDeniedNotice;
      });
      await _speakNotice(micDeniedNotice);
    } on VoiceUnavailableException catch (e) {
      if (!_currentConversation(gen)) return;
      _hf('error', 'mic_start ${e.reason}');
      _set(() {
        phase = VoicePhase.idle;
        typing = true;
        _voiceOut();
      });
    } on TimeoutException {
      _hf('error', 'mic_start timeout');
      try {
        await input.cancel().timeout(_quickLimit); // a start that never answered must not leave the mic on
      } catch (_) {}
      if (!_currentConversation(gen)) return;
      if (_retryStart()) return;
      _set(() {
        phase = VoicePhase.idle;
        notice = voiceTroubleNotice;
      });
    } catch (e) {
      if (!_currentConversation(gen)) return;
      _hf('error', 'mic_start $e');
      if (_retryStart()) return;
      _set(() {
        phase = VoicePhase.idle;
        notice = voiceTroubleNotice;
      });
    }
  }

  /// Hands-free: a microphone that failed to open is opened again a little later, out of
  /// sight. False when it is not hands-free now or the retries are used up.
  bool _retryStart() {
    if (!continuous || _paused || _disposed || phase != VoicePhase.listening) return false;
    if (_startFailures >= _startRetries) return false;
    _startFailures++;
    _hf('recognizer_restart', 'after_start_error $_startFailures');
    _startRetry?.cancel();
    final gen = _conversationGen;
    _startRetry = Timer(Duration(seconds: _startFailures), () {
      _startRetry = null;
      if (_currentConversation(gen) && phase == VoicePhase.listening && !_paused) _restartMic(stopFirst: false);
    });
    return true;
  }

  /// The connection was lost while listening. The input has already stopped the mic.
  /// Hands-free, before anything was heard, the recognizer is simply started again.
  void _inputDropped(Object error) {
    _hf('dropped', '$error phase=${phase.name} heard=${caption.trim().isNotEmpty} drops=$_drops');
    if (phase != VoicePhase.listening) return;
    _stopListenClock();
    final heard = caption.trim();
    if (continuous && !_paused && heard.isEmpty && _drops < _dropRestarts) {
      _drops++;
      _hf('recognizer_restart', 'after_drop');
      _restartMic(stopFirst: false);
      return;
    }
    if (continuous && !_paused && heard.isNotEmpty) {
      // Words were heard before the connection went: they are the answer, as after a pause.
      _hf('mic_close', 'dropped_send');
      _set(() => phase = VoicePhase.idle);
      unawaited(_send('reply', text: heard, fromTranscript: true));
      return;
    }
    _hf('mic_close', 'dropped');
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
      if (_listenedSeconds >= _healthyListen) _drops = 0;
      if (continuous && caption.trim().isEmpty) {
        // Quiet never closes a hands-free microphone: one nudge, then the recognizer restarts
        // before the phone's session limit.
        if (!_nudged && _silentSeconds >= nudgeAfter.inSeconds) {
          _stopListenClock();
          unawaited(_nudge());
        } else if (_listenedSeconds >= sessionRestart.inSeconds) {
          _stopListenClock();
          _hf('recognizer_restart', 'session ${_listenedSeconds}s');
          _restartMic();
        }
        return;
      }
      if (continuous) {
        if (_listenedSeconds >= listenLimit.inSeconds) {
          _stopListenClock();
          _hf('mic_close', 'listen_limit');
          unawaited(stopTalk());
        }
        return;
      }
      if (_silentSeconds >= silenceLimit.inSeconds || _listenedSeconds >= listenLimit.inSeconds) {
        _stopListenClock();
        _hf('mic_close', _silentSeconds >= silenceLimit.inSeconds ? 'quiet' : 'listen_limit');
        unawaited(stopTalk());
      } else if (listenSecondsLeft != null) {
        _set(() {});
      }
    });
  }

  void _stopListenClock() {
    _listenClock?.cancel();
    _listenClock = null;
    _startRetry?.cancel();
    _startRetry = null;
    _endOfTurnTimer?.cancel();
    _endOfTurnTimer = null;
  }

  /// Hands-free: a fresh recognizer session while the screen keeps saying "Listening".
  void _restartMic({bool stopFirst = true}) {
    if (_starting != null || _disposed) return;
    final gen = _conversationGen;
    Future<void> again() async {
      if (stopFirst) {
        try {
          await input.cancel().timeout(_quickLimit);
        } catch (_) {}
      }
      if (_currentConversation(gen) && phase == VoicePhase.listening) await _openMic();
    }

    final starting = again();
    _starting = starting;
    starting.whenComplete(() {
      if (identical(_starting, starting)) _starting = null;
    });
  }

  /// Hands-free, after a long quiet: "Take your time. I'm still listening." once, then listening again.
  Future<void> _nudge() async {
    final gen = _conversationGen;
    _nudged = true;
    _hf('nudge', 'quiet ${_silentSeconds}s');
    _hf('mic_close', 'nudge');
    try {
      await input.cancel().timeout(_quickLimit);
    } catch (_) {}
    if (!_currentConversation(gen)) return;
    if (phase != VoicePhase.listening || _disposed) return;
    _set(() {
      phase = VoicePhase.idle;
      _nudging = true;
    });
    final said = await _speak(listeningNudge, mascotLine: false);
    _set(() => _nudging = false);
    if (said) _listenAgain();
  }

  /// Every caption (a new partial or final) restarts the end-of-turn wait, once a word is heard.
  void _armEndOfTurn(String text) {
    if (_disposed || text.trim().isEmpty) return;
    _drops = 0;
    _endOfTurnTimer?.cancel();
    final token = _turnToken;
    _endOfTurnTimer = Timer(endOfTurn, () {
      _endOfTurnTimer = null;
      if (!_disposed && !_stale(token) && phase == VoicePhase.listening) {
        _hf('end_of_turn');
        unawaited(stopTalk());
      }
    });
  }

  /// Closes the microphone and sends what was heard.
  Future<void> stopTalk() async {
    final gen = _conversationGen;
    await _starting;
    if (!_currentConversation(gen)) return;
    if (phase != VoicePhase.listening) return;
    final token = _turnToken;
    // Heard for another question meanwhile (typed, tapped, Type instead): dropped, never sent.
    bool superseded() {
      if (!_currentConversation(gen)) return true;
      if (!_stale(token)) return false;
      _hf('stale_drop', 'finish');
      return true;
    }

    _stopListenClock();
    _hf('mic_close', 'finish');
    _set(() => phase = VoicePhase.interpreting);
    String text;
    try {
      text = (await input.finish().timeout(_micFinishLimit)).trim();
      if (superseded()) return;
      _hf('final', heardForLog(text));
    } on VoiceUnavailableException {
      if (superseded()) return;
      _hf('error', 'finish voice_unavailable');
      _set(() {
        phase = VoicePhase.idle;
        typing = true;
        _voiceOut();
      });
      return;
    } catch (e) {
      if (superseded()) return;
      _hf('error', 'finish $e');
      final heard = caption.trim();
      if (continuous && !_paused) {
        // Hands-free: what was heard is still the answer; with nothing heard it just listens on.
        _set(() => phase = VoicePhase.idle);
        if (heard.isNotEmpty) return _send('reply', text: heard, fromTranscript: true);
        return _listenAgain();
      }
      _set(() {
        phase = VoicePhase.idle;
        notice = voiceTroubleNotice;
      });
      return;
    }
    if (text.isEmpty) {
      if (continuous) {
        // Nothing to send: hands-free simply keeps listening.
        _set(() {
          phase = VoicePhase.idle;
          caption = '';
        });
        return _listenAgain();
      }
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
    final gen = _conversationGen;
    // A listen that began meanwhile is waited for too, so no microphone is left open.
    while (_starting != null) {
      await _starting;
      if (!_currentConversation(gen)) return;
    }
    if (phase != VoicePhase.listening) return;
    _turnToken++; // what was heard is dropped, and any late word of it too
    _stopListenClock();
    _hf('mic_close', 'cancel');
    try {
      await input.cancel().timeout(_quickLimit);
    } catch (_) {}
    if (!_currentConversation(gen)) return;
    _set(() {
      phase = VoicePhase.idle;
      caption = '';
    });
  }

  // ---- typing and buttons ---------------------------------------------------

  Future<void> submitTyped(String text) async {
    final gen = _conversationGen;
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    if (phase != VoicePhase.idle && phase != VoicePhase.speaking) return;
    await _stopSpeech();
    if (!_currentConversation(gen)) return;
    _set(() => caption = t);
    await _send('reply', text: t);
  }

  /// Tap-to-answer choices for short categorical questions, which voice
  /// mishears ("female" as "email"). Label shown, and the words sent.
  /// Empty unless the server is asking (not confirming) one of these fields.
  List<(String, String)> get quickAnswers {
    final t = turn;
    // The one end-of-intake offer of the missing answers ("Want to answer them now?").
    if (t != null && !t.complete && t.phase == 'missing') return const [('Yes', 'yes'), ('Not now', 'not now')];
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
    final gen = _conversationGen;
    if (_busy || phase == VoicePhase.interpreting) return;
    if (phase == VoicePhase.listening) await cancelTalk();
    if (!_currentConversation(gen)) return;
    await submitTyped(text);
  }

  Future<void> confirm() => _button('confirm');
  Future<void> change() async {
    final gen = _conversationGen;
    if (_busy || !confirming) return;
    if (phase == VoicePhase.listening) await cancelTalk();
    if (!_currentConversation(gen)) return;
    if (phase != VoicePhase.idle && phase != VoicePhase.speaking) return;
    await _stopSpeech();
    if (!_currentConversation(gen)) return;
    _set(() {
      correcting = true;
      notice = null;
    });
    _listenAgain(); // hands-free: say the right answer
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

  /// Stops the mascot talking. Hands-free, the microphone then opens.
  Future<void> stopSpeaking() async {
    await _stopSpeech();
    _listenAgain();
  }

  Future<void> _button(String action, {String? text}) async {
    final gen = _conversationGen;
    if (_busy) return;
    if (phase == VoicePhase.listening) await cancelTalk();
    if (!_currentConversation(gen)) return;
    if (phase != VoicePhase.idle && phase != VoicePhase.speaking && phase != VoicePhase.done) return;
    await _stopSpeech();
    if (!_currentConversation(gen)) return;
    await _send(action, text: text);
  }

  /// Repeats the request that failed.
  Future<void> retry() async {
    final r = _retry;
    if (r == null || _busy) return;
    await r();
  }

  Future<void> setTyping(bool value) async {
    final gen = _conversationGen;
    if (value == typing) return;
    if (!value && !voiceUsable) {
      // Voice was never agreed to (or stopped working): ask before any talking.
      _set(() => askingVoice = true);
      return;
    }
    if (!value) _warmUp();
    if (value) {
      if (phase == VoicePhase.listening) await cancelTalk();
      if (!_currentConversation(gen)) return;
      await _stopSpeech();
      if (!_currentConversation(gen)) return;
      // A microphone still finishing: its words are dropped (the person types instead), and
      // the field is not left switched off.
      if (!_busy && phase == VoicePhase.interpreting) {
        _turnToken++;
        _set(() => phase = VoicePhase.idle);
      }
    }
    _set(() => typing = value);
    if (!value) {
      // Back to voice (owner): a question Mochi already said is not read again, the mic just
      // listens; one not said yet (it came while typing) is said once first. Once done,
      // nothing is said or heard; while a reply is on its way, the reply is said instead.
      // "Hear it again" is the way to replay.
      _listenAgain(sayFirst: true);
    }
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
    if (yes) {
      _warmUp();
      _listenAgain();
    }
  }

  Future<void> hearAgain() async {
    final gen = _conversationGen;
    if (!canHearAgain) return;
    if (phase == VoicePhase.listening) await cancelTalk();
    if (!_currentConversation(gen)) return;
    final line = mascotLine;
    // The speaker's last audio is replayed only when it is this very question.
    if (await _speak(line, replay: output.canReplay && identical(_saidTurn, turn))) _listenAgain();
  }

  // ---- server turn -----------------------------------------------------------

  Future<void> _send(
    String action, {
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    String? importSource,
  }) async {
    final gen = _conversationGen;
    if (!_currentConversation(gen)) return;
    if (_busy) return;
    if (turn == null && action != 'start') {
      // The first question never arrived (e.g. no network), so there is nothing to answer
      // yet: the server would refuse it. Anything sent, Try again included, starts instead.
      return _send('start');
    }
    if (phase == VoicePhase.listening) await cancelTalk(); // never wait on the server with the mic open
    if (!_currentConversation(gen)) return;
    _busy = true;
    _tryVoiceAgain();
    if (action == 'reply' && text != null) _lastReply = (text, fromTranscript);
    // After "No, change it" the next answer is a correction. Otherwise a reply
    // to a read-back goes as a reply, so the server can hear "yes", "no" or a new value.
    final wire = action == 'reply' && confirming && correcting ? 'correct' : action;
    // This answer is for the open question: it is marked done now, and anything still heard
    // or timed for that question is dropped.
    _turnToken++;
    final answering = _answering(action, text);
    final number = answering == null ? null : questionNumber;
    _set(() {
      phase = VoicePhase.interpreting;
      notice = null;
      _retry = null;
      _sending = answering;
      savedNumber = number;
    });
    _hf('send', action == 'reply' && text != null ? '$wire ${heardForLog(text)}' : wire);
    final GuideTurn t;
    try {
      t = await guide
          .turn(
            action: wire,
            state: turn?.state ?? (action == 'start' ? startState : null),
            text: text,
            fromTranscript: fromTranscript,
            values: values,
            aiHelper: aiHelper,
            importSource: importSource,
          )
          .timeout(_turnLimit);
    } on GuideRejected catch (e) {
      if (!_currentConversation(gen)) return;
      // The server explained what is wrong; show its words. Nothing was changed.
      _hf('error', 'turn rejected');
      _busy = false;
      _set(() {
        _unmark();
        phase = turn?.complete == true ? VoicePhase.done : VoicePhase.idle;
        notice = action == 'import' ? '$healthRejectedPrefix${e.message}' : e.message;
      });
      return;
    } catch (e) {
      if (!_currentConversation(gen)) return;
      _hf('error', 'turn $e');
      _busy = false;
      _set(() {
        _unmark();
        phase = VoicePhase.idle;
        notice = e is GuideTooBusy ? e.message : noNetworkNotice;
        _retry = () async {
          if (_currentConversation(gen)) {
            await _send(action, text: text, fromTranscript: fromTranscript, values: values, importSource: importSource);
          }
        };
      });
      if (!typing) await _speakNotice(notice!);
      return;
    }
    if (!_currentConversation(gen)) return;
    _busy = false;
    _hf(
      'turn',
      'field=${t.state['current_field']} phase=${t.phase} complete=${t.complete}${t.offTopic ? ' off_topic' : ''}',
    );
    _set(() {
      if (_voiceBack) _voiceIn();
      correcting = false;
      if (t.state['current_field'] != turn?.state['current_field'] || t.phase != turn?.phase) {
        _nudged = false;
        _offTopicSaid = false;
      }
      _drops = 0;
      // The answer stays marked only if the reply took it; the same question asked again
      // (not understood, read back, Go back) is open again.
      final sent = _sending;
      _sending = null;
      if (sent != null && (t.state['current_field'] == sent || !_doneIn(t.state).contains(sent))) savedNumber = null;
      _turnToken++;
      turn = t;
      // Someone else was heard: the question on screen stays, and the screen says why.
      if (!t.offTopic || mascotLine.isEmpty) mascotLine = t.message;
      if (t.offTopic) notice = offTopicLine;
      phase = t.complete ? VoicePhase.done : VoicePhase.idle;
    });
    final sayOffTopic = t.offTopic && !_offTopicSaid;
    if (t.offTopic) _offTopicSaid = true;
    final pending = _pendingHealth;
    if (action == 'start' && pending != null) {
      // The answer to the import asks the first open question, so only it is spoken.
      _pendingHealth = null;
      return _send('import', values: pending, importSource: _pendingSource);
    }
    // Nothing is said while the screen is out of sight; back on screen, it listens.
    if (typing || !voiceUsable || screenReader || _paused) return;
    if (t.offTopic) {
      // Asked once per question; after that it just listens again, so a TV never loops it.
      if (!sayOffTopic || await _speak(offTopicLine, mascotLine: false)) _listenAgain();
      return;
    }
    final first = _firstLine;
    _firstLine = false;
    if (await _speak(t.message, first: first)) _listenAgain();
  }

  /// The open question this action answers (typed, spoken, tapped, skipped or confirmed),
  /// or null when it answers none (start, import, resume, Go back, a follow-up).
  String? _answering(String action, String? text) {
    final s = turn?.state;
    final field = s?['current_field'];
    if (field is! String || turn!.complete) return null;
    if (s!['phase'] != 'asking' && s['phase'] != 'confirming') return null;
    if (!const {'reply', 'skip', 'confirm', 'correct'}.contains(action) || text == 'go back') return null;
    return field;
  }

  /// The request failed or was refused: the question is open again. Call inside [_set].
  void _unmark() {
    _sending = null;
    savedNumber = null;
  }

  static Set<String> _doneIn(Map<String, dynamic> s) => {
    for (final e in ((s['confirmed_profile'] as Map?) ?? const {}).entries)
      if (e.value != null) '${e.key}',
    for (final f in (s['skipped_fields'] as List?) ?? const []) '$f',
    for (final f in (s['unknown_fields'] as List?) ?? const []) '$f',
  };

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
    final gen = _conversationGen;
    _recovering = input
        .warmUp()
        .then((_) {
          if (_currentConversation(gen)) _voiceBack = _voiceOutage;
        }, onError: (Object _) {})
        .whenComplete(() {
          if (_currentConversation(gen)) _recovering = null;
        });
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
    final gen = _conversationGen;
    if (phase == VoicePhase.speaking) {
      _speechGen++;
      await _stopOutput();
      if (!_currentConversation(gen)) return;
      _set(() => phase = turn?.complete == true ? VoicePhase.done : VoicePhase.idle);
    }
  }

  /// Says an important notice out loud for someone using voice. A screen
  /// reader announces it already.
  Future<void> _speakNotice(String text) async {
    if (!voiceUsable || screenReader) return;
    await _speak(text, mascotLine: false);
  }

  /// True when the line ran to its end (or, the first line, gave up waiting for audio)
  /// and nothing else took over meanwhile: hands-free may listen next.
  Future<bool> _speak(String line, {bool replay = false, bool mascotLine = true, bool first = false}) async {
    final gen = ++_speechGen;
    // The speaker's last audio becomes this line: a replay is right only once it was said
    // to the end, and only for this turn.
    final saying = mascotLine ? turn : null;
    _saidTurn = null;
    _hf('tts_start', '${mascotLine ? 'line' : 'notice'}${first ? ' first' : ''}${replay ? ' replay' : ''}');
    _set(() => phase = VoicePhase.speaking);
    // The first line: if no audio has started within [firstAudioLimit], its words are on
    // screen, so speech stops and the microphone opens instead of leaving dead air.
    final late = Completer<void>();
    var heard = false;
    Timer? wait;
    void onAudio() {
      if (heard || gen != _speechGen || _disposed) return;
      heard = true;
      wait?.cancel();
      final at = _openedAt;
      _openedAt = null;
      _hf('first_audio', at == null ? '' : 'opened+${at.elapsedMilliseconds}ms');
    }

    if (first && continuous) {
      wait = Timer(firstAudioLimit, () {
        if (heard || gen != _speechGen || _disposed) return;
        _hf('error', 'no audio ${firstAudioLimit.inMilliseconds} ms after the first line came; listening instead');
        _openedAt = null;
        late.complete();
      });
    }
    try {
      final speech = replay ? output.replay() : output.speak(spokenText(line), onAudio: onAudio);
      await Future.any([speech, late.future]).timeout(_speakLimit);
      if (late.isCompleted) {
        if (gen != _speechGen || _disposed) return false;
        await _stopOutput();
        _hf('tts_end', 'gave_up_first');
        if (gen == _speechGen) _saidTurn = saying; // on screen, and not said again
        if (gen == _speechGen && phase == VoicePhase.speaking) {
          _set(() => phase = turn?.complete == true ? VoicePhase.done : VoicePhase.idle);
        }
        return gen == _speechGen;
      }
      _hf('tts_end', gen == _speechGen ? 'done' : 'stopped');
      if (gen == _speechGen) _saidTurn = saying;
    } on VoiceUnavailableException {
      _hf('tts_end', 'error voice_unavailable');
      // A notice that could not be said aloud is still on screen; replacing it (say, "can't
      // reach LifeTwin" with "couldn't say that") would hide what went wrong.
      if (gen == _speechGen && mascotLine) {
        _set(() {
          typing = true;
          _voiceOut();
        });
      }
    } catch (e) {
      _hf('tts_end', 'error $e');
      if (gen == _speechGen && mascotLine) _set(() => notice = speakTroubleNotice);
    } finally {
      wait?.cancel();
    }
    if (gen == _speechGen && phase == VoicePhase.speaking) {
      _set(() => phase = turn?.complete == true ? VoicePhase.done : VoicePhase.idle);
    }
    return gen == _speechGen;
  }

  @override
  void dispose() {
    _disposed = true;
    _conversationGen++;
    _speechGen++;
    _stopListenClock();
    input.dispose();
    output.dispose();
    super.dispose();
  }
}
