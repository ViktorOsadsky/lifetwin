import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/demo/demo_seed.dart' show rosaProfile;
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/wellness/repository_adapter.dart';

import '../forecast_screen_test.dart' show FakeForecastClient, supportedJson;
import '../support/assessments.dart';

/// Onboarding that finishes at once with Rosa's (64) confirmed answers.
class RosaGuide extends FakeConversationGuide {
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
    final done = action != 'start';
    return GuideTurn(
      state: {
        'phase': done ? 'ready' : 'asking',
        'current_field': done ? null : 'age',
        'confirmed_profile': done ? rosaProfile : <String, dynamic>{},
        'pending_profile': <String, dynamic>{},
      },
      message: done ? 'All done.' : 'How old are you?',
      complete: done,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());

  Future<void> launch(WidgetTester t, TwinRepository repo) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final client = FakeForecastClient()..answers.add(forecastFrom(supportedJson()));
    await t.pumpWidget(
      LifeTwinApp(
        controller: VoiceOnboardingController(guide: RosaGuide(), input: FakeSpeechInput(), output: FakeSpeechOutput()),
        forecastClient: client,
        twin: Future.value(repo),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> finishOnboarding(WidgetTester t) async {
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    await t.tap(find.text("No, I'll type"));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 700));
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '64');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ask the ball'));
    await t.pumpAndSettle();
  }

  testWidgets('Rosa (64): the reveal after onboarding once, not on the next launch, shown on See your estimate', (
    t,
  ) async {
    final backend = MemoryBackend();
    final repo = TwinRepository(model: model, store: await TwinStore.open(backend));
    final year = DateTime.now().year;

    await launch(t, repo);
    await finishOnboarding(t);
    expect(repo.lifespanRevealSeen, isTrue);
    // Rosa: about 2050, age about 88-89, most likely 83-95 (the engine's own numbers, shown rounded).
    final est = repo.lifespanEstimate!;
    expect(est.expectedYear, inInclusiveRange(year + 24, year + 25));
    expect(est.expectedAge.round(), inInclusiveRange(88, 89));
    final age = (est.expectedAge + 0.5).floor(), lo = (est.p25Age + 0.5).floor(), hi = (est.p75Age + 0.5).floor();
    expect((lo, hi), (83, 95));
    expect(find.text('Around ${est.expectedYear}'), findsOneWidget);
    expect(find.textContaining('about age $age, most likely 83–95'), findsOneWidget);
    expect(find.text('Rough guide'), findsNothing, reason: 'age 64 is inside 35–79');

    // The next launch: the flag is remembered, so a later conversation does not reveal again.
    await t.pumpWidget(const SizedBox());
    final next = TwinRepository(model: model, store: await TwinStore.open(backend));
    expect(next.lifespanRevealSeen, isTrue);
    expect(RepositoryWellness(next).snapshot.lifespanRevealSeen, isTrue);

    // "See your estimate" (the Room's score card) shows it.
    await t.pumpWidget(const SizedBox());
    final client3 = FakeForecastClient()..answers.add(forecastFrom(supportedJson()));
    await t.pumpWidget(
      LifeTwinApp(
        controller: VoiceOnboardingController(guide: RosaGuide(), input: FakeSpeechInput(), output: FakeSpeechOutput()),
        forecastClient: client3,
        twin: Future.value(next),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('See your estimate'));
    await t.tap(find.text('See your estimate'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ask the ball'));
    await t.pumpAndSettle();
    expect(find.text('Around ${next.lifespanEstimate!.expectedYear}'), findsOneWidget);
  });
}
