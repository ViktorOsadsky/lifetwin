import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/experiment/recommendations.dart';
import 'package:lifesim/twin/twin_experiment.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/voice/api_base.dart';

/// One item as the server sends it (server/lifetwin/onboarding/models.py `Recommendation`).
Map<String, dynamic> item(String id, {Object? lever, Object? target, String message = 'A short walk helps.'}) => {
  'id': id,
  'lever': 'moderate_plus_90',
  'title': 'A small start',
  'message': message,
  'based_on': ['moderate_recreation_min_week'],
  'wellness_card': 'activity',
  'source_title': 'CDC: Physical activity for adults',
  'source_url': 'https://www.cdc.gov/physical-activity-basics/guidelines/adults.html',
  'effect': 'some',
  'effect_note': 'Modeled difference for people like you, not a promise.',
  'experiment_lever': lever,
  'experiment_target': target,
  'why_short': 'Moving a little more is good for everyone.',
  'source_domain': 'cdc.gov',
  'causal_interpretation': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());
  late TwinRepository repo;
  setUp(() async {
    repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => DateTime(2026, 10, 26, 9, 30),
    );
  });
  tearDown(() => repo.dispose());

  HttpRecommendations source(http.Client client) =>
      HttpRecommendations(repo, base: ApiBase('http://test'), client: client);

  group('Recommendation.fromJson', () {
    test('reads the server shape into the fields the Ideas screen uses', () {
      final r = Recommendation.fromJson(item('activity', lever: 'moderate_recreation_min_week', target: 120));
      expect(r.id, 'activity');
      expect(r.tip, 'A short walk helps.');
      expect(r.wellnessCardId, 'activity');
      expect(r.leverId, LeverId.moderate);
      expect(r.leverValue, 120);
      expect(r.whyShort, 'Moving a little more is good for everyone.');
      expect(r.effect, 'some');
      expect(r.sourceDomain, 'cdc.gov');
      expect(r.habitNoteQuote, isNull);
    });

    test('a missing current value keeps the lever but never presets 0', () {
      final r = Recommendation.fromJson(item('sleep', lever: 'sleep_hours', target: null));
      expect(r.leverId, LeverId.sleepHours);
      expect(r.leverValue, isNull);
    });

    test('smoking "former" maps to the app code for quit', () {
      final r = Recommendation.fromJson(item('quit_smoking', lever: 'smoking_status', target: 'former'));
      expect(r.leverId, LeverId.smoking);
      expect(r.leverValue, 1);
    });

    test('an unknown lever or no lever opens nothing', () {
      expect(Recommendation.fromJson(item('x', lever: 'weight_kg', target: 60)).leverId, isNull);
      expect(Recommendation.fromJson(item('x', lever: 'something_new', target: 3)).leverValue, isNull);
      expect(Recommendation.fromJson(item('keep_it_up')).leverId, isNull);
    });

    test('a broken item is rejected, not shown half-empty', () {
      expect(() => Recommendation.fromJson({...item('x'), 'title': null}), throwsFormatException);
    });
  });

  group('HttpRecommendations', () {
    test('posts only fields the server accepts and returns at most 3 ideas', () async {
      await repo.saveConversationProfile({'age': 66, 'sleep_hours': 6, 'general_health': 3});
      late Map<String, dynamic> sent;
      final ideas = await source(
        MockClient((req) async {
          expect(req.url.toString(), 'http://test/api/recommendations');
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'status': 'ok',
              'recommendations': [
                for (final id in ['a', 'b', 'c', 'd']) item(id, lever: 'sleep_hours', target: 7),
              ],
            }),
            200,
          );
        }),
      ).load();
      expect(sent.keys.toSet(), {'profile', 'habit_notes', 'outside_ai_consent'});
      expect(sent['profile'], {'age': 66, 'sleep_hours': 6, 'general_health': 'good'});
      expect(sent['habit_notes'], isEmpty, reason: 'no notes leave the phone without memory consent');
      expect(sent['outside_ai_consent'], isEmpty);
      expect(ideas.map((i) => i.id), ['a', 'b', 'c']);
    });

    test('a supplement suggestion is never shown', () async {
      final ideas = await source(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'recommendations': [
                item('a', message: 'Try a vitamin D supplement.'),
                item('b', message: 'A pre-workout drink gives energy.'),
                item('c'),
              ],
            }),
            200,
          ),
        ),
      ).load();
      expect(ideas.map((i) => i.id), ['c']);
    });

    for (final code in [422, 429, 503]) {
      test('HTTP $code is a RecommendationsFailure with the code', () async {
        final load = source(MockClient((_) async => http.Response('{}', code))).load();
        await expectLater(load, throwsA(isA<RecommendationsFailure>().having((f) => f.statusCode, 'code', code)));
      });
    }

    test('a garbled body or network error is a failure without a code', () async {
      await expectLater(
        source(MockClient((_) async => http.Response('not json', 200))).load(),
        throwsA(isA<RecommendationsFailure>().having((f) => f.statusCode, 'code', isNull)),
      );
      await expectLater(
        source(MockClient((_) async => throw http.ClientException('down'))).load(),
        throwsA(isA<RecommendationsFailure>()),
      );
    });
  });
}
