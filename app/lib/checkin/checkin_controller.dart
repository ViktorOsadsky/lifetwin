import 'dart:async';

import 'package:flutter/foundation.dart';

import '../health/health_sample.dart';
import '../onboarding/voice_onboarding_controller.dart'
    show
        emptyTranscriptNotice,
        micDeniedNotice,
        noNetworkNotice,
        speakTroubleNotice,
        voiceOffNotice,
        voiceTroubleNotice;
import '../voice/speech.dart';
import '../voice/spoken_text.dart';
import 'checkin_client.dart';
import 'checkin_models.dart';
import 'checkin_reminders.dart';
import 'checkin_scheduler.dart';
import 'checkin_store.dart';
import 'daily_logs.dart';
import 'health_suggestions.dart';

enum CheckinPhase {
  /// Nothing sent yet.
  notStarted,

  /// Mochi is talking.
  speaking,

  /// Waiting for the person.
  idle,

  /// The microphone is open.
  listening,

  /// Waiting for the server.
  interpreting,

  /// Finished (or stopped with Cancel).
  done,
}

/// The number the "Call 911" button dials. The person taps it; the app never calls.
final emergencyCallUri = Uri.parse('tel:911');
const savedNotice = "I couldn't save that just now. Please try again.";

/// Runs one check-in (quick, daily or weekly). The server decides what Mochi says; this
/// class holds the caller-owned state, moves audio in and out, and saves the confirmed
/// answers when the check-in finishes. It is the only path from a check-in to history:
/// nothing is saved except a finished conversation's confirmed read-backs.
///
/// Guards match the onboarding controller: one request at a time, a second tap while
/// busy does nothing, every wait has a time limit, and a failed request keeps the answers
/// with a Try again.
class CheckinController extends ChangeNotifier {
  CheckinController({
    required this.guide,
    required this.input,
    required this.output,
    required this.store,
    this.scheduler = const CheckinScheduler(),
    this.reminders,
    this.healthSamples,
    this.onFinished,
    DateTime Function()? clock,
    this.voiceUsable = true,
    this.ownsSpeech = true,
  }) : _clock = clock ?? DateTime.now,
       typing = !voiceUsable;

  final CheckinGuide guide;
  final SpeechInput input;
  final SpeechOutput output;

  /// False when [input] and [output] are the app-wide ones shared with later check-ins: dispose leaves them alone.
  final bool ownsSpeech;
  final CheckinStore store;
  final CheckinScheduler scheduler;

  /// Plans reminders after each check-in, and offers them once after the first one.
  final CheckinReminders? reminders;

  /// Apple Health samples already allowed by the person (sleep, exercise minutes), for
  /// one-tap "Looks right?" read-backs. Null when Apple Health isn't connected.
  final Future<List<HealthSample>> Function()? healthSamples;

  /// Called once with the finished turn after it is saved: a weekly check-in's
  /// `profile_update` goes to the profile from here (TwinRepository.applyCheckin).
  final Future<void> Function(CheckinTurn finished)? onFinished;
  final DateTime Function() _clock;

  CheckinPhase phase = CheckinPhase.notStarted;
  String kind = 'quick';

  /// The phone's date when this check-in started; its answers belong to it.
  String? localDate;

  /// The person agreed to voice (asked at onboarding). False types instead.
  bool voiceUsable;
  bool typing;

  /// VoiceOver already reads Mochi's words aloud, so Mochi doesn't speak them again.
  bool screenReader = false;

  CheckinTurn? turn;
  String mascotLine = '';
  String caption = '';

  /// A message that stays until the next action.
  String? notice;

  /// "No, change it" was pressed: the next answer replaces the one read back.
  bool correcting = false;

  /// The check-in is paused because something urgent was said. Show "Call 911"
  /// ([emergencyCallUri]) and Continue ([continueAfterEmergency]).
  bool emergency = false;

  /// Show the one-time "Would you like a gentle reminder each day?" offer.
  bool offerReminder = false;

