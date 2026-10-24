import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/widgets/whole_word_text.dart';

/// The app's real fonts, so word widths are the ones people see.
Future<void> loadFonts() async {
  await (FontLoader(LtFonts.display)..addFont(rootBundle.load('assets/fonts/fredoka/Fredoka-Variable.ttf'))).load();
  await (FontLoader(LtFonts.body)
        ..addFont(rootBundle.load('assets/fonts/atkinson_hyperlegible/AtkinsonHyperlegible-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/atkinson_hyperlegible/AtkinsonHyperlegible-Bold.ttf')))
      .load();
}

/// Every laid-out paragraph whose lines break inside a word ("Contin|ue"), or that was
/// cut off. A break may follow whitespace, a hyphen or a slash.
List<String> brokenWords(WidgetTester t) {
  final problems = <String>[];
  for (final p in t.allRenderObjects.whereType<RenderParagraph>()) {
    if (!p.hasSize) continue;
    final text = p.text.toPlainText(includeSemanticsLabels: false);
    if (p.didExceedMaxLines) problems.add('cut off: "$text"');
    final painter = TextPainter(
      text: p.text,
      textAlign: p.textAlign,
      textDirection: p.textDirection,
      textScaler: p.textScaler,
      maxLines: p.maxLines,
      locale: p.locale,
      strutStyle: p.strutStyle,
      textWidthBasis: p.textWidthBasis,
      textHeightBehavior: p.textHeightBehavior,
    )..layout(minWidth: p.constraints.minWidth, maxWidth: p.constraints.maxWidth);
    final starts = <int>{};
    for (var o = 0; o < text.length; o++) {
      starts.add(painter.getLineBoundary(TextPosition(offset: o)).start);
    }
    painter.dispose();
    for (final s in starts) {
      if (s <= 0 || s >= text.length) continue;
      final before = text[s - 1], after = text[s];
      if (!_breakable(before) && !_breakable(after)) {
        problems.add('"${text.substring(0, s)}|${text.substring(s)}"');
      }
    }
  }
  return problems;
}

bool _breakable(String c) => c.trim().isEmpty || c == '-' || c == '/';

/// [child] on a 390x844 phone at text [scale], in the app theme.
Future<void> show(WidgetTester t, Widget child, {double scale = 1}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: lifeTwinTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [child]),
          ),
        ),
      ),
    ),
  );
}

/// The scaler the inner [Text] of the [WholeWordText] showing [label] was given.
TextScaler? fitted(WidgetTester t, String label) =>
    t.widget<Text>(find.descendant(of: find.byType(WholeWordText), matching: find.text(label))).textScaler;

