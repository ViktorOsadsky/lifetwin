import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/forecast/forecast_screen.dart';
import 'package:lifesim/forecast/fortune_ceremony_screen.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/widgets.dart';

import 'support/assessments.dart';

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

/// An on-device result shaped like design profile C (68 F, 165 cm / 68 kg, former
/// smoker, 7 h), the package's assess() output.
Map<String, dynamic> profileCJson() => availableAssessment(const {1: 0.9852, 2: 0.967, 3: 0.9484, 4: 0.928, 5: 0.9080});

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
    final client = await pumpForecast(t, forecastFrom(profileCJson()));
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

  testWidgets('See what shaped it: the curve, confirmed answers with sources, the limits, nothing assumed', (t) async {
    await pumpForecast(t, forecastFrom(profileCJson()));
    await t.ensureVisible(find.text('See what shaped it'));
    await t.pumpAndSettle();
    await t.tap(find.text('See what shaped it'));
    await t.pumpAndSettle();

    final curve = t.widget<SurvivalCurve>(find.byType(SurvivalCurve));
    expect(curve.markers, {1: 0.9852, 2: 0.967, 3: 0.9484, 4: 0.928, 5: 0.9080});
    expect(curve.curve, hasLength(6)); // now, then years 1-5
    expect(
      find.bySemanticsLabel(
        'Out of 100 people with answers like yours: about 99 after 1 year, about 97 after 2 years, '
        'about 95 after 3 years, about 93 after 4 years, about 91 after 5 years.',
      ),
      findsOneWidget,
    );
    expect(find.text('Built from your answers'), findsOneWidget);
    expect(find.text('Age 68'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Former smoker'), findsOneWidget);
    expect(find.text('Exercise 60 min/week'), findsOneWidget);
    expect(find.text('Apple Health'), findsNWidgets(2)); // height and sleep
    // Nothing is filled in: there is no 'We assumed' section.
    expect(find.text('We assumed'), findsNothing);
    expect(find.text('Add an answer'), findsNothing);
    await t.scrollUntilVisible(find.text('Not a promise, not a date'), 200, scrollable: find.byType(Scrollable).first);
    for (final line in ['Looks 5 years ahead at most', 'A US health survey', 'Links, not causes']) {
      expect(find.text(line), findsOneWidget);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('unsupported: the plain reason, Go back to my answers, no number and no bear heads', (t) async {
    const reason = 'Annual estimates support ages 35–79 only.';
    var backs = 0;
    await pumpForecast(t, forecastFrom(unavailableAssessment(message: reason)), onBack: () => backs++);
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
      await pumpHuman(t, forecast(forecastFrom(profileCJson())));
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
          client: FakeForecastClient()..answers.add(forecastFrom(unavailableAssessment(message: 'Not covered.'))),
          profile: profileC,
          onBack: () {},
        ),
      );
      expect(spriteAsset(t), 'assets/twin/bear/pose/shrug.png');
      await pumpHuman(t, FortuneCeremonyScreen(onAsk: () {}, onBack: () {}));
      expect(spriteAsset(t), 'assets/twin/bear/pose/hold_ball.png');
    });
  });

  test('every twin has every pose, with the hat or without it', () {
    expect(twinAsset(TwinType.human, TwinLook.calHat, TwinPose.holdBall), 'assets/twin/human/pose/hold_ball.png');
    expect(twinAsset(TwinType.human, TwinLook.calHat, TwinPose.sleep), 'assets/twin/human/pose/sleep.png');
    expect(twinAsset(TwinType.human, TwinLook.calHat), 'assets/twin/human/pose/stand.png');
    expect(twinAsset(TwinType.bear, TwinLook.calHat, TwinPose.shrug), 'assets/twin/bear/pose/shrug.png');
    expect(twinAsset(TwinType.bear, TwinLook.plain, TwinPose.holdBall), 'assets/twin/bear/pose_nohat/hold_ball.png');
    expect(twinAsset(TwinType.human, TwinLook.plain, TwinPose.shrug), 'assets/twin/human/pose_nohat/shrug.png');
    expect(twinFeetAnchor(TwinType.human, TwinLook.calHat, TwinPose.shrug), 0.9649);
    expect(twinFeetAnchor(TwinType.human, TwinLook.plain, TwinPose.sleep), 0.9668);
  });
}
