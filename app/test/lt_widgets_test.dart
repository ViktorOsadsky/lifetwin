import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/theme/lifetwin_theme.dart';
import 'package:lifesim/widgets/lt_buttons.dart';
import 'package:lifesim/widgets/lt_text_link.dart';
import 'package:lifesim/widgets/magic_ball_badge.dart';
import 'package:lifesim/widgets/pip.dart';
import 'package:lifesim/widgets/scene_paper.dart';
import 'package:lifesim/widgets/speech_bubble.dart';
import 'package:lifesim/widgets/twin.dart';
import 'package:lifesim/widgets/vector/shapes.dart';

/// Shows [child] on a 390x844 phone at [scale] text size with the LifeTwin theme.
Future<void> show(WidgetTester t, Widget child, {double scale = 1, bool reduceMotion = false}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: lifeTwinTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(LtSpace.gutter),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [child]),
          ),
        ),
      ),
    ),
  );
}

/// Renders at 1.0 and 2.0 without layout errors.
Future<void> expectFitsAtBothScales(WidgetTester t, Widget child) async {
  for (final scale in [1.0, 2.0]) {
    await show(t, child, scale: scale);
    expect(t.takeException(), isNull, reason: 'at text scale $scale');
  }
}

double faceDrop(WidgetTester t, Finder button) {
  final transform = t.widget<Transform>(find.descendant(of: button, matching: find.byType(Transform)).first);
  return transform.transform.getTranslation().y;
}

