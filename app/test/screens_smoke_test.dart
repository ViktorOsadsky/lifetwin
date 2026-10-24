import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetwin/app/app.dart';
import 'package:lifetwin/app/router.dart';
import 'package:lifetwin/features/activity/activity_models.dart';
import 'package:lifetwin/state/confirmed_baseline.dart';
import 'package:lifetwin/state/experiment_state.dart';
import 'package:lifetwin/state/game_health.dart';
import 'package:lifetwin/state/intake_answers.dart';
import 'package:lifetwin/state/twin_look.dart';
import 'package:lifetwin/widgets/lt_twin.dart';

const _sample = IntakeAnswers(
  age: 34,
  sex: Sex.female,
  heightCm: 170,
  weightKg: 70,
  sleepHours: 7,
  activityMinutes: 30,
  smoking: Smoking.never,
  drinksPerWeek: 3,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  String location, {
  IntakeAnswers? answers,
}) async {
  tester.view.physicalSize = const Size(780, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  if (answers != null) {
    container.read(intakeAnswersProvider.notifier).set(answers);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: LifeTwinApp(router: buildRouter(initialLocation: location)),
    ),
  );
  await _settle(tester);
  return container;
}

/// Tier 3+ backgrounds animate forever, so settle by time, not by quiet.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(f);
  await tester.pump(); // lay out the scrolled position before tapping
  await tester.tap(f);
  await _settle(tester);
}

Future<void> _say(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await _settle(tester);
}

