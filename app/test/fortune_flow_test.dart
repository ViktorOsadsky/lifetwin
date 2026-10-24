import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/forecast/forecast_screen.dart';
import 'package:lifesim/forecast/fortune_ceremony_screen.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/widgets.dart';

class FakeForecastClient implements ForecastClient {
  final calls = <Map<String, dynamic>>[];
  final answers = <Object>[]; // Forecast or ForecastFailure, in order

  @override
  Future<Forecast> predict(Map<String, dynamic> confirmedProfile) async {
    calls.add(confirmedProfile);
    final next = answers.removeAt(0);
    if (next is ForecastFailure) throw next;
    return next as Forecast;
  }
}

/// Real model output for design profile C (68 F, 165 cm / 68 kg, 60 min/wk,
/// former smoker, 7 h), deepsurv-nhanes-73700ee880b6 via POST /api/predict
/// on 2026-10-24 (docs/design/painted-card-direction.md §2).
Map<String, dynamic> profileCJson() => {
  'schema_version': '1.0',
  'status': 'supported',
  'model_version': 'deepsurv-nhanes-73700ee880b6',
  'max_horizon_years': 5,
  'survival': [
    {'years': 1, 'survival': 0.9852},
    {'years': 3, 'survival': 0.9484},
    {'years': 5, 'survival': 0.9080},
  ],
  'curve': [
    {'years': 0.0, 'survival': 1.0},
    {'years': 1.0, 'survival': 0.9852},
    {'years': 3.0, 'survival': 0.9484},
    {'years': 5.0, 'survival': 0.9080},
  ],
  'filled_in': [
    {'feature': 'sedentary_min_day', 'label': 'time spent sitting each day'},
    {'feature': 'diabetes_diagnosed', 'label': 'diabetes'},
    {'feature': 'hypertension_diagnosed', 'label': 'high blood pressure'},
    {'feature': 'general_health', 'label': 'how you rate your health'},
  ],
  'reason': null,
  'limitations': ['No causal effects of changing lifestyle are estimated.'],
};

const profileC = {
  'age': 68,
  'sex': 'female',
  'height_cm': 165,
  'weight_kg': 68,
  'exercise_minutes_weekly': 60,
  'smoking_status': 'former',
  'sleep_hours': 7,
};

const sentenceC = 'Out of 100 people with answers like yours, about 91 were still living 5 years later.';

Future<FakeForecastClient> pumpForecast(WidgetTester t, Object answer, {VoidCallback? onBack}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final client = FakeForecastClient()..answers.add(answer);
  await t.pumpWidget(
    MaterialApp(
      home: ForecastScreen(
        client: client,
        profile: profileC,
        healthKeys: const {'height_cm', 'sleep_hours'},
        onBack: onBack ?? () {},
      ),
    ),
  );
  await t.pumpAndSettle();
  return client;
}