double widthOf(String word, TextStyle style, TextScaler scaler) {
  final p = TextPainter(
    text: TextSpan(text: word, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  final w = p.width;
  p.dispose();
  return w;
}

void main() {
  setUpAll(loadFonts);

  group('WholeWordText', () {
    testWidgets('at a normal size it is plain text at the chosen scale', (t) async {
      await show(t, WholeWordText('Continue', style: LtText.display(26)), scale: 1);
      expect(fitted(t, 'Continue'), isNull);
      expect(brokenWords(t), isEmpty);
    });

    testWidgets('large text whose words all fit keeps the chosen size and wraps at spaces', (t) async {
      await show(t, WholeWordText('Good to see you, I am glad', style: LtText.body()), scale: 2);
      expect(fitted(t, 'Good to see you, I am glad'), isNull);
      expect(t.getSize(find.byType(WholeWordText)).height, greaterThan(2 * 22 * 2)); // wrapped
      expect(brokenWords(t), isEmpty);
    });

    testWidgets('a word wider than the line shrinks just enough to fit whole', (t) async {
      const room = 200.0;
      final style = LtText.display(26);
      await show(
        t,
        Center(
          child: SizedBox(
            width: room,
            child: WholeWordText('Continue', style: style),
          ),
        ),
        scale: 3,
      );
      const three = TextScaler.linear(3);
      expect(widthOf('Continue', style, three), greaterThan(room)); // would break as plain text
      final s = fitted(t, 'Continue')!;
      final w = widthOf('Continue', style, s);
      expect(w, lessThanOrEqualTo(room));
      expect(w, greaterThan(room * 0.9)); // not smaller than needed
      expect(brokenWords(t), isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets('a plain Text in the same place breaks the word (the checker catches it)', (t) async {
      await show(
        t,
        Center(
          child: SizedBox(width: 200, child: Text('Continue', style: LtText.display(26))),
        ),
        scale: 3,
      );
      expect(brokenWords(t), isNotEmpty);
    });

    testWidgets('the whole text shrinks by one factor; lines still break only at spaces', (t) async {
      const line = 'Let an AI helper read hard answers?';
      await show(t, WholeWordText(line, style: LtText.display(30)), scale: 3.12);
      final s = fitted(t, line)!;
      expect(s.scale(10), lessThan(31.2));
      expect(t.getSize(find.byType(WholeWordText)).height, greaterThan(32 * s.scale(1) * 1.15 * 2)); // still wraps
      expect(brokenWords(t), isEmpty);
    });

    testWidgets('rich text: a word made of two styles counts as one word', (t) async {
      await show(
        t,
        WholeWordText.rich(
          const TextSpan(
            children: [
              TextSpan(text: 'Out of 100, about '),
              TextSpan(
                text: '88',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: '% were still living afterwards.'),
            ],
          ),
          style: LtText.display(26),
        ),
        scale: 3.12,
      );
      expect(brokenWords(t), isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets('answers intrinsic sizes (IntrinsicHeight, SliverFillRemaining) at the fitted size', (t) async {
      await show(
        t,
        IntrinsicHeight(
          child: SizedBox(width: 200, child: WholeWordText('Continue', style: LtText.display(26))),
        ),
        scale: 3,
      );
      expect(t.takeException(), isNull);
      final box = t.getSize(find.byType(IntrinsicHeight));
      expect(box.height, closeTo(t.getSize(find.text('Continue')).height, 0.5));
      expect(brokenWords(t), isEmpty);
    });

    test('wordFitFactor is 1 when the widest word fits and below 1 when it does not', () async {
      final style = LtText.display(26);
      const span = TextSpan(text: 'No, change it');
      expect(wordFitFactor(span, style, TextScaler.noScaling, 300, TextDirection.ltr), 1);
      final f = wordFitFactor(span, style, const TextScaler.linear(3.12), 150, TextDirection.ltr);
      expect(f, lessThan(1));
      expect(widthOf('change', style, ShrunkTextScaler(const TextScaler.linear(3.12), f)), lessThanOrEqualTo(150));
    });
  });

  group('shared widgets never break a word', () {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('buttons, links, chips, bubble and progress at text scale $scale', (t) async {
        await show(
          t,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const StepProgress(step: 3, total: 11),
              LinkButton(label: 'Settings', icon: Icons.settings_outlined, onTap: () {}),
              const SizedBox(height: 12),
              LipButton(label: 'Continue', height: 72, onTap: () {}),
              LipButton(label: "Yes, I'll talk", icon: Icons.mic_none_rounded, height: 72, onTap: () {}),
              LipButton(
                label: 'No, change it',
                icon: Icons.edit_rounded,
                kind: LipKind.secondary,
                height: 72,
                onTap: () {},
              ),
              LipButton(label: 'Go back to my answers', onTap: () {}),
              LipButton(label: 'Use my Apple Health', icon: Icons.favorite_border_rounded, kind: LipKind.secondary, onTap: () {}),
              LtToggleChip(label: 'AI helper: Off', value: false, onChanged: (_) {}),
              const Bubble(text: "Let's talk first, so I can make your forecast."),
              Center(
                child: LinkButton(label: 'Skip this question', onTap: () {}),
              ),
            ],
          ),
          scale: scale,
        );
        expect(t.takeException(), isNull);
        expect(brokenWords(t), isEmpty);
      });
    }
  });
}
