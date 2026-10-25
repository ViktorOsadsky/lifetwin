import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_client.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart' show voiceOffNotice;
import 'package:lifesim/voice/speech.dart';

/// A scripted quick check-in: sleep, then sitting, read back each, then done.
class FakeCheckinGuide implements CheckinGuide {
  final calls = <Map<String, dynamic>>[];
  bool failNext = false;
  String? rejectNext;
  Completer<void>? gate;

  static const questions = ['sleep_hours_last_night', 'sedentary_min_day'];

  @override
  Future<CheckinTurn> start({
    required String kind,
    required String localDate,
    Map<String, dynamic> previous = const {},
    QuickPlan? quick,
  }) async {
    calls.add({
      'action': 'start',
      'kind': kind,
      'local_date': localDate,
      'previous': previous,
      'quick': quick?.toJson(),
    });
    await _wait();
    final suggested = quick?.suggestedSleepLastNight;
    if (suggested != null) {
      return _turn(
        'confirming',
        'Apple Health says you slept about $suggested hours last night. Looks right?',
        field: questions.first,
        pending: {'sleep_hours_last_night': suggested},
        fromHealth: true,
      );
    }
    return _turn('asking', 'How did you sleep last night?', field: questions.first);
  }

  @override
  Future<CheckinTurn> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  }) async {
    calls.add({'action': action, 'text': text, 'fromTranscript': fromTranscript, 'state': state});
    await _wait();
    final field = state['current_field'] as String?;
    final confirmed = Map<String, dynamic>.from(state['confirmed'] as Map? ?? {});
    final pending = Map<String, dynamic>.from(state['pending'] as Map? ?? {});
    final skipped = {for (final f in state['skipped_fields'] as List? ?? const []) '$f'};
    if (action == 'reply' && text != null && text.contains("can't breathe")) {
      return CheckinTurn({...emergencyTurn, 'state': state});
    }
    switch (action) {
      case 'resume':
        return _turn(
          state['phase'] as String,
          "Okay, let's carry on. How did you sleep last night?",
          field: field,
          confirmed: confirmed,
          pending: pending,
        );
      case 'cancel':
        return _turn('cancelled', 'We can stop here. Nothing was saved.', field: null);
      case 'skip':
        return _next(confirmed, {...skipped, field!});
      case 'confirm':
        return _next({...confirmed, ...pending}, skipped);
      case 'reply' when text == 'go back':
        return _turn('asking', "Okay, let's go back to your sleep.", field: questions.first, confirmed: confirmed);
      case 'reply' when state['phase'] == 'confirming' && text == 'yes':
        return _next({...confirmed, ...pending}, skipped);
      case 'reply':
        final value = int.tryParse(RegExp(r'\d+').firstMatch(text ?? '')?.group(0) ?? '');
        if (value == null) return _turn('asking', "Sorry, I didn't catch that.", field: field, confirmed: confirmed);
        final values = field == 'sedentary_min_day' ? {field!: value * 60} : {field!: value};
        return _turn(
          'confirming',
          'I heard $text. Is that right?',
          field: field,
          confirmed: confirmed,
          pending: values,
        );
    }
    throw StateError(action);
  }

  Future<void> _wait() async {
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw const GuideFailure('offline');
    }
    if (rejectNext case final reason?) {
      rejectNext = null;
      throw GuideRejected(reason);
    }
  }

  CheckinTurn _next(Map<String, dynamic> confirmed, Set<String> skipped) {
    final next = questions.where((q) => !confirmed.containsKey(q) && !skipped.contains(q)).firstOrNull;
    if (next == null) {
      return CheckinTurn({
        ..._raw('ready', "Got it. That's all. Thank you for checking in with me!", null, confirmed, {}),
        'complete': true,
        'daily_logs': [
          if (confirmed['sedentary_min_day'] != null)
            {
              'date': '2026-10-23',
              'sleep_hours': null,
              'vigorous_recreation_min': null,
              'moderate_recreation_min': null,
              'sedentary_min_day': confirmed['sedentary_min_day'],
            },
          if (confirmed['sleep_hours_last_night'] != null)
            {
              'date': '2026-10-24',
              'sleep_hours': confirmed['sleep_hours_last_night'],
              'vigorous_recreation_min': null,
              'moderate_recreation_min': null,
              'sedentary_min_day': null,
            },
        ],
      });
    }
    return _turn(
      'asking',
      'Got it. About how many hours did you spend sitting yesterday?',
      field: next,
      confirmed: confirmed,
      skipped: skipped,
    );
  }

  CheckinTurn _turn(
    String phase,
    String message, {
    String? field,
    Map<String, dynamic> confirmed = const {},
    Map<String, dynamic> pending = const {},
    bool fromHealth = false,
    Set<String> skipped = const {},
  }) => CheckinTurn(_raw(phase, message, field, confirmed, pending, fromHealth: fromHealth, skipped: skipped));

  static Map<String, dynamic> _raw(
    String phase,
    String message,
    String? field,
    Map<String, dynamic> confirmed,
    Map<String, dynamic> pending, {
    bool fromHealth = false,
    Set<String> skipped = const {},
  }) => {
    'message': message,
    'complete': false,
    'emergency': false,
    'mascot_events': [
      {'state': phase == 'ready' ? 'celebrating' : 'asking', 'caption': message},
    ],
    'daily_logs': [],
    'profile_update': {},
    'state': {
      'kind': 'quick',
      'phase': phase,
      'questions': questions,
      'current_field': field,
      'confirmed': confirmed,
      'pending': pending,
      'skipped_fields': [...skipped],
      'from_health': fromHealth,
      'local_date': '2026-10-24',
      'activity_day': 'yesterday',
    },
  };

  static const emergencyTurn = {
    'message': "I'm sorry you're going through that. If you need help right now, please call 911. We can carry on whenever you're ready.",
    'complete': false,
    'emergency': true,
    'mascot_events': [
      {'state': 'concerned', 'caption': '...'},
    ],
    'daily_logs': [],
    'profile_update': {},
  };
}

