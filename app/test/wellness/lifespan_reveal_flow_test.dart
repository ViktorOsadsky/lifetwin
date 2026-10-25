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
  RosaGuide(this.profile);
  final Map<String, dynamic> profile;

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
        'confirmed_profile': done ? profile : <String, dynamic>{},
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
  late Map<String, dynamic> rosa;
  setUpAll(() async {
    model = await TwinModelService.load();
    // Rosa (64) as she onboards in the demo.
    rosa = Map<String, dynamic>.from(rosaProfile);
  });

  Future<void> launch(WidgetTester t, TwinRepository repo) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final client = FakeForecastClient()..answers.add(forecastFrom(supportedJson()));
    await t.pumpWidget(
      LifeTwinApp(
        controller: VoiceOnboardingController(
          guide: RosaGuide(rosa),
          input: FakeSpeechInput(),
          output: FakeSpeechOutput(),
        ),
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
    // Rosa's yearly projection: 50% at 98.93, 75% at 87.39, 25% at 108.89.
    final est = repo.lifespanEstimate!;
    expect(est.expectedYear, year + 35);
    expect((est.expectedAge.round(), est.p25Age.round(), est.p75Age.round()), (99, 87, 109));
    expect(find.text('Around ${est.expectedYear}'), findsOneWidget);
    expect(find.text('age 87–109'), findsOneWidget);
    expect(find.text('Rough guide'), findsNothing, reason: 'age 64 is inside 35–79: no flag badge');
    expect(est.status, LifespanStatus.available, reason: 'the engine flag is off for Rosa');
    expect(find.text('Estimate, rough guide'), findsOneWidget, reason: 'the lifespan is always a rough guide');

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
        controller: VoiceOnboardingController(
          guide: RosaGuide(rosa),
          input: FakeSpeechInput(),
          output: FakeSpeechOutput(),
        ),
        forecastClient: client3,
        twin: Future.value(next),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Estimate, rough guide'), findsOneWidget, reason: 'on the Home chip too, flag off');
    await t.ensureVisible(find.text('Around ${next.lifespanEstimate!.expectedYear}'));
    await t.tap(find.text('Around ${next.lifespanEstimate!.expectedYear}'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ask the ball'));
    await t.pumpAndSettle();
    expect(find.text('Around ${next.lifespanEstimate!.expectedYear}'), findsOneWidget);
  });
}