void main() {
  testWidgets('room shows tier chip, hearts and the four props', (
    tester,
  ) async {
    await _pump(tester, '/room');
    expect(find.text('Steady'), findsOneWidget);
    for (final p in ['Fortune', 'Experiment', 'Quiz', 'Studio']) {
      expect(find.text(p), findsOneWidget);
    }
    expect(find.textContaining('3 / 3'), findsOneWidget);
  });

  testWidgets('room: a prop makes the twin react on stage, then opens', (
    tester,
  ) async {
    await _pump(tester, '/room');
    expect(tester.widget<Twin>(find.byType(Twin)).pose, TwinPose.rest);
    await tester.tap(find.text('Quiz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // The response is on the twin, in place, before the mode opens.
    expect(tester.widget<Twin>(find.byType(Twin)).pose, TwinPose.cheer);
    expect(find.text('Quiz arena'), findsNothing);
    // A second tap during the reaction is ignored, not queued.
    await tester.tap(find.text('Studio'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Quiz arena'), findsOneWidget);
    expect(find.text('Twin studio'), findsNothing);
  });

  testWidgets('room: tapping the twin makes it wave, then it settles', (
    tester,
  ) async {
    await _pump(tester, '/room');
    await tester.tap(find.byType(Twin));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Twin>(find.byType(Twin)).pose, TwinPose.wave);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Twin>(find.byType(Twin)).pose, TwinPose.rest);
  });

  testWidgets('room: semantic activation opens a prop', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, '/room');
    tester.semantics.tap(find.semantics.byLabel(RegExp(r'^Studio$')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Twin studio'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('quiz: semantic activation answers and the twin reacts', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final c = await _pump(tester, '/quiz');
    tester.semantics.tap(find.semantics.byLabel(RegExp(r'^75 minutes$')));
    await _settle(tester);
    expect(c.read(gameHealthProvider).hearts, 2);
    expect(tester.widget<Twin>(find.byType(Twin)).pose, TwinPose.huddle);
    expect(find.text('Help it recover'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('intake: voice unavailable, unit clarification, full run', (
    tester,
  ) async {
    final container = await _pump(tester, '/intake');
    expect(find.textContaining('Voice coming soon'), findsOneWidget);
    expect(find.text('First, how old are you?'), findsOneWidget);

    await _say(tester, '17');
    expect(find.textContaining('adults aged 18'), findsOneWidget);
    await _say(tester, '34');
    expect(find.textContaining('Which sex'), findsOneWidget);
    await _tap(tester, find.text('Female'));
    expect(find.text('How tall are you?'), findsOneWidget);

    await _say(tester, '170');
    expect(find.text('Is that cm or inches?'), findsOneWidget);
    await _tap(tester, find.text('cm'));
    expect(find.text('And your weight?'), findsOneWidget);

    await _say(tester, '154 lb');
    await _say(tester, '7.5');
    await _say(tester, '150');
    await _tap(tester, find.text('Never'));
    await _say(tester, '3');

    expect(find.text('Review my answers'), findsOneWidget);
    final a = container.read(intakeAnswersProvider);
    expect(a.isComplete, isTrue);
    expect(a.heightCm, 170);
    expect(a.weightKg, closeTo(69.85, 0.05));
    // Intake never writes the confirmed baseline.
    expect(container.read(confirmedBaselineProvider).hasActivity, isFalse);
  });

  testWidgets('confirm: editable rows, Looks right needs every answer', (
    tester,
  ) async {
    await _pump(tester, '/confirm');
    expect(find.text('Confirm your answers'), findsOneWidget);
    expect(find.text('Add'), findsNWidgets(8));
    expect(find.text('Fill in every row to continue.'), findsOneWidget);
  });

  testWidgets('confirm: editing a row updates the summary', (tester) async {
    final c = await _pump(tester, '/confirm', answers: _sample);
    expect(find.text('34 years'), findsOneWidget);
    await _tap(tester, find.text('34 years'));
    await tester.enterText(find.byType(TextField), '35');
    await _tap(tester, find.text('Save'));
    expect(find.text('35 years'), findsOneWidget);
    expect(c.read(intakeAnswersProvider).age, 35);
    await _tap(tester, find.text('Looks right'));
    expect(find.text('Magic ball'), findsOneWidget);
  });

  testWidgets('fortune: placeholder outlook with both chips', (tester) async {
    await _pump(tester, '/fortune');
    expect(find.text('[xx.x %]'), findsNothing);
    await _tap(tester, find.text('Reveal my outlook'));
    expect(find.text('[xx.x %]'), findsOneWidget);
    expect(find.text('Modeled association, not cause'), findsOneWidget);
    expect(find.text('Illustrative — model not connected'), findsOneWidget);
    await _tap(tester, find.text('20 years'));
    expect(find.textContaining('20-year'), findsOneWidget);
    await _tap(tester, find.text('See the curve'));
    expect(find.text('Outlook curve'), findsOneWidget);
    expect(find.textContaining('Schematic shape'), findsOneWidget);
  });

  testWidgets('levers: placeholders, no-effect and uncertain labels', (
    tester,
  ) async {
    await _pump(tester, '/levers');
    expect(find.text('±[x.x pts]'), findsWidgets);
    // Warm, honest words instead of "No modeled effect" / "Uncertain".
    expect(
      find.text('Doesn’t change the model, but it may still feel good'),
      findsOneWidget,
    );
    expect(find.text('We’re not sure yet'), findsOneWidget);
    expect(find.text('Uncertain'), findsNothing);
    expect(find.text('Research a plan'), findsOneWidget);
  });

  testWidgets('plan: model and evidence rows, try-on sheet, skip', (
    tester,
  ) async {
    final c = await _pump(tester, '/plan');
    expect(find.text('[SOURCE]'), findsNWidgets(3));
    expect(find.text('±[x.x pts] at 10 y'), findsNWidgets(3));
    await _tap(tester, find.text('Skip').first);
    expect(find.text('Skipped'), findsOneWidget);
    // Tapping the row opens the try-on sheet (no filled button per row).
    await _tap(tester, find.text('Sleep one more hour a night'));
    expect(find.text('Assumed change'), findsOneWidget);
    expect(find.textContaining('Sleep', findRichText: true), findsWidgets);
    expect(find.textContaining('Your real baseline is not'), findsOneWidget);
    expect(c.read(experimentProvider), isNull);
  });

  testWidgets('try-on: confirm starts an experiment, baseline untouched', (
    tester,
  ) async {
    final c = await _pump(tester, '/try-on');
    expect(find.text('Assumed change'), findsOneWidget);
    await _tap(tester, find.text('Confirm and try it'));
    expect(c.read(experimentProvider)?.activityMinutes, 180);
    expect(c.read(confirmedBaselineProvider).hasActivity, isFalse);
    expect(find.text('Experiment'), findsWidgets);
  });

  testWidgets('experiment: Reset clears the experiment, never the baseline', (
    tester,
  ) async {
    final c = await _pump(tester, '/experiment');
    c
        .read(confirmedBaselineProvider.notifier)
        .confirmActivity(minutesPerWeek: 90, source: ActivitySource.manual);
    c.read(experimentProvider.notifier).setActivity(240);
    await _settle(tester);
    expect(find.text('Baseline'), findsOneWidget);
    expect(find.text('Thriving'), findsNothing);
    expect(find.text('Good'), findsOneWidget); // experiment tier 3
    expect(find.text('Steady'), findsOneWidget); // baseline tier 2
    expect(find.text('±[x.x pts]'), findsOneWidget);

    await _tap(tester, find.text('Reset experiment'));
    expect(c.read(experimentProvider), isNull);
    expect(c.read(confirmedBaselineProvider).activityMinutesPerWeek, 90);
    expect(find.text('Steady'), findsNWidgets(2));
  });

  testWidgets('experiment: offers Record real measurements separately', (
    tester,
  ) async {
    await _pump(tester, '/experiment');
    await _tap(tester, find.text('Record real measurements'));
    expect(find.text('Confirm as my baseline'), findsOneWidget);
  });

  testWidgets('quiz: wrong answer costs a heart, feedback is game-only', (
    tester,
  ) async {
    final c = await _pump(tester, '/quiz');
    expect(find.textContaining('· sample'), findsOneWidget);
    expect(find.textContaining('Question 1 of 3'), findsOneWidget);
    await _tap(tester, find.text('75 minutes'));
    expect(find.textContaining('Game health only'), findsOneWidget);
    expect(c.read(gameHealthProvider).hearts, 2);
    expect(c.read(gameHealthProvider).mood, TwinMood.sick);
    await _tap(tester, find.text('Help it recover'));
    expect(find.textContaining('Question 1 of 3'), findsOneWidget);
    await _tap(tester, find.text('150 minutes'));
    expect(c.read(gameHealthProvider).hearts, 3);
    await _tap(tester, find.text('Next question'));
    expect(find.textContaining('Question 2 of 3'), findsOneWidget);
  });

  testWidgets('quiz feedback: direct visit has a safe empty state', (
    tester,
  ) async {
    await _pump(tester, '/quiz-feedback');
    expect(find.text('Answer a question first.'), findsOneWidget);
  });

  testWidgets('studio: cosmetics change the look, not numbers', (tester) async {
    final c = await _pump(tester, '/studio');
    expect(find.text('Looks never change your numbers'), findsOneWidget);
    await _tap(tester, find.text('Hair'));
    await _tap(tester, find.text('Curly'));
    expect(c.read(twinLookProvider).hairStyle, TwinHair.curly);
    await _tap(tester, find.text('Extras'));
    await _tap(tester, find.text('Glasses'));
    expect(c.read(twinLookProvider).extra, TwinExtra.glasses);
    expect(c.read(confirmedBaselineProvider).hasActivity, isFalse);
  });
}