  /// Good weeks so far and check-in days this week, after this check-in is saved.
  WeekProgress? progress;

  static const silenceLimit = voiceQuietClose; // before the first word
  static const endOfTurn = voiceEndOfTurn; // after a word: send once this quiet
  Timer? _endOfTurnTimer;
  static const listenLimit = Duration(seconds: 30);
  static const _micStartLimit = Duration(seconds: 10);
  static const _micFinishLimit = Duration(seconds: 20);
  static const _quickLimit = Duration(seconds: 4);
  static const _speakLimit = Duration(seconds: 60);
  static const _turnLimit = Duration(seconds: 30);

  bool _busy = false;
  bool _saved = false;
  bool _disposed = false;
  Future<void>? _starting;
  Future<void> Function()? _retry;
  Timer? _listenClock;
  int _listenedSeconds = 0;
  int _silentSeconds = 0;
  int _speechGen = 0;

  /// A yes/no is open: the one read-back at the end ([finalReadback]), a check question
  /// about one unusual answer ([checkQuestion]), or (weekly) the read-back of one answer.
  bool get confirming => turn?.isConfirming ?? false;

  /// Quick and daily: the one read-back of every answer, at the end. [confirm] saves them
  /// all; [change] then the person's words ("my sleep was 6 hours") correct one.
  bool get finalReadback => turn?.isFinalReadback ?? false;

  /// Mochi's warm reply to a low mood is open: "Keep going" or "Stop for today" (sent as replies).
  bool get careQuestionOpen => turn?.careQuestionOpen ?? false;

  /// Quick and daily: "Did I hear 15 hours of sleep? ... Is that right?" mid check-in.
  bool get checkQuestion => turn?.isCheckQuestion ?? false;

  /// The answers heard so far and not saved yet, in the server's field names.
  Map<String, dynamic> get heardAnswers => turn?.pending ?? const {};

  /// Apple Health's value is offered (quick: in the question; weekly never): label the
  /// buttons "Looks right" ([confirm]) / "Not quite" ([change]).
  bool get confirmingHealth => (turn?.offersHealthValue ?? false) || (confirming && (turn?.fromHealth ?? false));
  bool get canRetry => _retry != null;
  bool get canGoBack => turn != null && (!confirming || finalReadback) && !emergency && (turn!.doneFields.isNotEmpty);
  bool get canHearAgain => voiceUsable && mascotLine.isNotEmpty && !typing && phase != CheckinPhase.interpreting;

  /// "Question N of M" for the open question; the activity's follow-up counts with it.
  (int, int)? get questionNumber {
    final t = turn;
    if (t == null || t.complete) return null;
    final asked = _topicsOf(t.questions);
    final done = _topicsOf(t.doneFields.toList());
    return ((done.length + 1).clamp(1, asked.length), asked.length);
  }

  /// Seconds until the microphone closes by itself, shown only near the end.
  int? get listenSecondsLeft {
    if (phase != CheckinPhase.listening || _listenClock == null) return null;
    final left = listenLimit.inSeconds - _listenedSeconds;
    return left <= 10 ? left : null;
  }

  /// Tap-to-answer choices: the label shown and the words sent (as if said).
  List<(String, String)> get quickAnswers {
    final t = turn;
    if (t == null || t.complete || emergency || correcting || t.phase != 'asking') return const [];
    final held = t.state['held_minutes'] != null;
    return switch (t.currentField) {
      'wellbeing' => const [('Good', 'good'), ('Okay', 'okay'), ('Not great', 'not great')],
      'vigorous_recreation_min' || 'vigorous_recreation_min_week' when held => const [
        ('Out of breath', 'it got me out of breath'),
        ('Easy pace', 'it was all easy'),
        ('A bit of both', 'a bit of both'),
      ],
      'vigorous_recreation_min' || 'moderate_recreation_min' => const [('Nothing', 'no, nothing')],
      'sedentary_min_day' => const [
        ('About 4 hours', 'about 4 hours'),
        ('About 6 hours', 'about 6 hours'),
        ('About 8 hours', 'about 8 hours'),
        ('10 hours or more', 'about 10 hours'),
      ],
      _ => const [],
    };
  }

