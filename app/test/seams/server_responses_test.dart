// Seam: what the app does with what the server really SAYS.
//
// Inputs are real in-process server responses (test/fixtures/seam_flow.json, written by
// server/tests/make_seam_fixture.py, which fails its own drift test when the server moves).
// Nothing is typed in by hand except the failures the network adds (422/429/503/timeout
// statuses), whose bodies are the server's real error bodies from the same file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/checkin/change_chat.dart';
import 'package:lifesim/checkin/checkin_client.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/checkin/consent_screens.dart';
import 'package:lifesim/checkin/consents.dart';
import 'package:lifesim/documents/document_extract.dart';
import 'package:lifesim/experiment/recommendations.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart' show noNetworkNotice;
import 'package:lifesim/twin/twin_checkin_store.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/http_conversation_guide.dart';
import 'package:lifesim/wellness/coach_client.dart';
import 'package:lifesim/wellness/coach_context.dart';
import 'package:lifesim/wellness/daily_plan_screen.dart';

import '../wellness/screens_test.dart' show phone, reveal;

Map<String, dynamic> load(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
final Map<String, dynamic> seam = load('test/fixtures/seam_flow.json');
final Map<String, dynamic> merged = load('test/fixtures/merged_flow.json');

Map<String, dynamic> copy(Object? j) => Map<String, dynamic>.from(jsonDecode(jsonEncode(j)) as Map);
Map<String, dynamic> at(String a, [String? b]) =>
    copy(b == null ? seam[a] : (seam[a] as Map)[b]);

/// The server will add fields: put an unknown one into every object, at every depth.
Object? withExtras(Object? j) {
  if (j is Map) {
    return {
      for (final e in j.entries) e.key: withExtras(e.value),
      'zz_future_field': {'nested': [1, null, 'x']},
    };
  }
  if (j is List) return [for (final v in j) withExtras(v)];
  return j;
}

Map<String, dynamic> extras(Map<String, dynamic> j) => Map<String, dynamic>.from(withExtras(j) as Map);

class FakePort implements NotificationPort {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime localWallTime,
    required String title,
    required String body,
  }) async {}
  @override
  Future<void> cancelAll() async {}
}

/// An HTTP client that answers from a script: a Response, or an Exception to throw.
class Script {
  Script(this.steps);
  final List<Object> steps;
  int calls = 0;
  late final http.Client client = MockClient((request) async {
    calls++;
    final step = steps.removeAt(0);
    if (step is http.Response) return step;
    throw step;
  });
}

