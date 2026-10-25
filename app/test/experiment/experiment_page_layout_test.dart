import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/experiment/experiment_page.dart';
import 'package:lifesim/experiment/widgets/pills.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/widgets/lip_button.dart';

import '../support/app_fonts.dart';

const _maximumScale = 53 / 17;
const _bodyKey = Key('body-start');
const _endKey = Key('body-end');

void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpPage(
    WidgetTester t, {
    required double width,
    required double scale,
    required String title,
    required VoidCallback onBack,
    bool whatIf = false,
    double height = 700,
  }) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(top: 44, bottom: 24);
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: child!,
        ),
        home: ExperimentPage(
          title: title,
          whatIfPill: whatIf,
          onBack: onBack,
          body: const Column(
            children: [
              Text('Body starts here', key: _bodyKey),
              SizedBox(height: 900),
              Text('Body ends here', key: _endKey),
            ],
          ),
          dock: const SizedBox(height: 64, child: Center(child: Text('Dock action'))),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final width in [320.0, 375.0]) {
    for (final scale in [1.6, _maximumScale]) {
      for (final title in ['Experiment', 'Side by side', 'About these ideas and your what-if changes']) {
        testWidgets('full title and navigation at $width / $scale: $title', (t) async {
          var backs = 0;
          final semantics = t.ensureSemantics();
          try {
            await pumpPage(
              t,
              width: width,
              scale: scale,
              title: title,
              whatIf: title == 'Side by side',
              onBack: () => backs++,
            );
            final text = find.text(title);
            final paragraph = t.renderObject<RenderParagraph>(text);
            expect(paragraph.didExceedMaxLines, isFalse, reason: 'the complete heading must be laid out');
            expect(paragraph.textScaler.scale(26), closeTo(26 * scale, 0.001), reason: 'no scale clamp');
            expect(find.bySemanticsLabel(title), findsOneWidget);
            final titleRect = t.getRect(text);
            final back = find.byType(RoundBackButton);
            final backRect = t.getRect(back);
            expect(titleRect.top, greaterThanOrEqualTo(backRect.bottom));
            // Inspect every non-space glyph. A word wider than the full phone may
            // wrap; no glyph may be omitted, ellipsized or clipped by a fixed box.
            for (var i = 0; i < title.length; i++) {
              if (title[i] == ' ') continue;
              final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
              expect(boxes, isNotEmpty, reason: 'glyph $i must be laid out');
              for (final box in boxes) {
                expect(titleRect.left + box.left, greaterThanOrEqualTo(0));
                expect(titleRect.left + box.right, lessThanOrEqualTo(width));
                expect(titleRect.top + box.top, greaterThanOrEqualTo(backRect.bottom));
                expect(titleRect.top + box.bottom, lessThanOrEqualTo(t.getRect(find.byKey(_bodyKey)).top));
              }
            }
            final vertical = Scrollable.of(t.element(find.byKey(_bodyKey))).position;
            expect(t.getRect(find.byKey(_bodyKey)).top, greaterThanOrEqualTo(titleRect.bottom));
            if (title == 'Side by side') {
              final pill = t.getRect(find.byType(ModePill));
              expect(pill.overlaps(titleRect), isFalse);
              expect(pill.overlaps(backRect), isFalse);
            }
            await t.ensureVisible(find.byKey(_endKey));
            await t.pumpAndSettle();
            expect(vertical.pixels, greaterThan(0));
            final end = t.getRect(find.byKey(_endKey));
            final dock = t.getRect(find.text('Dock action'));
            expect(end.bottom, lessThanOrEqualTo(dock.top));
            expect(t.getRect(back), backRect, reason: 'Back stays pinned while the title/body scroll');
            expect(backRect.width, greaterThanOrEqualTo(44));
            expect(backRect.height, greaterThanOrEqualTo(44));
            await t.tap(back);
            expect(backs, 1);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }

  testWidgets('a long large title scrolls on a small landscape viewport without trapping Back or the body', (t) async {
    var backs = 0;
    await pumpPage(
      t,
      width: 568,
      height: 320,
      scale: _maximumScale,
      title: 'About these ideas and your what-if changes',
      whatIf: true,
      onBack: () => backs++,
    );
    await t.ensureVisible(find.byKey(_endKey));
    await t.pumpAndSettle();
    final end = t.getRect(find.byKey(_endKey));
    expect(end.bottom, lessThanOrEqualTo(t.getRect(find.text('Dock action')).top));
    await t.tap(find.byType(RoundBackButton));
    expect(backs, 1);
    expect(t.takeException(), isNull);
  });
}