  void _set(void Function() change) {
    change();
    if (!_disposed) notifyListeners();
  }

  // ---- starting ----------------------------------------------------------

  /// Starts a check-in. For `quick`, the plan comes from the stored days and Apple
  /// Health; it does nothing when there is nothing left to ask today.
  Future<bool> start({String kind = 'quick'}) async {
    if (_busy || phase != CheckinPhase.notStarted) return false;
    if (voiceUsable) _warmUp(); // the token is ready by the time Mochi first speaks
    final now = _clock();
    final today = isoDay(dayOf(now));
    final history = await store.checkins();
    final days = await store.dayLogs();
    QuickPlan? plan;
    if (kind == 'quick') {
      // Once a day: nothing when today's is done or nothing is left to ask.
      plan = scheduler.due(localNow: now, history: history, days: days, health: await _health()).quick;
      if (plan == null) return false;
    }
    this.kind = kind;
    localDate = today;
    final previous = _previous(kind, history, days);
    await _send(() => guide.start(kind: kind, localDate: today, previous: previous, quick: plan).timeout(_turnLimit));
    return turn != null;
  }

  Future<HealthDay> _health() async {
    final read = healthSamples;
    if (read == null) return const HealthDay();
    try {
      return healthDay(await read().timeout(_turnLimit));
    } catch (_) {
      return const HealthDay(); // no Apple Health today: Mochi asks
    }
  }

  /// The last answers, so "same as yesterday" works. History only, never a default.
  static Map<String, dynamic> _previous(String kind, List<CheckinEntry> history, List<DayLog> days) {
    if (kind == 'weekly') {
      return history
          .lastWhere(
            (c) => c.kind == 'weekly',
            orElse: () => const CheckinEntry(kind: '', date: '', answers: {}),
          )
          .answers;
    }
    T? latest<T>(T? Function(DayLog d) pick) {
      for (final d in days.reversed) {
        final v = pick(d);
        if (v != null) return v;
      }
      return null;
    }

    final active = days.reversed.where((d) => d.activityKnown).firstOrNull;
    final feeling = history.reversed.map((c) => c.wellbeing).whereType<String>().firstOrNull;
    if (kind == 'daily') return {'wellbeing': ?feeling};
    return {
      'sleep_hours_last_night': ?latest((d) => d.sleepHours),
      'vigorous_recreation_min': ?active?.vigorousMin,
      'moderate_recreation_min': ?active?.moderateMin,
      'sedentary_min_day': ?latest((d) => d.sedentaryMin),
      'wellbeing': ?feeling,
    };
  }

  // ---- talking -----------------------------------------------------------

  Future<void> startTalk() {
    if (_starting != null) return _starting!;
    if (typing || !voiceUsable || _busy) return Future.value();
    if (phase != CheckinPhase.idle && phase != CheckinPhase.speaking) return Future.value();
    return _starting = _startTalk().whenComplete(() => _starting = null);
  }

  Future<void> _startTalk() async {
    if (phase == CheckinPhase.speaking) {
      _speechGen++;
      await _stopOutput();
    }
    _set(() {
      phase = CheckinPhase.listening;
      caption = '';
      notice = null;
      _retry = null;
    });
    try {
      if (!await input.hasPermission()) throw const MicDeniedException();
      if (phase != CheckinPhase.listening) return;
      await input
          .start((text) {
            if (text != caption) _silentSeconds = 0;
            _set(() => caption = text);
            _armEndOfTurn(text);
          }, onDropped: (_) => _inputDropped())
          .timeout(_micStartLimit);
      if (phase == CheckinPhase.listening) _startListenClock();
    } on MicDeniedException {
      _set(() {
        phase = CheckinPhase.idle;
        typing = true;
        notice = micDeniedNotice;
      });
    } on VoiceUnavailableException {
      _set(() {
        phase = CheckinPhase.idle;
        typing = true;
        _voiceOut();
      });
    } on TimeoutException {
      _set(() {
        phase = CheckinPhase.idle;
        notice = voiceTroubleNotice;
      });
      try {
        await input.cancel().timeout(_quickLimit); // a start that never answered must not leave the mic on
      } catch (_) {}
    } catch (_) {
      _set(() {
        phase = CheckinPhase.idle;
        notice = voiceTroubleNotice;
      });
    }
  }