void main() {
  group('LtPrimaryButton', () {
    testWidgets('renders, is at least 96 pt plus its lip, taps, and announces itself', (t) async {
      var taps = 0;
      await show(t, LtPrimaryButton(label: 'Talk with Pip', onPressed: () => taps++));
      final b = find.byType(LtPrimaryButton);
      expect(find.text('Talk with Pip'), findsOneWidget);
      expect(t.getSize(b).height, greaterThanOrEqualTo(LtSize.primaryButton + LtLip.primary));
      expect(t.getSize(b).width, 390 - 2 * LtSpace.gutter);
      expect(t.getSemantics(b), isSemantics(label: 'Talk with Pip', isButton: true, isEnabled: true));
      await t.tap(b);
      expect(taps, 1);
    });

    testWidgets('pressing drops the face onto the lip', (t) async {
      await show(t, LtPrimaryButton(label: 'Yes', onPressed: () {}));
      final b = find.byType(LtPrimaryButton);
      expect(faceDrop(t, b), 0);
      final g = await t.startGesture(t.getCenter(b));
      await t.pump();
      expect(faceDrop(t, b), LtLip.primary);
      await g.up();
      await t.pump();
      expect(faceDrop(t, b), 0);
    });

    testWidgets('disabled: flat, does nothing, announced as disabled', (t) async {
      await show(t, const LtPrimaryButton(label: 'Yes', onPressed: null));
      final b = find.byType(LtPrimaryButton);
      expect(t.getSemantics(b), isSemantics(label: 'Yes', isButton: true, isEnabled: false));
      final g = await t.startGesture(t.getCenter(b));
      await t.pump();
      expect(faceDrop(t, b), 0);
      await g.up();
    });

    testWidgets('no overflow at text scale 2.0', (t) async {
      await expectFitsAtBothScales(t, LtPrimaryButton(label: 'Go back to my answers', onPressed: () {}));
    });
  });

  group('LtSecondaryButton', () {
    testWidgets('renders at least 78 pt plus its lip and taps', (t) async {
      var taps = 0;
      await show(t, LtSecondaryButton(label: 'What this means', onPressed: () => taps++));
      final b = find.byType(LtSecondaryButton);
      expect(t.getSize(b).height, greaterThanOrEqualTo(LtSize.secondaryButton + LtLip.secondary));
      await t.tap(b);
      expect(taps, 1);
    });

    testWidgets('a smaller height is clamped to 72 pt', (t) async {
      await show(t, LtSecondaryButton(label: 'Short', minHeight: 40, onPressed: () {}));
      expect(t.getSize(find.byType(LtSecondaryButton)).height, greaterThanOrEqualTo(LtSize.minButton));
    });

    testWidgets('no overflow at text scale 2.0', (t) async {
      await expectFitsAtBothScales(t, LtSecondaryButton(label: 'Use the keyboard', onPressed: () {}));
    });
  });

  group('LtBackButton and LtChoiceTile', () {
    testWidgets('Back is at least 56 pt and fits at 2.0', (t) async {
      var taps = 0;
      await show(t, Align(alignment: Alignment.centerLeft, child: LtBackButton(onPressed: () => taps++)));
      expect(t.getSize(find.byType(LtBackButton)).height, greaterThanOrEqualTo(LtSize.smallTap));
      await t.tap(find.text('Back'));
      expect(taps, 1);
      await expectFitsAtBothScales(t, LtBackButton(onPressed: () {}));
    });

    testWidgets('a selected tile is announced as selected', (t) async {
      await show(
        t,
        LtChoiceTile(selected: true, semanticLabel: 'About 91 in 100', onPressed: () {}, child: const Text('91')),
      );
      expect(
        t.getSemantics(find.byType(LtChoiceTile)),
        isSemantics(label: 'About 91 in 100', isButton: true, isSelected: true),
      );
      expect(t.getSize(find.byType(LtChoiceTile)).height, greaterThanOrEqualTo(LtSize.tile));
    });
  });

  group('LtTextLink', () {
    testWidgets('underlined, at least 56 pt, taps, fits at 2.0', (t) async {
      var taps = 0;
      await show(t, Center(child: LtTextLink(label: 'Skip this question', onPressed: () => taps++)));
      expect(t.getSize(find.byType(LtTextLink)).height, greaterThanOrEqualTo(LtSize.smallTap));
      expect(t.widget<Text>(find.text('Skip this question')).style!.decoration, TextDecoration.underline);
      expect(t.getSemantics(find.byType(LtTextLink)), isSemantics(label: 'Skip this question', isButton: true));
      await t.tap(find.text('Skip this question'));
      expect(taps, 1);
      await expectFitsAtBothScales(t, LtTextLink(label: 'Use the keyboard instead', onPressed: () {}));
    });
  });

  group('SpeechBubble', () {
    for (final tail in BubbleTail.values) {
      testWidgets('renders with tail ${tail.name} and fits at 2.0', (t) async {
        await expectFitsAtBothScales(
          t,
          SpeechBubble(tail: tail, child: Text('How tall are you?', style: LtText.question)),
        );
        expect(find.text('How tall are you?'), findsOneWidget);
      });
    }
  });

  group('Pip', () {
    for (final mood in PipMood.values) {
      testWidgets('draws $mood at its set size, labelled for screen readers', (t) async {
        await show(t, Center(child: Pip(mood: mood, height: 112)));
        final size = t.getSize(find.byType(Pip));
        expect(size.height, 112);
        expect(size.width, greaterThan(80));
        expect(find.bySemanticsLabel('Pip, ${mood.name}'), findsOneWidget);
        await expectFitsAtBothScales(t, Center(child: Pip(mood: mood)));
      });
    }

    testWidgets('bob floats only when motion is allowed', (t) async {
      await show(t, const Center(child: Pip(bob: true)));
      expect(t.hasRunningAnimations, isTrue);
      await show(t, const Center(child: Pip(bob: true)), reduceMotion: true);
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('reduced motion switches mood with no cross-fade', (t) async {
      await show(t, const Center(child: Pip(mood: PipMood.asking)), reduceMotion: true);
      await show(t, const Center(child: Pip(mood: PipMood.pleased)), reduceMotion: true);
      expect(t.hasRunningAnimations, isFalse);
      expect(find.bySemanticsLabel('Pip, pleased'), findsOneWidget);
    });
  });

  group('Twin, MagicBallBadge, ScenePaper', () {
    testWidgets('render at their set sizes and fit at 2.0', (t) async {
      await expectFitsAtBothScales(t, const Center(child: Twin(height: 200)));
      expect(t.getSize(find.byType(Twin)).height, 200);
      expect(find.bySemanticsLabel('Your twin, waving'), findsOneWidget);

      await expectFitsAtBothScales(t, const Center(child: MagicBallBadge()));
      expect(t.getSize(find.byType(MagicBallBadge)), const Size(150, 72));

      for (final kind in SceneKind.values) {
        await expectFitsAtBothScales(
          t,
          ScenePaper(kind: kind, child: const Positioned(left: 40, bottom: 6, child: Pip(height: 96))),
        );
        expect(t.getSize(find.byType(ScenePaper)).height, kind == SceneKind.room ? 400 : 150);
      }
    });
  });

  group('parseSvgPath', () {
    test('absolute and relative commands', () {
      expect(parseSvgPath('M0 0 L10 0 V10 H0 Z').getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
      expect(parseSvgPath('M15 5l-7 7 7 7').getBounds(), const Rect.fromLTRB(8, 5, 15, 19));
      expect(parseSvgPath('M0 0 C0 10 10 10 10 0 Q5 -5 0 0 Z').getBounds().width, closeTo(10, 0.01));
    });

    test('arcs are refused, not silently mis-drawn', () {
      expect(() => parseSvgPath('M0 0 a6.5 6.5 0 0 0 13 0'), throwsFormatException);
    });
  });

  test('theme: large readable defaults', () {
    final theme = lifeTwinTheme();
    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, LtColors.paper);
    for (final s in [theme.textTheme.bodyLarge, theme.textTheme.bodyMedium, theme.textTheme.bodySmall]) {
      expect(s!.fontSize, greaterThanOrEqualTo(18));
    }
    for (final style in [
      theme.filledButtonTheme.style,
      theme.elevatedButtonTheme.style,
      theme.outlinedButtonTheme.style,
    ]) {
      expect(style!.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(72));
    }
  });
}
