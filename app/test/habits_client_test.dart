import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/habits/habit.dart';
import 'package:lifesim/habits/habits_client.dart';
import 'package:lifesim/voice/api_base.dart';

const active = Habit(
  id: 'walk_after_lunch-20261020',
  catalogId: 'walk_after_lunch',
  pillar: 'move',
  anchor: 'After lunch',
  tinyAction: 'walk for 2 minutes outside',
  source: 'said',
  status: HabitStatus.active,
  startedOn: '2026-10-20',
);

Map<String, Object?> reply(Map<String, Object?> extra) => {
  'schema_version': '1.0',
  'message': 'ok',
  'mood': 'happy',
  'emergency': false,
  'safety': null,
  'limitations': <String>[],
  ...extra,
};

void main() {
  late Map<String, dynamic> sent;
  late Uri sentTo;

  HttpHabitsClient client(Object? body, [int status = 200]) => HttpHabitsClient(
    base: ApiBase('http://x'),
    client: MockClient((req) async {
      sentTo = req.url;
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
    }),
  );

  test('propose sends only the lever fields, and own words only with consent', () async {
    final c = client(reply({'status': 'proposed', 'proposal': active.copyWith(status: HabitStatus.proposed).toJson()}));
    final r = await c.propose(
      age: 45,
      today: '2026-10-24',
      habits: const [],
      profile: {'smoking_status': 'never', 'weight_kg': 80, 'sleep_hours': 6, 'name': 'Ann'},
      ownWords: ['tired'],
    );
    expect(sentTo.path, '/api/habits/propose');
    expect(sent['profile'], {'smoking_status': 'never', 'sleep_hours': 6});
    expect(sent.containsKey('own_words'), isFalse);
    expect(sent.containsKey('sitting_minutes_daily'), isFalse);
    expect(r.habit!.status, HabitStatus.proposed);
    await c.propose(
      age: 45,
      today: '2026-10-24',
      habits: const [],
      ownWords: List.filled(9, 'tired'),
      memoryConsent: true,
    );
    expect((sent['own_words'] as List).length, 5);
    expect(sent['memory_consent'], isTrue);
  });

  test('update and question send the records and action', () async {
    final c = client(reply({'status': 'answered', 'habit_id': active.id, 'result': 'not_today'}));
    final r = await c.question(
      age: 40,
      today: '2026-10-24',
      habits: const [active],
      action: HabitQuestionAction.reply,
      habitId: active.id,
      text: 'not today',
    );
    expect(sent['habits'], [active.toJson()]);
    expect(sent['action'], 'reply');
    expect(r.result, HabitResult.notToday);
    await c.update(age: 40, today: '2026-10-24', habits: const [active], action: HabitAction.edit, habitId: active.id, anchor: 'After tea');
    expect(sentTo.path, '/api/habits/update');
    expect(sent['anchor'], 'After tea');
    expect(sent.containsKey('tiny_action'), isFalse);
  });

  test('a skipped answer is unknown, not "not today"', () async {
    final r = await client(reply({'status': 'skipped', 'habit_id': active.id, 'result': null})).question(
      age: 40,
      today: '2026-10-24',
      habits: const [active],
      action: HabitQuestionAction.skip,
      habitId: active.id,
    );
    expect(r.result, isNull);
  });

  test('week sends at most 400 days, the most recent', () async {
    final results = {
      for (var i = 0; i < 450; i++)
        DateTime.utc(2025, 1, 1).add(Duration(days: i)).toIso8601String().substring(0, 10): HabitResult.done,
    };
    await client(reply({'status': 'ok', 'habit_id': active.id})).week(
      age: 40,
      today: '2026-10-24',
      habit: active,
      results: results,
    );
    final days = (sent['results'] as Map).keys.toList()..sort();
    expect(days.length, 400);
    expect(days.first, '2025-02-20');
  });

  test('under 18 and safety replies come through for the app to show', () async {
    final teen = await client(reply({'status': 'age_not_supported', 'proposal': null, 'mood': 'cozy'})).propose(
      age: 16,
      today: '2026-10-24',
      habits: const [],
    );
    expect(teen.ageNotSupported, isTrue);
    expect(teen.habit, isNull);
    final urgent = await client(
      reply({'status': 'safety', 'safety': 'emergency', 'emergency': true, 'mood': 'concerned'}),
    ).propose(age: 40, today: '2026-10-24', habits: const [], ownWords: ['help'], memoryConsent: true);
    expect(urgent.emergency, isTrue);
  });

  test('errors carry the plain server message; junk bodies fail cleanly', () async {
    await expectLater(
      client({'code': 'invalid_request', 'message': 'Please check these answers: date.'}, 422).week(
        age: 40,
        today: '2026-10-24',
        habit: active,
        results: const {},
      ),
      throwsA(isA<HabitsFailure>().having((e) => e.plain, 'plain', 'Please check these answers: date.')),
    );
    for (final junk in [<String, Object?>{}, 'text', reply({'status': 'proposed', 'proposal': {'id': 1}})]) {
      await expectLater(
        client(junk).propose(age: 40, today: '2026-10-24', habits: const []),
        throwsA(isA<HabitsFailure>()),
      );
    }
  });
}