  /// The connection was lost while listening. The input has already stopped the mic.
  void _inputDropped() {
    if (phase != CheckinPhase.listening) return;
    _stopListenClock();
    _set(() {
      phase = CheckinPhase.idle;
      notice = voiceTroubleNotice;
    });
  }

  void _startListenClock() {
    _listenClock?.cancel();
    _listenedSeconds = 0;
    _silentSeconds = 0;
    _listenClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (phase != CheckinPhase.listening) return _stopListenClock();
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
    _endOfTurnTimer?.cancel();
    _endOfTurnTimer = null;
  }

  /// Every caption (a new partial or final) restarts the end-of-turn wait, once a word is heard.
  void _armEndOfTurn(String text) {
    if (_disposed || text.trim().isEmpty) return;
    _endOfTurnTimer?.cancel();
    _endOfTurnTimer = Timer(endOfTurn, () {
      _endOfTurnTimer = null;
      if (!_disposed && phase == CheckinPhase.listening) unawaited(stopTalk());
    });
  }

  /// Closes the microphone and sends what was heard.
  Future<void> stopTalk() async {
    await _starting;
    if (phase != CheckinPhase.listening) return;
    _stopListenClock();
    _set(() => phase = CheckinPhase.interpreting);
    String text;
    try {
      text = (await input.finish().timeout(_micFinishLimit)).trim();
    } on VoiceUnavailableException {
      _set(() {
        phase = CheckinPhase.idle;
        typing = true;
        _voiceOut();
      });
      return;
    } catch (_) {
      _set(() {
        phase = CheckinPhase.idle;
        notice = voiceTroubleNotice;
      });
      return;
    }
    if (text.isEmpty) {
      _set(() {
        phase = CheckinPhase.idle;
        notice = emptyTranscriptNotice;
      });
      return;
    }
    _set(() => caption = text);
    await _reply(text, fromTranscript: true);
  }

  /// Closes the microphone and drops what was heard.
  Future<void> cancelTalk() async {
    await _starting;
    if (phase != CheckinPhase.listening) return;
    _stopListenClock();
    try {
      await input.cancel().timeout(_quickLimit);
    } catch (_) {}
    _set(() {
      phase = CheckinPhase.idle;
      caption = '';
    });
  }

  // ---- typing and buttons ------------------------------------------------

  Future<void> submitTyped(String text) async {
    final t = text.trim();
    if (t.isEmpty || _busy) return;
    if (phase != CheckinPhase.idle && phase != CheckinPhase.speaking) return;
    await _stopSpeech();
    _set(() => caption = t);
    await _reply(t);
  }

  /// A tapped quick answer: the same words a person would say.
  Future<void> submitQuick(String text) async {
    if (_busy || phase == CheckinPhase.interpreting) return;
    if (phase == CheckinPhase.listening) await cancelTalk();
    await submitTyped(text);
  }

  /// "Yes, that's right" to the read-back (at the end, a check question, or weekly one
  /// answer), or "Looks right" to Apple Health's offered value.
  Future<void> confirm() async {
    if (!confirming && !confirmingHealth) return;
    await _button('confirm');
  }

