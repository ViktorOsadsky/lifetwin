import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/quiz/quiz_game.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/quiz/quiz_screen.dart';

import 'models_and_quiz_test.dart' show question;
import 'screens_test.dart' show phone, reveal;

void main() {
  testWidgets(
    'selection, check, explanation and practice have distinct effects',
    (t) async {
      final q = QuizQuestion.fromJson(question());
      final game = QuizGame([q]);
      addTearDown(game.dispose);
      await phone(t, QuizScreen(onBack: () {}, game: game));
      await reveal(t, find.text('Start quiz'));
      await t.tap(find.text('Start quiz'));
      await t.pump();
      await reveal(t, find.text('First label'));
      await t.tap(find.text('First label'));
      await t.pump();
      expect(game.answerFor(q), isNull);
      expect(game.gameHealth, 100);
      await reveal(t, find.text('Check my answer'));
      await t.tap(find.text('Check my answer'));
      await t.pump();
      expect(game.gameHealth, 95);
      await reveal(t, find.text('Read why'));
      await t.tap(find.text('Read why'));
      await t.pump();
      expect(game.gameHealth, 95);
      await reveal(t, find.text('Got it'));
      await t.tap(find.text('Got it'));
      await t.pump();
      expect(game.gameHealth, 100);
      await reveal(t, find.text('Try again for practice · No score'));
      await t.tap(find.text('Try again for practice · No score'));
      await t.pump();
      await t.scrollUntilVisible(
        find.text('Second label'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Second label'));
      await t.pump();
      await reveal(t, find.text('Check my answer'));
      await t.tap(find.text('Check my answer'));
      await t.pump();
      expect(game.answerFor(q), 'a');
      expect(game.gameHealth, 100);
      await reveal(t, find.text('Round done'));
      await t.tap(find.text('Round done'));
      await t.pump();
      expect(find.text('Round done. Nice exploring!'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('leaving a round is optional and never resets game health', (
    t,
  ) async {
    var leaves = 0;
    final q = QuizQuestion.fromJson(question());
    final game = QuizGame([q])..answer(q, 'a');
    addTearDown(game.dispose);
    await phone(t, QuizScreen(onBack: () => leaves++, game: game), scale: 2);
    await reveal(t, find.text('Start quiz'));
    await t.tap(find.text('Start quiz'));
    await t.pump();
    await t.scrollUntilVisible(
      find.byType(RoundBackButton),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.byType(RoundBackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep playing'));
    await t.pumpAndSettle();
    expect(leaves, 0);
    await t.tap(find.byType(RoundBackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('Leave quiz'));
    await t.pumpAndSettle();
    expect(leaves, 1);
    expect(game.gameHealth, 95);
    expect(t.takeException(), isNull);
  });
}