void main() {
  testWidgets('supported (profile C): About 91 in 100, 91 bear heads, the exact sentence, nothing invented', (t) async {
    final client = await pumpForecast(t, Forecast.parse(profileCJson()));
    expect(client.calls.single, profileC);
    expect(find.text('Your look ahead'), findsOneWidget);
    expect(find.textContaining('About 91 in 100', findRichText: true), findsOneWidget);
    expect(find.text('chance you’re still here in 5 years'), findsOneWidget);
    expect(t.widget<BearHeadArray>(find.byType(BearHeadArray)).filled, 91);
    expect(find.text(sentenceC), findsOneWidget);
    expect(find.text('Linked, not proven.'), findsOneWidget);
    expect(find.text('Why?'), findsOneWidget);
    expect(find.text('See what shaped it'), findsOneWidget);
    // Never an age, a date, a countdown, a percentage or a grade.
    for (final banned in ['life expectancy', 'death', r'\bdie\b', 'countdown', '%', r'\bage\b', 'years old']) {
      expect(find.textContaining(RegExp(banned, caseSensitive: false), findRichText: true), findsNothing);
    }
  });

  testWidgets('See what shaped it: the curve, confirmed answers with sources, the filled_in labels, the limits', (
    t,
  ) async {
    await pumpForecast(t, Forecast.parse(profileCJson()));
    await t.ensureVisible(find.text('See what shaped it'));
    await t.pumpAndSettle();
    await t.tap(find.text('See what shaped it'));
    await t.pumpAndSettle();

    final curve = t.widget<SurvivalCurve>(find.byType(SurvivalCurve));
    expect(curve.markers, {1: 0.9852, 3: 0.9484, 5: 0.9080});
    expect(curve.curve, hasLength(4));
    expect(
      find.bySemanticsLabel(
        'Out of 100 people with answers like yours: about 99 after 1 year, about 95 after 3 years, about 91 after 5 years.',
      ),
      findsOneWidget,
    );
    expect(find.text('Built from your answers'), findsOneWidget);
    expect(find.text('Age 68'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Former smoker'), findsOneWidget);
    expect(find.text('Exercise 60 min/week'), findsOneWidget);
    expect(find.text('Apple Health'), findsNWidgets(2)); // height and sleep
    await t.scrollUntilVisible(find.text('We assumed'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('We assumed'), findsOneWidget);
    for (final label in [
      'Time spent sitting each day',
      'Diabetes',
      'High blood pressure',
      'How you rate your health',
    ]) {
      await t.scrollUntilVisible(find.text(label), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Add an answer'), findsNWidgets(4));
    await t.scrollUntilVisible(find.text('Not a promise, not a date'), 200, scrollable: find.byType(Scrollable).first);
    for (final line in ['Looks 5 years ahead at most', 'A US health survey', 'Links, not causes']) {
      expect(find.text(line), findsOneWidget);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('unsupported: the plain reason, Go back to my answers, no number and no bear heads', (t) async {
    const reason =
        'The survey this forecast learns from does not record exact ages above 80, '
        'so we cannot make a forecast for you yet.';
    var backs = 0;
    await pumpForecast(
      t,
      Forecast.parse({
        ...profileCJson(),
        'status': 'unsupported',
        'survival': <Object>[],
        'curve': <Object>[],
        'filled_in': <Object>[],
        'reason': reason,
      }),
      onBack: () => backs++,
    );
    expect(find.text("I can't make a forecast for you yet. $reason"), findsOneWidget);
    expect(find.byType(BearHeadArray), findsNothing);
    expect(find.textContaining('in 100', findRichText: true), findsNothing);
    await t.tap(find.text('Go back to my answers'));
    expect(backs, 1);
  });

  testWidgets('501 (model not installed): still learning, misted ball, Back to room', (t) async {
    var backs = 0;
    await pumpForecast(t, const ForecastFailure('model not installed', modelMissing: true), onBack: () => backs++);
    expect(find.text('Still learning'), findsOneWidget);
    expect(find.text(stillLearningLine), findsOneWidget);
    expect(find.text('Your fortune will show here later.'), findsOneWidget);
    expect(find.byType(BearHeadArray), findsNothing);
    expect(find.text('Try again'), findsNothing);
    await t.tap(find.text('Back to room'));
    expect(backs, 1);
  });

  testWidgets('ceremony: Ask the ball pulses, then hands off; reduced motion hands off at once', (t) async {
    for (final reduced in [false, true]) {
      var asked = 0;
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: const Size(390, 844), disableAnimations: reduced),
            child: FortuneCeremonyScreen(key: ValueKey(reduced), onAsk: () => asked++, onBack: () {}),
          ),
        ),
      );
      expect(find.text('Want to peek ahead?'), findsOneWidget);
      await t.tap(find.text('Ask the ball'));
      await t.pump();
      expect(asked, reduced ? 1 : 0);
      await t.pumpAndSettle();
      expect(asked, 1);
    }
  });

  group('the chosen twin is composited on the night plate', () {
    const human = TwinAppearance(type: TwinType.human);

    String spriteAsset(WidgetTester t) {
      final image = t.widget<Image>(find.descendant(of: find.byType(TwinSprite), matching: find.byType(Image)).first);
      return (image.image as AssetImage).assetName;
    }

    String plateAsset(WidgetTester t) =>
        (t.widget<Image>(find.descendant(of: find.byType(PlateScene), matching: find.byType(Image)).first).image
                as AssetImage)
            .assetName;

    Future<void> pumpHuman(WidgetTester t, Widget screen) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: screen));
      await t.pumpAndSettle();
    }

    ForecastScreen forecast(Object answer) => ForecastScreen(
      client: FakeForecastClient()..answers.add(answer),
      profile: profileC,
      appearance: human,
      onBack: () {},
    );

    testWidgets('Human: ceremony holds the ball', (t) async {
      await pumpHuman(t, FortuneCeremonyScreen(appearance: human, onAsk: () {}, onBack: () {}));
      expect(spriteAsset(t), 'assets/twin/human/pose/hold_ball.png');
      expect(plateAsset(t), 'assets/scene/night.jpg');
      expect(t.widget<TwinSprite>(find.byType(TwinSprite)).holdsBall, isTrue);
    });

    testWidgets('Human: the supported result holds the ball', (t) async {
      await pumpHuman(t, forecast(Forecast.parse(profileCJson())));
      expect(find.text(sentenceC), findsOneWidget);
      expect(spriteAsset(t), 'assets/twin/human/pose/hold_ball.png');
      expect(plateAsset(t), 'assets/scene/night.jpg');
    });

    testWidgets('Human: still learning shrugs', (t) async {
      await pumpHuman(t, forecast(const ForecastFailure('model not installed', modelMissing: true)));
      expect(find.text('Still learning'), findsOneWidget);
      expect(spriteAsset(t), 'assets/twin/human/pose/shrug.png');
    });

    testWidgets('Bear: unsupported shrugs; the default bear holds the ball in the ceremony', (t) async {
      await pumpHuman(
        t,
        ForecastScreen(
          client: FakeForecastClient()
            ..answers.add(
              Forecast.parse({
                ...profileCJson(),
                'status': 'unsupported',
                'survival': <Object>[],
                'reason': 'Not covered.',
              }),
            ),
          profile: profileC,
          onBack: () {},
        ),
      );
      expect(spriteAsset(t), 'assets/twin/bear/pose/shrug.png');
      await pumpHuman(t, FortuneCeremonyScreen(onAsk: () {}, onBack: () {}));
      expect(spriteAsset(t), 'assets/twin/bear/pose/hold_ball.png');
    });
  });

  test('poses fall back to the twin\'s own standing sprite when it lacks them', () {
    expect(twinAsset(TwinType.human, TwinLook.calHat, TwinPose.holdBall), 'assets/twin/human/pose/hold_ball.png');
    expect(twinAsset(TwinType.human, TwinLook.calHat, TwinPose.sleep), 'assets/twin/human/base/cal_hat.png');
    expect(twinAsset(TwinType.human, TwinLook.calHat), 'assets/twin/human/base/cal_hat.png');
    expect(twinAsset(TwinType.bear, TwinLook.calHat, TwinPose.shrug), 'assets/twin/bear/pose/shrug.png');
    expect(twinAsset(TwinType.bear, TwinLook.plain, TwinPose.holdBall), 'assets/twin/bear/base/default.png');
    expect(twinAsset(TwinType.human, TwinLook.plain, TwinPose.shrug), 'assets/twin/human/base/default.png');
    expect(twinFeetAnchor(TwinType.human, TwinLook.calHat, TwinPose.shrug), 0.967);
    expect(twinFeetAnchor(TwinType.human, TwinLook.calHat, TwinPose.sleep), 0.954);
  });
}
