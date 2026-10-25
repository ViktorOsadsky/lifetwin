// Quick and daily check-ins read every answer back once, at the end (owner audit,
// 2026-10). Spoken, typed and tapped answers are heard alike; only the final yes saves.
// The fake below answers in the server's own shapes (see contracts/fixtures/cases.json).
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_client.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/voice/fakes.dart';

const questions = ['sleep_hours_last_night', 'sedentary_min_day'];

Map<String, dynamic> raw(Map<String, dynamic> state, String message, {bool complete = false}) => {
  'message': message,
  'complete': complete,
  'emergency': false,
  'mascot_events': [
    {'state': 'asking', 'caption': message},
  ],
  'daily_logs': [
    if (complete)
      {
        'date': '2026-10-24',
        'sleep_hours': (state['confirmed'] as Map)['sleep_hours_last_night'],
        'vigorous_recreation_min': null,
        'moderate_recreation_min': null,
        'sedentary_min_day': null,
      },
  ],
  'profile_update': {},
  'state': state,
};

Map<String, dynamic> state(
  String phase,
  String? field, {
  Map<String, dynamic> pending = const {},
  Map<String, dynamic> confirmed = const {},
  Map<String, dynamic> suggested = const {},
  bool fromHealth = false,
}) => {
  'kind': 'quick',
  'phase': phase,
  'questions': questions,
  'current_field': field,
  'pending': pending,
  'confirmed': confirmed,
  'suggested': suggested,
  'from_health': fromHealth,
  'checking': <String>[],
  'skipped_fields': <String>[],
  'local_date': '2026-10-24',
  'activity_day': 'yesterday',
};

class SingleReadbackGuide implements CheckinGuide {
  final calls = <(String, String?)>[];
  bool health = false;

  @override
  Future<CheckinTurn> start({
    required String kind,
    required String localDate,
    Map<String, dynamic> previous = const {},
    QuickPlan? quick,
  }) async => CheckinTurn(
    health
        ? raw(
            state('asking', questions.first, suggested: {'sleep_hours_last_night': 7.5}, fromHealth: true),
            'Apple Health says you slept about 7.5 hours last night. Does that sound right?',
          )
        : raw(state('asking', questions.first), 'How did you sleep last night?'),
  );

  @override
  Future<CheckinTurn> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  }) async {
    calls.add((action, text));
    final heard = Map<String, dynamic>.from(state['pending'] as Map);
    if (action == 'confirm' && state['phase'] == 'confirming') {
      return CheckinTurn(raw(_state('ready', null, confirmed: heard), 'All saved.', complete: true));
    }
    final field = state['current_field'] as String;
    heard[field] = action == 'confirm' ? 7.5 : int.parse(RegExp(r'\d+').firstMatch(text!)!.group(0)!);
    final next = questions.where((q) => !heard.containsKey(q)).firstOrNull;
    if (next == null) {
      return CheckinTurn(raw(_state('confirming', null, pending: heard), "Before I save anything... Is that right?"));
    }
    return CheckinTurn(raw(_state('asking', next, pending: heard), 'Got it. How many hours did you sit?'));
  }

  Map<String, dynamic> _state(
    String phase,
    String? field, {
    Map<String, dynamic> pending = const {},
    Map<String, dynamic> confirmed = const {},
  }) => state(phase, field, pending: pending, confirmed: confirmed);
}

void main() {
  late SingleReadbackGuide guide;
  late InMemoryCheckinStore store;
  CheckinController make() => CheckinController(
    guide: guide,
    input: FakeSpeechInput(),
    output: FakeSpeechOutput(),
    store: store,
    clock: () => DateTime(2026, 10, 24, 10),
    voiceUsable: false,
  );

  setUp(() {
    guide = SingleReadbackGuide();
    store = InMemoryCheckinStore(
      checkins: [const CheckinEntry(kind: 'quick', date: '2026-10-23', answers: {})],
    );
  });

  test('typed and tapped answers are heard without a read-back each; one read-back saves all', () async {
    final c = make();
    await c.start();
    await c.submitTyped('7 hours');
    expect(c.confirming, isFalse); // no per-answer "Is that right?"
    expect(c.heardAnswers, {'sleep_hours_last_night': 7});
    expect(c.questionNumber, (2, 2));
    expect(c.canGoBack, isTrue);
    await c.submitQuick('about 6 hours'); // a tapped answer, the same way
    expect(c.finalReadback, isTrue);
    expect(c.checkQuestion, isFalse);
    expect(c.confirming, isTrue);
    expect(c.canGoBack, isTrue); // "go back" still works at the end
    expect(store.writes, 0);
    await c.confirm();
    expect(guide.calls.last.$1, 'confirm');
    expect(c.phase, CheckinPhase.done);
    expect(store.writes, 1);
  });

  test('a correction at the end is sent as "no, ..."', () async {
    final c = make();
    await c.start();
    await c.submitTyped('7 hours');
    await c.submitTyped('6 hours');
    await c.change();
    expect(c.correcting, isTrue);
    guide.calls.clear();
    try {
      await c.submitTyped('my sleep was 5 hours');
    } catch (_) {}
    expect(guide.calls.single, ('reply', 'no, my sleep was 5 hours'));
  });

  test("Apple Health's offered value: Looks right is the confirm action, and is only heard", () async {
    guide.health = true;
    final c = make();
    await c.start();
    expect(c.confirmingHealth, isTrue);
    expect(c.confirming, isFalse);
    await c.confirm();
    expect(guide.calls.single.$1, 'confirm');
    expect(c.heardAnswers, {'sleep_hours_last_night': 7.5});
    expect(store.writes, 0);
  });
}