http.Response ok(Object? body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
http.Response failure(int status) =>
    http.Response.bytes(utf8.encode(jsonEncode((seam['errors'] as Map)['$status'])), status);
const bareStatuses = {422, 429, 503};

/// Scrolls up to the error card at the top of the plan page.
Future<void> up(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(finder, -200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. real server output parses through the Dart models', () {
    test('check-in turns: every kind, with the care reply, nulls and unknown fields', () {
      final turns = <Map<String, dynamic>>[
        for (final k in ['daily', 'weekly']) copy(merged[k]),
        for (final q in merged['quick_week'] as List) copy(q),
        at('daily'),
        for (final t in seam['weekly_care_turns'] as List) copy(t),
      ];
      var careOpen = 0;
      for (final raw in turns) {
        for (final json in [raw, extras(raw)]) {
          final t = CheckinTurn.parse(json);
          expect(t.message, raw['message']);
          expect(t.complete, raw['complete']);
          expect(t.emergency, raw['emergency']);
          expect(t.kind, (raw['state'] as Map)['kind']);
          expect(t.phase, (raw['state'] as Map)['phase']);
          expect(t.currentField, (raw['state'] as Map)['current_field']); // null at the end
          expect(t.careQuestionOpen, (raw['state'] as Map)['care_question_open']);
          expect(t.dailyLogs, hasLength((raw['daily_logs'] as List).length));
          // profile_update: only the non-null values, with the server's names and numbers.
          expect({...t.profileUpdate}..remove('zz_future_field'), {
            for (final e in (raw['profile_update'] as Map).entries)
              if (e.value != null) e.key: e.value,
          });
          // pending/checking/questions are lists and maps of the right types.
          expect(t.pending.values.every((v) => v != null), isTrue);
          expect(t.questions, [for (final q in (raw['state'] as Map)['questions'] as List) '$q']);
        }
        if (CheckinTurn.parse(raw).careQuestionOpen) careOpen++;
      }
      expect(careOpen, 1, reason: 'the care reply turn is in the fixtures');
    });

    test('the finished weekly check-in with the care reply keeps its mood and its updates', () {
      final last = CheckinTurn.parse(copy((seam['weekly_care_turns'] as List).last));
      expect(last.complete, isTrue);
      expect(last.state['care_line_shown'], isTrue);
      expect((last.state['confirmed'] as Map)['wellbeing'], 'not_great');
      expect(last.profileUpdate['sleep_hours'], 7.0);
      expect((last.profileUpdate['weight_kg'] as num).toDouble(), closeTo(68.04, 0.01));
      expect(last.profileUpdate.containsKey('age'), isFalse); // null on the server: left alone
    });

    test('onboarding turn: state, model_inputs and client_action; extra fields change nothing', () {
      final raw = at('onboarding_ready');
      final plain = HttpConversationGuide.parseTurn(raw);
      final more = HttpConversationGuide.parseTurn(extras(raw));
      for (final t in [plain, more]) {
        expect(t.complete, isTrue);
        expect(t.message, raw['message']);
        expect(t.state['phase'], 'ready');
        expect(t.modelInputs!['status'], 'ready');
        expect((t.modelInputs!['profile'] as Map).isNotEmpty, isTrue);
        expect(t.providerStatus, raw['provider_status']);
      }
      expect({...more.state['confirmed_profile'] as Map}..remove('zz_future_field'), plain.state['confirmed_profile']);
    });

    test('coach plans: every shape the server returns', () {
      final plans = {
        for (final k in ['plan', 'reused', 'after_feedback', 'emergency', 'bp_crisis', 'general'])
          k: at('coach', k),
        'after_weekly': at('coach_after_weekly'),
      };
      for (final e in plans.entries) {
        final raw = e.value;
        for (final json in [raw, withExtras(raw)]) {
          final plan = DailyPlan.fromJson(json);
          expect(plan.items, hasLength((raw['items'] as List).length), reason: e.key);
          expect(plan.revision, raw['revision_id'], reason: e.key); // null when emergency
          expect(plan.emergency, raw['status'] == 'emergency');
          expect(plan.reusedPrevious, raw['reused_previous']);
          expect(plan.general, raw['plan_type'] == 'general');
          expect(plan.changes, [for (final c in raw['changes'] as List) (c as Map)['explanation']]);
          expect(plan.trace, hasLength((raw['trace'] as List).length));
          for (final item in plan.items) {
            expect(item['source_url'], startsWith('https://'));
            expect(['workout', 'diet', 'habit', 'encourage'], contains(item['kind']));
          }
        }
      }
      expect(DailyPlan.fromJson(plans['bp_crisis']).paused, isTrue);
      expect(DailyPlan.fromJson(plans['bp_crisis']).json['alert'], 'bp_crisis');
      expect(DailyPlan.fromJson(plans['emergency']).items, isEmpty);
      expect(DailyPlan.fromJson(plans['reused']).reusedPrevious, isTrue);
    });

    test('the previous plan the app sends back is the one the server reused', () {
      final plan = DailyPlan.fromJson(at('coach', 'plan'));
      expect(plan.previousPlan(), (seam['coach'] as Map)['previous_plan_as_app_builds_it']);
    });

    test('nullable plan item fields (minutes, callback_note_id, lever) may be null', () {
      final raw = at('coach', 'plan');
      for (final item in raw['items'] as List) {
        (item as Map)
          ..['minutes'] = null
          ..['callback_note_id'] = null
          ..['lever'] = null
          ..['intensity'] = null
          ..['position'] = null
          ..['counts_as'] = null
          ..['wellness_card'] = null;
      }
      raw['based_on'] = null;
      raw['clarify'] = null;
      expect(DailyPlan.fromJson(raw).items, isNotEmpty);
    });

    test('capabilities: provider, company and training flag come from the server', () {
      final plain = AiProvider.fromCapabilities(at('capabilities'))!;
      expect((plain.id, plain.displayName, plain.company), ('muse', 'Muse by Meta', 'Meta'));
      expect(plain.configured, isFalse);
      expect(plain.trainingLine, isNull, reason: 'nothing is claimed when the server does not say so');
      final contributor = AiProvider.fromCapabilities(extras(at('capabilities_contributor')))!;
      expect(contributor.configured, isTrue);
      expect(contributor.trainingLine, 'Meta may use what you share to improve its AI.');
    });

    test('change conversation turns', () {
      for (final key in ['change_start', 'change_turn']) {
        final raw = at(key);
        for (final json in [raw, extras(raw)]) {
          final r = ChangeResponse(json);
          expect(r.message, raw['message']);
          expect(r.complete, raw['complete']);
          expect(r.emergency, raw['emergency']);
          expect(r.phase, (raw['state'] as Map)['phase']);
          expect(r.profileUpdate.values.every((v) => v != null), isTrue);
          expect(r.habitNote, raw['habit_note']); // null without memory consent
        }
      }
    });

    test('document candidates: strings and nulls from the parser', () {
      final raw = at('documents_extract');
      for (final json in [raw, withExtras(raw)]) {
        final d = DocumentExtraction.fromJson(json);
        expect(d.status, 'found');
        final bp = d.candidates.single;
        expect((bp.field, bp.value, bp.unit, bp.page), ('blood_pressure', '128/78', 'mmHg', 1));
        expect(bp.modelInput, isFalse); // blood pressure is information, never a model input
        expect(bp.date, DateTime(2026, 10, 1));
        expect(bp.section, isNull);
        expect(d.providerStatus, 'not_requested');
      }
    });

    test('recommendations: every real server item parses, with its new fields', () {
      for (final entry in (seam['recommendations'] as Map).entries) {
        final items = (entry.value as Map)['recommendations'] as List;
        for (final raw in items) {
          final json = Map<String, dynamic>.from(raw as Map);
          for (final r in [Recommendation.fromJson(json), Recommendation.fromJson(extras(json))]) {
            expect(r.tip, json['message'], reason: entry.key);
            expect(r.whyShort, json['why_short'], reason: entry.key);
            expect(r.effect, json['effect'], reason: entry.key);
            expect(r.sourceDomain, json['source_domain'], reason: entry.key);
            // A lever only with a target the app can hold; a missing current value never presets 0.
            if (json['experiment_target'] == null) expect(r.leverValue, isNull, reason: entry.key);
          }
        }
      }
    });

    test('recommendations: every experiment_target becomes a number the lever can hold', () {
      final targets = [
        for (final r in (seam['recommendations'] as Map).values)
          for (final item in (r as Map)['recommendations'] as List)
            if ((item as Map)['experiment_target'] != null) Map<String, dynamic>.from(item),
      ];
      expect(targets, isNotEmpty);
      expect(targets.any((t) => t['experiment_target'] == 'former'), isTrue, reason: 'covers the smoking string');
      for (final t in targets) {
        final r = Recommendation.fromJson(t);
        expect(r.leverId, t['experiment_lever']);
        expect(r.leverValue, isA<double>(), reason: '${t['experiment_lever']}: ${t['experiment_target']}');
      }
    });
  });

  group('4. error paths: a gentle message, no crash, and recovery', () {
    test('the coach client maps 422, 429, 503, a timeout and garbage to CoachFailure', () async {
      Future<CoachFailure> failWith(Object step) async {
        final s = Script([step]);
        final client = HttpCoachClient(base: ApiBase('https://t.test'), client: s.client);
        try {
          await client.plan({'local_date': '2026-10-26'});
        } on CoachFailure catch (e) {
          return e;
        }
        fail('expected a CoachFailure');
      }

      expect((await failWith(failure(422))).statusCode, 422);
      expect((await failWith(failure(429))).statusCode, 429);
      expect((await failWith(failure(503))).statusCode, 503);
      expect((await failWith(TimeoutException('slow'))).statusCode, isNull);
      expect((await failWith(ok({'status': 'ok'}))).statusCode, isNull); // not a plan
      expect((await failWith(http.Response('<html>proxy</html>', 200))).statusCode, isNull);
    });

    for (final (label, step, message) in <(String, Object Function(), String)>[
      ('422', () => failure(422), 'The plan couldn’t connect. Your saved plan is still here.'),
      ('429', () => failure(429), 'A lot is happening. Give it a moment, then try again.'),
      ('503', () => failure(503), 'The plan couldn’t connect. Your saved plan is still here.'),
      ('timeout', () => TimeoutException('slow'), 'The plan couldn’t connect. Your saved plan is still here.'),
    ]) {
      testWidgets('the daily plan after a $label keeps the saved plan, says so gently, and recovers', (t) async {
        final fresh = at('coach_after_weekly');
        final script = Script([step(), ok(fresh)]);
        // One item keeps its buttons unambiguous: "Yes" asks the coach for a fresh plan.
        final single = at('coach', 'plan');
        single['items'] = [(single['items'] as List).first];
        single['changes'] = [];
        single['trace'] = [];
        final first = DailyPlan.fromJson(single);
        await phone(
          t,
          DailyPlanScreen(
            client: HttpCoachClient(base: ApiBase('https://t.test'), client: script.client),
            confirmedContext: () => {'local_date': '2026-10-26'},
            initialPlan: first,
            onBack: () {},
            onTalk: () {},
          ),
        );
        final firstTitle = first.items.first['title'] as String;
        await reveal(t, find.text('Yes'));
        await t.tap(find.text('Yes'));
        await t.pumpAndSettle();
        await up(t, find.text(message));
        expect(find.text(message), findsOneWidget);
        expect(t.takeException(), isNull);
        // The old plan is still there.
        await reveal(t, find.text(firstTitle));
        expect(find.text(firstTitle), findsOneWidget);
        // Recovery: the same button works, the message goes, the new plan shows.
        await up(t, find.text('Refresh plan'));
        await t.tap(find.text('Refresh plan'));
        await t.pumpAndSettle();
        expect(find.text(message), findsNothing);
        expect(script.calls, 2);
        final newTitle = DailyPlan.fromJson(fresh).items.first['title'] as String;
        await reveal(t, find.text(newTitle));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('the first plan of the day failing with a 503 offers a retry that works', (t) async {
      final script = Script([failure(503), ok(at('coach', 'plan'))]);
      await phone(
        t,
        DailyPlanScreen(
          client: HttpCoachClient(base: ApiBase('https://t.test'), client: script.client),
          confirmedContext: () => {'local_date': '2026-10-26'},
          onBack: () {},
          onTalk: () {},
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('The planner needs a moment. Try again.'), findsOneWidget);
      await t.tap(find.text('Refresh plan'));
      await t.pumpAndSettle();
      expect(find.text('The planner needs a moment. Try again.'), findsNothing);
      expect(t.takeException(), isNull);
    });

    test('a server that never answers times out: coach after 30 s, check-in after 20 s', () {
      fakeAsync((async) {
        final never = MockClient((_) => Completer<http.Response>().future);
        Object? coachError, checkinError;
        HttpCoachClient(base: ApiBase('https://t.test'), client: never)
            .plan({'local_date': '2026-10-26'})
            .then((_) {}, onError: (Object e) { coachError = e; });
        HttpCheckinClient(client: never, base: ApiBase('https://t.test'))
            .turn(action: 'reply', state: const {}, text: 'x')
            .then((_) {}, onError: (Object e) { checkinError = e; });
        async.elapse(const Duration(seconds: 19));
        expect((coachError, checkinError), (null, null));
        async.elapse(const Duration(seconds: 2));
        expect(checkinError, isA<GuideFailure>());
        expect(coachError, isNull);
        async.elapse(const Duration(seconds: 10));
        expect(coachError, isA<CoachFailure>().having((e) => e.statusCode, 'status', isNull));
      });
    });

    test('the check-in client maps 422 to the server\'s own words, 429 to "too busy", the rest to a failure', () async {
      Future<Object> failWith(Object step) async {
        final s = Script([step]);
        final client = HttpCheckinClient(client: s.client, base: ApiBase('https://t.test'));
        try {
          await client.turn(action: 'reply', state: const {}, text: 'x');
        } catch (e) {
          return e;
        }
        fail('expected a failure');
      }

      final errors = seam['errors'] as Map;
      expect(await failWith(failure(422)), isA<GuideRejected>().having((e) => e.message, 'm', (errors['422'] as Map)['message']));
      expect(await failWith(failure(429)), isA<GuideTooBusy>().having((e) => e.message, 'm', (errors['429'] as Map)['message']));
      final unavailable = await failWith(failure(503));
      expect(unavailable, isA<GuideFailure>());
      expect(unavailable, isNot(isA<GuideRejected>()));
      expect(await failWith(TimeoutException('slow')), isA<GuideFailure>());
      expect(await failWith(http.Response('<html>sign in to this Wi-Fi</html>', 403)), isA<GuideFailure>());
    });

    test('a weekly check-in survives 422, 429, 503 and a timeout, then carries on (503 recovery)', () async {
      final turns = [for (final t in seam['weekly_care_turns'] as List) copy(t)];
      final script = Script([
        ok(turns[0]), // start
        failure(422), // the person's answer was refused
        failure(429),
        failure(503),
        TimeoutException('slow'),
        ok(turns[1]), // finally
      ]);
      final controller = CheckinController(
        guide: HttpCheckinClient(client: script.client, base: ApiBase('https://t.test')),
        input: FakeSpeechInput(),
        output: FakeSpeechOutput(),
        store: InMemoryCheckinStore(),
        reminders: CheckinReminders(FakePort()),
        clock: () => DateTime(2026, 10, 26, 9),
        voiceUsable: false,
      );
      addTearDown(controller.dispose);
      expect(await controller.start(kind: 'weekly'), isTrue);
      final errors = seam['errors'] as Map;

      await controller.submitTyped('6 hours');
      expect(controller.notice, (errors['422'] as Map)['message']);
      expect(controller.canRetry, isFalse); // refused: the person must change the answer
      expect(controller.phase, CheckinPhase.idle);

      await controller.submitTyped('6 hours');
      expect(controller.notice, (errors['429'] as Map)['message']);
      expect(controller.canRetry, isTrue);

      await controller.submitTyped('6 hours');
      expect(controller.notice, noNetworkNotice);
      expect(controller.phase, CheckinPhase.idle);
      expect(controller.turn!.message, turns[0]['message'], reason: 'the question is still on screen');

      await controller.submitTyped('6 hours');
      expect(controller.notice, noNetworkNotice);
      expect(controller.canRetry, isTrue);

      await controller.retry(); // the server is back
      expect(controller.notice, isNull);
      expect(controller.turn!.message, turns[1]['message']);
      expect(script.steps, isEmpty);
    });

    test('recommendations: 422, 429, 503 and a timeout are a RecommendationsFailure, never a crash', () async {
      final model = await TwinModelService.load();
      final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
      addTearDown(repo.dispose);
      final errors = seam['errors'] as Map;
      for (final code in [422, 429, 503]) {
        final body = jsonEncode(errors['$code'] ?? {});
        final source = HttpRecommendations(repo,
            base: ApiBase('http://test'), client: MockClient((_) async => http.Response(body, code)));
        await expectLater(source.load(),
            throwsA(isA<RecommendationsFailure>().having((f) => f.statusCode, 'code', code)));
      }
      fakeAsync((async) {
        final source = HttpRecommendations(repo,
            base: ApiBase('http://test'), client: MockClient((_) => Completer<http.Response>().future));
        Object? error;
        source.load().catchError((Object e) { error = e; return <Recommendation>[]; });
        async.elapse(const Duration(seconds: 31));
        expect(error, isA<RecommendationsFailure>());
      });
    });
  });

  group('5. privacy seam: the consent copy for outside AI', () {
    Future<void> pumpConsent(WidgetTester t, AiProvider p) async {
      await t.pumpWidget(
        MaterialApp(theme: lifeTwinTheme(), home: OutsideAiConsentScreen(provider: p, onChoose: (_) {})),
      );
      await t.pump();
    }

    testWidgets('names the provider from the server and says what the company may do', (t) async {
      final p = AiProvider.fromCapabilities(at('capabilities_contributor'))!;
      await pumpConsent(t, p);
      expect(find.text('With Muse by Meta'), findsOneWidget);
      expect(find.text('Meta may use what you share to improve its AI.'), findsOneWidget);
      expect(find.text('Never your name or contact details'), findsOneWidget);
    });

    testWidgets('claims nothing about training when the server does not', (t) async {
      final p = AiProvider.fromCapabilities(at('capabilities'))!;
      await pumpConsent(t, p);
      expect(find.text('With Muse by Meta'), findsOneWidget);
      expect(find.textContaining('improve its AI'), findsNothing);
    });

    testWidgets('a different provider changes the copy; the company is not hard-coded', (t) async {
      final caps = at('capabilities_contributor');
      (caps['personalize'] as Map)
        ..['display_name'] = 'Other Assistant'
        ..['company'] = 'Other Co';
      await pumpConsent(t, AiProvider.fromCapabilities(caps)!);
      expect(find.text('With Other Assistant'), findsOneWidget);
      expect(find.text('Other Co may use what you share to improve its AI.'), findsOneWidget);
      expect(find.textContaining('Meta'), findsNothing);
    });
  });

  group('1++. a field the server adds later', () {
    test('inside a finished check-in does not end up in the stored profile or the next request', () async {
      final model = await TwinModelService.load();
      final now = DateTime(2026, 10, 26, 9, 30);
      final repo = TwinRepository(
        model: model,
        store: await TwinStore.open(MemoryBackend()),
        reminders: CheckinReminders(FakePort()),
        clock: () => now,
      );
      final onboarding = at('onboarding_ready');
      await repo.saveOnboarding(
        Map<String, dynamic>.from(extras(onboarding)['state'] as Map),
        modelInputs: Map<String, dynamic>.from(onboarding['model_inputs'] as Map),
      );
      await TwinCheckinStore(repo).applyFinishedCheckin(
        extras(copy((seam['weekly_care_turns'] as List).last)),
        localDate: '2026-10-25',
      );
      // The server rejects fields it does not know (extra="forbid"): an unknown key kept in
      // the profile would turn every later coach, change and recommendations call into a 422.
      expect(repo.profile.keys, everyElement(isNot('zz_future_field')));
      expect(coachContext(repo, now: now)['profile'], isNot(contains('zz_future_field')));
      expect(repo.profile['sleep_hours'], 7.0);
    });
  });

  group('1+. one connected flow on the phone, from real server output', () {
    test('onboarding -> profile -> score, percentile, lifespan -> coach plan -> daily -> weekly (care) -> history', () async {
      final model = await TwinModelService.load();
      var now = DateTime(2026, 10, 26, 9, 30);
      final repo = TwinRepository(
        model: model,
        store: await TwinStore.open(MemoryBackend()),
        reminders: CheckinReminders(FakePort()),
        clock: () => now,
      );
      final checkins = TwinCheckinStore(repo);

      // Onboarding answers -> the confirmed profile.
      final onboarding = at('onboarding_ready');
      await repo.saveOnboarding(
        Map<String, dynamic>.from(onboarding['state'] as Map),
        modelInputs: Map<String, dynamic>.from(onboarding['model_inputs'] as Map),
        sources: const {'height_cm': HistorySource.appleHealth, 'weight_kg': HistorySource.appleHealth},
      );
      final confirmed = (onboarding['state'] as Map)['confirmed_profile'] as Map;
      for (final e in confirmed.entries) {
        if (e.value != null) expect(repo.profile[e.key], e.value, reason: 'profile ${e.key}');
      }

      // Health score, percentile and the lifespan estimate come from the on-device model.
      final score0 = repo.healthScore;
      expect(repo.healthScoreStatus, HealthScoreStatus.available);
      expect(score0, isNotNull);
      final pct = repo.ageGroupPercentile!;
      expect(pct, inInclusiveRange(0, 100));
      final life = repo.lifespanEstimate!;
      expect(life.expectedAge, greaterThan(72));
      expect(life.expectedYear, greaterThan(2026));
      final historyBefore = repo.healthScoreHistory().length;
      expect(historyBefore, greaterThanOrEqualTo(1));

      // Recommendations arrived with the completing turn; the app's own list is its stub.
      expect(onboarding['recommendations'], isNotEmpty);

      // The coach plan the server made for the request this phone builds parses and round-trips.
      final body = coachRequestBody(coachContext(repo, now: now));
      expect(body['profile'], isA<Map>());
      expect(body['local_date'], '2026-10-26');
      final plan = DailyPlan.fromJson(at('coach', 'plan'));
      expect(plan.items.length, inInclusiveRange(2, 4));

      // A daily check-in (low mood, care reply) is history only: the profile does not move.
      final profileBefore = copy(repo.profile);
      now = DateTime(2026, 10, 26, 20);
      await checkins.applyFinishedCheckin(at('daily'), localDate: '2026-10-26');
      expect(repo.profile, profileBefore);

      // The weekly check-in (care reply, then the yes) updates the profile.
      await checkins.applyFinishedCheckin(
        copy((seam['weekly_care_turns'] as List).last),
        localDate: '2026-10-25',
      );
      final updated = seam['updated_profile'] as Map;
      for (final k in ['weight_kg', 'sleep_hours', 'smoking_status', 'sedentary_min_day']) {
        expect(repo.profile[k], updated[k], reason: 'the phone and the server agree on $k');
      }
      expect(repo.profile['age'], 72, reason: 'a null in profile_update leaves the answer alone');
      expect(repo.healthScore, isNot(score0), reason: 'a new sleep and weight give a new score');

      // Updated score history: another point, newest last.
      final history = repo.healthScoreHistory();
      expect(history.length, greaterThan(historyBefore));
      expect(history.last.rawLogRelativeHazard, repo.rawLogRelativeHazard);
    });
  });
}