  /// "No, let me fix it": the next answer is sent as `"no, <answer>"` and replaces the one
  /// read back (at the end: "no, my sleep was 6 hours" changes that answer). Sends nothing.
  Future<void> change() async {
    if (_busy || !(confirming || confirmingHealth) || (phase != CheckinPhase.idle && phase != CheckinPhase.speaking)) {
      return;
    }
    await _stopSpeech();
    _set(() {
      correcting = true;
      notice = null;
    });
  }

  /// Back to Yes / No without changing anything.
  void keepAnswer() => _set(() => correcting = false);

  /// Skips the open question (or Apple Health's read-back). Nothing of it is kept.
  Future<void> skip() => _button('skip');

  /// Reopens the answer before this one. The server understands "go back".
  Future<void> goBack() async {
    if (!canGoBack) return;
    await _button('reply', text: 'go back');
  }

  /// Continue after an emergency pause: the same question or read-back again.
  Future<void> continueAfterEmergency() async {
    if (!emergency) return;
    await _button('resume');
  }

  /// Stops the check-in. Nothing is saved.
  Future<void> cancel() => _button('cancel');

  Future<void> stopSpeaking() => _stopSpeech();

  Future<void> retry() async {
    final r = _retry;
    if (r == null || _busy) return;
    await r();
  }

  Future<void> setTyping(bool value) async {
    if (value == typing || (!value && !voiceUsable)) return;
    if (!value) _warmUp();
    if (value) {
      if (phase == CheckinPhase.listening) await cancelTalk();
      await _stopSpeech();
    }
    _set(() => typing = value);
  }

  Future<void> hearAgain() async {
    if (!canHearAgain) return;
    if (phase == CheckinPhase.listening) await cancelTalk();
    await _speak(mascotLine, replay: output.canReplay);
  }

  // ---- reminders -----------------------------------------------------------

  /// Yes to the reminder offer, at the time the person picked (10:00 by default). This is
  /// when the phone first asks to allow notifications.
  Future<void> acceptReminders({int? hour, int? minute}) async {
    final r = reminders;
    if (r == null || _busy) return;
    _busy = true;
    try {
      final next = await r.accept(
        await store.settings(),
        localNow: _clock(),
        history: await store.checkins(),
        hour: hour,
        minute: minute,
      );
      await store.saveSettings(next);
    } finally {
      _busy = false;
      _set(() => offerReminder = false);
    }
  }

  Future<void> declineReminders() async {
    final r = reminders;
    if (r == null) return;
    await store.saveSettings(r.decline(await store.settings()));
    _set(() => offerReminder = false);
  }

  // ---- server turns ------------------------------------------------------------

  Future<void> _button(String action, {String? text}) async {
    if (_busy || turn == null) return;
    if (phase == CheckinPhase.listening) await cancelTalk();
    if (phase != CheckinPhase.idle && phase != CheckinPhase.speaking && phase != CheckinPhase.done) return;
    if (phase == CheckinPhase.done && action != 'reply') return;
    await _stopSpeech();
    final state = turn!.state;
    await _send(() => guide.turn(action: action, state: state, text: text).timeout(_turnLimit));
  }

  Future<void> _reply(String text, {bool fromTranscript = false}) async {
    if (turn == null) return;
    final state = turn!.state;
    // After "No, let me fix it", a reply is the right answer for the read-back; the
    // server reads "no, <answer>" as a correction.
    final words = (confirming || confirmingHealth) && correcting ? 'no, $text' : text;
    await _send(
      () => guide.turn(action: 'reply', state: state, text: words, fromTranscript: fromTranscript).timeout(_turnLimit),
    );
  }

