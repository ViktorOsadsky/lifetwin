import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/outlook_change.dart';
import 'package:lifesim/checkin/updated_card.dart';
import 'package:lifesim/experiment/ideas_list_screen.dart';
import 'package:lifesim/experiment/recommendations.dart';
import 'package:lifesim/experiment/room_pills.dart';
import 'package:lifesim/experiment/still_learning_screen.dart';
import 'package:lifesim/onboarding/missing_answers.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/wellness/home_panel.dart';
import 'package:lifesim/wellness/models.dart';

import 'twin/store_and_checkin_test.dart' show fullProfile;

/// The server's "Answer N more questions" (`state.ask_only`, server/tests/test_missing_answers.py),
/// scripted: it asks the `ask_only` fields still without a value, in order; a number answers the
/// open one, "I don't know" moves on. Every question it asked is recorded.
class AskOnlyGuide implements ConversationGuide {
  final asked = <String>[];
  final starts = <Map<String, dynamic>?>[];

  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    bool aiHelper = false,
    String? importSource,
  }) async {
    final s = Map<String, dynamic>.from(state ?? const {});
    if (action == 'start') starts.add(state);
    final confirmed = Map<String, dynamic>.from(s['confirmed_profile'] as Map? ?? const {});
    final unknown = [for (final f in s['unknown_fields'] as List? ?? const []) '$f'];
    final current = s['current_field'] as String?;
    if (action == 'reply' && current != null) {
      final n = num.tryParse('$text'.split(' ').first);
      if (n != null) {
        confirmed[current] = n;
      } else {
        unknown.add(current);
      }
    }
    final only = [for (final f in s['ask_only'] as List? ?? const []) '$f'];
    final next = only.where((f) => confirmed[f] == null && !unknown.contains(f)).firstOrNull;
    if (next != null) asked.add(next);
    return GuideTurn(
      state: {
        ...s,
        'phase': next == null ? 'ready' : 'asking',
        'current_field': next,
        'confirmed_profile': confirmed,
        'unknown_fields': unknown,
      },
      message: next == null ? 'Thank you, that\'s all I needed.' : 'What about your $next?',
      complete: next == null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());

  Future<TwinRepository> repoWithout(List<String> keys) async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    await repo.saveConversationProfile({...fullProfile}..removeWhere((k, _) => keys.contains(k)));
    return repo;
  }

  group('missing questions', () {
    test('height and weight are asked only where missing; the rest one each, in order', () {
      expect(missingQuestions(['bmi', 'sex_nhanes'], {'height_cm': 170}), ['sex', 'weight_kg']);
      expect(missingQuestions(['vigorous_recreation_min_week', 'smoking_status'], const {}), [
        'smoking_status',
        'vigorous_recreation_min_week',
      ]);
      expect(answerMoreLabel(1), 'Answer 1 more question');
      expect(answerMoreLabel(3), 'Answer 3 more questions');
      expect(roughMissingLabel(2), 'Rough guide: 2 answers missing');
    });

    test('the start state has the saved answers, the server words, and only the missing fields', () {
      final s = askOnlyState({...fullProfile, 'vigorous_recreation_min_week': null}, [
        'vigorous_recreation_min_week',
      ], memoryConsent: false);
      expect(s['phase'], 'idle');
      expect(s['ask_only'], ['vigorous_recreation_min_week']);
      final confirmed = s['confirmed_profile'] as Map;
      expect(confirmed.containsKey('vigorous_recreation_min_week'), isFalse);
      expect(confirmed['general_health'], 'very_good');
      expect(confirmed['age'], 45);
    });
  });

  testWidgets('answerMissing asks exactly the missing fields, saves, and returns with a score', (t) async {
    final repo = await repoWithout(['vigorous_recreation_min_week', 'smoking_status', 'sleep_hours']);
    expect(repo.healthScore, isNull); // three missing: no number
    final guide = AskOnlyGuide();
    final intake = VoiceOnboardingController(guide: guide, input: FakeSpeechInput(), output: FakeSpeechOutput());
    final routes = AgenticRoutes(look: ValueNotifier(const TwinAppearance()), api: ApiBase(), voice: () => intake)
      ..attach(repo);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => routes.answerMissing(c), child: const Text('origin')),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('origin'));
    await t.pumpAndSettle();
    final start = guide.starts.single!;
    expect(start['ask_only'], ['smoking_status', 'sleep_hours', 'vigorous_recreation_min_week']);
    expect((start['confirmed_profile'] as Map)['age'], 45);
    // Mochi's usual conversation screen (voice or typing), not a form and not the whole intake.
    expect(find.byType(VoiceOnboardingScreen), findsOneWidget);
    // The person answers through the conversation's own controller (typing).
    VoiceOnboardingController talk() => routes.lastMissingTalk!;
    await talk().submitTyped("I don't know");
    await t.pumpAndSettle();
    await talk().submitTyped('7');
    await t.pumpAndSettle();
    await talk().submitTyped('30 minutes');
    await t.pumpAndSettle();
    expect(guide.asked, ['smoking_status', 'sleep_hours', 'vigorous_recreation_min_week']);
    expect(talk().turn!.complete, isTrue);
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    // Back on the screen it came from; the two answers are saved and a (rough) score shows.
    expect(find.text('origin'), findsOneWidget);
    expect(repo.profile['sleep_hours'], 7);
    expect(repo.profile['vigorous_recreation_min_week'], 30);
    expect(repo.missingInputs, ['smoking_status']);
    expect(repo.healthScoreStatus, HealthScoreStatus.roughMissing);
    expect(repo.healthScore, isNotNull);
  });

  group('every "still needed" surface has the one action', () {
    testWidgets('Still learning: the dock says "Answer N more questions"', (t) async {
      var opened = 0;
      final a = model.assess({...fullProfile}..remove('sleep_hours')..remove('smoking_status')..remove('diabetes'));
      await t.pumpWidget(
        MaterialApp(
          home: StillLearningScreen(
            appearance: const TwinAppearance(),
            assessment: a,
            known: const [],
            onBack: () {},
            onTellMochi: (_) {},
            questionCount: 3,
            onAnswerMissing: () => opened++,
          ),
        ),
      );
      await t.tap(find.text('Answer 3 more questions'));
      expect(opened, 1);
    });

    testWidgets('Ideas for you, nothing yet: "Answer 1 more question"', (t) async {
      var opened = 0;
      await t.pumpWidget(
        MaterialApp(
          home: IdeasListScreen(
            source: _NoIdeas(),
            appearance: const TwinAppearance(),
            origin: 'room',
            onBack: () {},
            onTry: (_) {},
            missingInputs: const ['vigorous_recreation_min_week'],
            questionCount: 1,
            onAnswerMore: () => opened++,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Answer 1 more question'));
      expect(opened, 1);
    });

    testWidgets('the Room pill opens the missing questions directly', (t) async {
      final repo = await repoWithout(['vigorous_recreation_min_week']);
      var opened = 0, learning = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: roomPills(
                repository: repo,
                onExperiment: () {},
                onStillLearning: () => learning++,
                onAnswerMissing: () => opened++,
                onWellness: () {},
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Answer 1 more question'));
      expect((opened, learning), (1, 0));
    });

    testWidgets('Home card: rough score flagged, with the action; no number with three missing', (t) async {
      var opened = 0;
      Widget card(WellnessSnapshot s) => MaterialApp(
        home: Scaffold(
          body: HomeWellnessPanel(snapshot: s, onEstimate: () {}, compact: true, onAnswerMissing: () => opened++),
        ),
      );
      await t.pumpWidget(
        card(
          const WellnessSnapshot(
            healthScore: 0.3,
            status: HealthScoreStatus.roughMissing,
            ageGroupPercentile: 60,
            missingCount: 1,
          ),
        ),
      );
      expect(find.text('Rough guide: 1 answer missing'), findsOneWidget);
      await t.tap(find.text('Answer 1 more question'));
      await t.pumpWidget(
        card(
          const WellnessSnapshot(status: HealthScoreStatus.missingInputs, message: 'Complete every model input.', missingCount: 3),
        ),
      );
      expect(find.text('Rough guide: 3 answers missing'), findsNothing);
      await t.tap(find.text('Answer 3 more questions'));
      expect(opened, 2);
    });

    testWidgets('the check-in\'s outlook card: "Still needed" with the action', (t) async {
      var opened = 0;
      final after = model.assess(
        {...fullProfile}..remove('sleep_hours')..remove('smoking_status')..remove('sedentary_min_day'),
      );
      final change = OutlookChange.between(null, after);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OutlookChangeCard(
              change: change,
              answerLabel: answerMoreLabel(3),
              onTellMochi: () => opened++,
            ),
          ),
        ),
      );
      expect(find.textContaining('Still needed'), findsOneWidget);
      await t.tap(find.text('Answer 3 more questions'));
      expect(opened, 1);
    });
  });

  test('the end-of-intake offer has Yes / Not now quick answers and no question number', () async {
    final guide = _OfferGuide();
    final c = VoiceOnboardingController(guide: guide, input: FakeSpeechInput(), output: FakeSpeechOutput());
    await c.answerConsent(false);
    expect(c.turn!.phase, 'missing');
    expect(c.quickAnswers, [('Yes', 'yes'), ('Not now', 'not now')]);
    expect(c.questionNumber, isNull);
  });
}

class _OfferGuide implements ConversationGuide {
  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    bool aiHelper = false,
    String? importSource,
  }) async => const GuideTurn(
    state: {'phase': 'missing', 'current_field': null, 'confirmed_profile': {}},
    message: 'I still need 1 answer for your estimate: your vigorous exercise. Want to answer it now?',
    complete: false,
  );
}

class _NoIdeas implements RecommendationsSource {
  @override
  Future<List<Recommendation>> load() async => const [];
}
