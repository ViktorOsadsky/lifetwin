// The compact Home score card: layout, the info circle, the lifespan chip, the trend.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show HealthScoreStatus, TwinModelService;
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/wellness/home_panel.dart';
import 'package:lifesim/wellness/models.dart';

import 'support/app_fonts.dart';
import 'support/settings_hub.dart';

const _lifespan = LifespanReveal(expectedAge: 87, p25Age: 80, p75Age: 93, expectedYear: 2051);

WellnessSnapshot _snap({bool seen = false, List<double> history = const []}) => WellnessSnapshot(
  healthScore: 0.42,
  status: HealthScoreStatus.available,
  ageGroupPercentile: 72,
  lifespan: _lifespan,
  lifespanRevealSeen: seen,
  history: history,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<void> pumpCard(
    WidgetTester t,
    WellnessSnapshot snap, {
    double width = 390,
    double scale = 1,
    VoidCallback? onDrivers,
    VoidCallback? onEstimate,
  }) async {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 844), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: HomeWellnessPanel(
                  snapshot: snap,
                  compact: true,
                  stateLine: 'Still learning 2',
                  onDrivers: onDrivers ?? () {},
                  onEstimate: onEstimate ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  for (final (width, scale) in [(390.0, 1.0), (320.0, 1.0), (390.0, 1.6), (320.0, 1.6)]) {
    testWidgets('the card fits at $width wide, ${scale}x text, with no overflow', (t) async {
      await pumpCard(t, _snap(seen: true, history: [0.1, 0.2, 0.15, 0.3, 0.42]), width: width, scale: scale);
      expect(t.takeException(), isNull);
      expect(find.text('+0.42'), findsOneWidget);
      expect(find.byType(ScoreSparkline), findsOneWidget);
      expect(find.byTooltip('What moves your score'), findsOneWidget);
      final info = t.getSize(find.byTooltip('What moves your score'));
      expect(info.width >= 48 && info.height >= 48, isTrue);
    });
  }

  testWidgets('the card is short: well under 260 px at 390 wide', (t) async {
    await pumpCard(t, _snap(seen: true, history: [0.1, 0.42]));
    expect(t.getSize(find.byType(HomeWellnessPanel)).height, lessThan(260));
  });

  testWidgets('the circled i opens the drivers', (t) async {
    var opened = 0;
    await pumpCard(t, _snap(), onDrivers: () => opened++);
    await t.tap(find.byTooltip('What moves your score'));
    expect(opened, 1);
  });

  testWidgets('no sparkline under two points; no "See your estimate" button', (t) async {
    await pumpCard(t, _snap(history: [0.3]));
    expect(find.byType(ScoreSparkline), findsNothing);
    expect(find.text('See your estimate'), findsNothing);
  });

  testWidgets('the lifespan chip names the year only after the reveal, and opens the estimate', (t) async {
    var estimates = 0;
    await pumpCard(t, _snap(seen: false), onEstimate: () => estimates++);
    expect(find.textContaining('Around'), findsNothing);
    await t.tap(find.text('Your estimate'));
    expect(estimates, 1);
    await pumpCard(t, _snap(seen: true), onEstimate: () => estimates++);
    expect(find.text('Around 2051'), findsOneWidget);
    await t.tap(find.text('Around 2051'));
    expect(estimates, 2);
  });

  testWidgets('Home shows the score card, Check in and the Today card without scrolling at 390 x 844', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = await memoryRepo(model);
    await repo.saveConversationProfile({
      'age': 55,
      'sex': 'male',
      'height_cm': 175.0,
      'weight_kg': 80.0,
      'sleep_hours': 5,
      'smoking_status': 'current',
      'diabetes': false,
      'hypertension_diagnosed': false,
      'general_health': 3,
      'vigorous_recreation_min_week': 0,
      'moderate_recreation_min_week': 20,
      'sedentary_min_day': 600,
    });
    await t.pumpWidget(
      LifeTwinApp(
        controller: VoiceOnboardingController(
          guide: FakeConversationGuide(),
          input: FakeSpeechInput(),
          output: FakeSpeechOutput(),
        ),
        twin: Future.value(repo),
      ),
    );
    await t.pump();
    await t.pump();
    expect(find.text('Health score'), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.textContaining('Today', findRichText: true), findsOneWidget);
    final scroll = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.maxScrollExtent, 0);
  });
}