class FakePort implements NotificationPort {
  bool allow = true;
  int asks = 0;
  final scheduled = <DateTime>[];
  @override
  Future<bool> requestPermission() async {
    asks++;
    return allow;
  }

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime localWallTime,
    required String title,
    required String body,
  }) async => scheduled.add(localWallTime);

  @override
  Future<void> cancelAll() async => scheduled.clear();
}

void main() {
  late FakeCheckinGuide guide;
  late FakeSpeechInput input;
  late FakeSpeechOutput output;
  late InMemoryCheckinStore store;
  late FakePort port;
  final now = DateTime(2026, 10, 24, 10);

  CheckinController make({bool voice = true, Future<List<HealthSample>> Function()? health}) => CheckinController(
    guide: guide,
    input: input,
    output: output,
    store: store,
    reminders: CheckinReminders(port),
    healthSamples: health,
    clock: () => now,
    voiceUsable: voice,
  );

  setUp(() {
    guide = FakeCheckinGuide();
    input = FakeSpeechInput();
    output = FakeSpeechOutput();
    store = InMemoryCheckinStore(
      checkins: [const CheckinEntry(kind: 'quick', date: '2026-10-23', answers: {})],
    );
    port = FakePort();
  });

  test('a controller that does not own the shared speech input leaves it alive for the next check-in', () async {
    CheckinController shared() => CheckinController(
      guide: guide,
      input: input,
      output: output,
      ownsSpeech: false,
      store: store,
      clock: () => now,
    );
    final first = shared();
    expect(await first.start(), isTrue);
    first.dispose();
    expect(input.disposals, 0);
    final second = shared();
    expect(await second.start(), isTrue);
    expect(second.mascotLine, 'How did you sleep last night?');
    second.dispose();
    expect(input.disposals, 0);
    make().dispose();
    expect(input.disposals, 1, reason: 'an owner still disposes its own input');
  });

  test('starts with a plan from the stored days and speaks the question', () async {
    final c = make();
    expect(await c.start(), isTrue);
    final sent = guide.calls.single;
    expect(sent['kind'], 'quick');
    expect(sent['local_date'], '2026-10-24');
    expect((sent['quick'] as Map)['activity_day'], 'yesterday');
    expect(c.mascotLine, 'How did you sleep last night?');
    expect(output.spoken.single, 'How did you sleep last night?');
    expect(c.phase, CheckinPhase.idle);
  });

  test('a whole check-in by voice: answers are saved only when it finishes', () async {
    final c = make();
    await c.start();
    input.transcript = '7 hours';
    await c.startTalk();
    await c.stopTalk();
    expect(guide.calls.last['fromTranscript'], isTrue);
    expect(c.confirming, isTrue);
    expect(store.writes, 0);
    await c.confirm();
    input.transcript = 'about 6';
    await c.startTalk();
    await c.stopTalk();
    expect(store.writes, 0); // nothing saved during the check-in
    await c.confirm();
    expect(c.phase, CheckinPhase.done);
    expect(store.writes, 1);
    final saved = await store.dayLogs();
    expect(saved.map((d) => d.toJson()), [
      {'date': '2026-10-23', 'sedentary_min_day': 360},
      {'date': '2026-10-24', 'sleep_hours': 7},
    ]);
    final record = (await store.checkins()).last;
    expect(record.kind, 'quick');
    expect(record.answers, {'sleep_hours_last_night': 7, 'sedentary_min_day': 360});
  });

  test('typing works the same, and quick answers send the words a person would say', () async {
    final c = make(voice: false);
    await c.start();
    expect(output.spoken, isEmpty);
    await c.submitTyped('8 hours');
    await c.confirm();
    expect(c.turn!.currentField, 'sedentary_min_day');
    expect(c.quickAnswers.map((a) => a.$1), contains('About 6 hours'));
    await c.submitQuick('about 6 hours');
    expect(guide.calls.last['text'], 'about 6 hours');
  });

  test('a tap while waiting for the server does nothing', () async {
    final c = make(voice: false);
    await c.start();
    guide.gate = Completer<void>();
    final first = c.submitTyped('7 hours');
    await c.submitTyped('7 hours');
    await c.skip();
    await c.confirm();
    guide.gate!.complete();
    await first;
    expect(guide.calls.where((call) => call['action'] != 'start'), hasLength(1));
  });

  test('confirm is ignored unless something is read back, and a second save never happens', () async {
    final c = make(voice: false);
    await c.start();
    await c.confirm();
    expect(guide.calls, hasLength(1));
    await c.submitTyped('7');
    await c.confirm();
    await c.skip();
    expect(c.phase, CheckinPhase.done);
    await c.confirm();
    await c.skip();
    expect(store.writes, 1);
  });

  test('Change sends the new answer as a correction', () async {
    final c = make(voice: false);
    await c.start();
    await c.submitTyped('7 hours');
    await c.change();
    expect(c.correcting, isTrue);
    await c.submitTyped('6 hours');
    expect(guide.calls.last['text'], 'no, 6 hours');
    expect(c.correcting, isFalse);
  });

  test('Skip and Go back', () async {
    final c = make(voice: false);
    await c.start();
    expect(c.canGoBack, isFalse);
    await c.skip();
    expect(guide.calls.last['action'], 'skip');
    expect(c.canGoBack, isTrue);
    await c.goBack();
    expect(guide.calls.last['text'], 'go back');
  });

  test('an emergency pauses: concerned Mochi, Call 911, and Continue resumes', () async {
    final c = make(voice: false);
    await c.start();
    await c.submitTyped("I can't breathe");
    expect(c.emergency, isTrue);
    expect(c.turn!.mascotState, 'concerned');
    expect(c.mascotLine, contains('If you need help right now, please call 911'));
    expect(emergencyCallUri.toString(), 'tel:911');
    expect(c.quickAnswers, isEmpty);
    expect(store.writes, 0);
    await c.continueAfterEmergency();
    expect(guide.calls.last['action'], 'resume');
    expect(c.emergency, isFalse);
  });

  test('no network keeps the state and Try again repeats the request', () async {
    final c = make(voice: false);
    await c.start();
    guide.failNext = true;
    await c.submitTyped('7 hours');
    expect(c.notice, contains("can't reach LifeTwin"));
    expect(c.canRetry, isTrue);
    await c.retry();
    expect(c.confirming, isTrue);
    expect(guide.calls.last['text'], '7 hours');
  });

  test("the server's refusal is shown in its own words", () async {
    final c = make(voice: false);
    await c.start();
    guide.rejectNext = 'Please answer yes or no to what I just read back first.';
    await c.skip();
    expect(c.notice, 'Please answer yes or no to what I just read back first.');
    expect(c.canRetry, isFalse);
  });

  test('cancel saves nothing', () async {
    final c = make(voice: false);
    await c.start();
    await c.submitTyped('7');
    await c.cancel();
    expect(c.phase, CheckinPhase.done);
    expect(store.writes, 0);
  });

  test('nothing to ask means no check-in', () async {
    store = InMemoryCheckinStore(
      checkins: [const CheckinEntry(kind: 'quick', date: '2026-10-24', answers: {})],
    );
    expect(await make().start(), isFalse);
    expect(guide.calls, isEmpty);
  });

  test('Apple Health sleep comes as a read-back, and still needs the yes', () async {
    final samples = [
      HealthSample(type: 'SLEEP_ASLEEP', start: DateTime(2026, 10, 23, 23), end: DateTime(2026, 10, 24, 6, 30)),
    ];
    final c = make(voice: false, health: () async => samples);
    await c.start();
    expect((guide.calls.single['quick'] as Map)['suggested'], {'sleep_hours_last_night': 7.5});
    expect(c.confirmingHealth, isTrue);
    expect(store.writes, 0);
  });

  test('Apple Health trouble just means Mochi asks', () async {
    final c = make(voice: false, health: () async => throw Exception('no access'));
    await c.start();
    expect((guide.calls.single['quick'] as Map)['suggested'], isEmpty);
  });

  test('reminders are offered once, after the first finished check-in, and permission is asked only on yes', () async {
    store = InMemoryCheckinStore();
    final c = make(voice: false);
    await c.start();
    expect(c.offerReminder, isFalse);
    await c.submitTyped('7');
    await c.confirm();
    await c.skip();
    expect(c.phase, CheckinPhase.done);
    expect(c.offerReminder, isTrue);
    expect(port.asks, 0);
    await c.acceptReminders(hour: 9, minute: 30);
    expect(port.asks, 1);
    final settings = await store.settings();
    expect(settings.remindersOn, isTrue);
    expect((settings.reminderHour, settings.reminderMinute), (9, 30));
    expect(port.scheduled.first, DateTime(2026, 10, 25, 9, 30)); // today is done
    expect(c.progress!.daysThisWeek, 1);
  });

  test('"Not now" is remembered', () async {
    store = InMemoryCheckinStore();
    final c = make(voice: false);
    await c.start();
    await c.skip();
    await c.skip();
    await c.declineReminders();
    expect((await store.settings()).reminderOffered, isTrue);
    expect(port.asks, 0);
  });

  test('after a 503, voice comes back on the next turn once a token is minted', () async {
    final c = make();
    await c.start();
    input.startError = const VoiceUnavailableException();
    input.warmUpError = const VoiceUnavailableException();
    await c.startTalk();
    expect(c.voiceUsable, isFalse);
    expect(c.notice, voiceOffNotice);
    input.startError = null;
    input.warmUpError = null;
    await c.submitTyped('7'); // the retry during this turn succeeds
    expect(c.voiceUsable, isTrue);
    expect(c.typing, isFalse);
  });

  test('a check-in that does not own the shared input still cancels its listen on dispose', () async {
    final c = CheckinController(
      guide: guide,
      input: input,
      output: output,
      ownsSpeech: false,
      store: store,
      clock: () => now,
      voiceUsable: true,
    );
    await c.start();
    await c.startTalk();
    expect(c.phase, CheckinPhase.listening);
    c.dispose();
    expect(input.cancels, 1);
    expect(input.disposals, 0, reason: 'the shared input stays alive');
  });

  test('microphone refused: typing instead', () async {
    final c = make();
    await c.start();
    input.permission = Completer<bool>()..complete(false);
    await c.startTalk();
    expect(c.typing, isTrue);
    expect(c.notice, contains("can't use the microphone"));
  });

  test('an empty transcript asks again and sends nothing', () async {
    final c = make();
    await c.start();
    input.transcript = '  ';
    await c.startTalk();
    await c.stopTalk();
    expect(guide.calls, hasLength(1));
    expect(c.notice, contains("didn't hear anything"));
  });

  test('question numbers count the activity follow-up with its question', () async {
    final c = make(voice: false);
    await c.start();
    expect(c.questionNumber, (1, 2));
    await c.skip();
    expect(c.questionNumber, (2, 2));
  });
}