  Future<void> _send(Future<CheckinTurn> Function() request) async {
    if (_busy) return;
    _busy = true;
    _tryVoiceAgain();
    _set(() {
      phase = CheckinPhase.interpreting;
      notice = null;
      _retry = null;
    });
    final CheckinTurn t;
    try {
      t = await request();
    } on GuideRejected catch (e) {
      _busy = false;
      _set(() {
        phase = turn == null ? CheckinPhase.notStarted : (turn!.complete ? CheckinPhase.done : CheckinPhase.idle);
        notice = e.message;
      });
      return;
    } catch (e) {
      _busy = false;
      _set(() {
        phase = turn == null ? CheckinPhase.notStarted : CheckinPhase.idle;
        notice = e is GuideTooBusy ? e.message : noNetworkNotice;
        _retry = () => _send(request);
      });
      return;
    }
    _set(() {
      if (_voiceBack) _voiceIn();
      correcting = false;
      turn = t;
      emergency = t.emergency;
      mascotLine = t.message;
      phase = t.complete || t.phase == 'cancelled' ? CheckinPhase.done : CheckinPhase.idle;
    });
    if (t.complete) await _finish(t);
    _busy = false;
    if (!typing && voiceUsable && !screenReader) await _speak(t.message);
  }

  /// Saves the finished check-in once, then plans reminders and the progress line.
  Future<void> _finish(CheckinTurn t) async {
    if (_saved) return;
    try {
      await store.applyFinishedCheckin(t.raw, localDate: localDate ?? isoDay(dayOf(_clock())));
      _saved = true;
    } catch (_) {
      _set(() {
        notice = savedNotice;
        _retry = () async {
          await _finish(t);
          if (_saved) _set(() => notice = null);
        };
      });
      return;
    }
    await onFinished?.call(t);
    final history = await store.checkins();
    final settings = await store.settings();
    final r = reminders;
    if (r != null) {
      try {
        if (settings.remindersOn) await r.reschedule(settings, localNow: _clock(), history: history);
      } catch (_) {} // a reminder that can't be planned never blocks the check-in
    }
    _set(() {
      progress = weekProgress(history, localDate!);
      offerReminder = r != null && r.shouldOffer(settings, history);
    });
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

  // ---- speaking ----------------------------------------------------------------

  /// Gets voice ready in the background; any problem shows up when voice is used.
  void _warmUp() => input.warmUp().ignore();

  Future<void> _stopOutput() async {
    try {
      await output.stop().timeout(_quickLimit);
    } catch (_) {}
  }

  Future<void> _stopSpeech() async {
    if (phase == CheckinPhase.speaking) {
      _speechGen++;
      await _stopOutput();
      _set(() => phase = _restingPhase);
    }
  }

  CheckinPhase get _restingPhase =>
      (turn?.complete ?? false) || turn?.phase == 'cancelled' ? CheckinPhase.done : CheckinPhase.idle;

  Future<void> _speak(String line, {bool replay = false}) async {
    final gen = ++_speechGen;
    _set(() => phase = CheckinPhase.speaking);
    try {
      await (replay ? output.replay() : output.speak(spokenText(line))).timeout(_speakLimit);
    } on VoiceUnavailableException {
      if (gen == _speechGen) {
        _set(() {
          typing = true;
          _voiceOut();
        });
      }
    } catch (_) {
      if (gen == _speechGen) _set(() => notice = speakTroubleNotice);
    }
    if (gen == _speechGen && phase == CheckinPhase.speaking) _set(() => phase = _restingPhase);
  }

  static Set<String> _topicsOf(List<String> fields) => {
    for (final f in fields)
      switch (f) {
        'moderate_recreation_min' => 'vigorous_recreation_min',
        'moderate_recreation_min_week' => 'vigorous_recreation_min_week',
        'diastolic_bp' => 'systolic_bp',
        _ => f,
      },
  };

  @override
  void dispose() {
    _disposed = true;
    _stopListenClock();
    if (ownsSpeech) {
      input.dispose();
      output.dispose();
    } else {
      // The shared input and output stay alive for the next check-in, but this one's listen
      // (and its socket) and its speech end with it.
      if (phase == CheckinPhase.listening || _starting != null) input.cancel().ignore();
      if (phase == CheckinPhase.speaking) output.stop().ignore();
    }
    super.dispose();
  }
}
