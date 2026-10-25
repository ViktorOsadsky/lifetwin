import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/room/room_layout_data.dart';
import 'package:lifesim/room/room_scene.dart';
import 'package:lifesim/room/room_sim.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/wellness/home_panel.dart';
import 'package:lifesim/wellness/today_card.dart';

import '../support/app_fonts.dart';
import 'coach_test.dart' show FakeCoach;
import 'today_card_test.dart' show fourSlots;

// Match the observed maximum iOS accessibility size: 17 pt -> 53 pt.
const _ax5 = 53 / 17;

Future<void> _pump(WidgetTester t, Widget child, {double scale = 1, double width = 375}) async {
  t.view.physicalSize = Size(width, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: lifeTwinTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 844), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

/// A text can fit its render box while still breaking "Higher" into letters.
/// Check the actual laid-out glyph boxes for every word, as well as clipping.
void _wholeWords(WidgetTester t, Finder finder, double scale) {
  final paragraph = t.renderObject<RenderParagraph>(finder);
  final text = paragraph.text.toPlainText();
  expect(paragraph.didExceedMaxLines, isFalse, reason: text);
  expect(paragraph.textScaler.scale(17), closeTo(17 * scale, 1e-8), reason: 'chosen size is preserved');
  for (final word in RegExp(r'\S+').allMatches(text)) {
    final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: word.start, extentOffset: word.end));
    expect(boxes, hasLength(1), reason: '${word.group(0)} must stay on one line');
    expect(boxes.single.left, greaterThanOrEqualTo(-0.5));
    expect(boxes.single.right, lessThanOrEqualTo(paragraph.size.width + 0.5));
    expect(boxes.single.bottom, lessThanOrEqualTo(paragraph.size.height + 0.5));
  }
}

class _ActivitySim extends RoomSim {
  _ActivitySim() : super(layout: roomLayout, reduced: true);
  RoomActivity current = RoomActivity.relaxing;
  @override
  RoomActivity get activity => current;
  void wander() {
    current = RoomActivity.walking;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  testWidgets('ambient activity updates are quiet but retain their current label and action', (t) async {
    final semantics = t.ensureSemantics();
    try {
      final sim = _ActivitySim();
      addTearDown(sim.dispose);
      var tapped = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                RoomScene(
                  sim: sim,
                  appearance: const TwinAppearance(name: 'Mochi'),
                  onActivityTap: () => tapped++,
                ),
                TextButton(onPressed: () {}, child: const Text('Unrelated control')),
              ],
            ),
          ),
        ),
      );
      await t.pump();
      for (final activity in ['relaxing', 'walking']) {
        final node = t.getSemantics(find.bySemanticsLabel('Mochi is $activity. Change what Mochi does.'));
        expect(node.flagsCollection.isLiveRegion, isFalse);
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(find.bySemanticsLabel('Unrelated control'), findsOneWidget);
        sim.wander();
        await t.pump();
      }
      await t.tap(find.byKey(const ValueKey('room-activity')));
      expect(tapped, 1);
      await t.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  for (final scale in [1.0, 1.6, _ax5]) {
    testWidgets('score directions support intrinsic sheet layout at $scale text', (t) async {
      await _pump(t, const IntrinsicHeight(child: ScoreScale(score: 0.59)), scale: scale);
      for (final label in ['‹ Higher risk', 'Average', 'Better health ›']) {
        _wholeWords(t, find.text(label), scale);
      }
      expect(t.takeException(), isNull);
    });
    for (final width in [375.0, 402.0]) {
      testWidgets('score directions stay whole at $scale text / $width width', (t) async {
        await _pump(t, const ScoreScale(score: 0.59, percentile: 86), scale: scale, width: width);
        for (final label in ['‹ Higher risk', 'Average', 'Better health ›']) {
          _wholeWords(t, find.text(label), scale);
        }
        final lower = t.getRect(find.text('‹ Higher risk'));
        final middle = t.getRect(find.text('Average'));
        final upper = t.getRect(find.text('Better health ›'));
        expect(lower.overlaps(middle), isFalse);
        expect(upper.overlaps(middle), isFalse);
        expect(t.takeException(), isNull);
      });

      testWidgets('Today keeps a readable preview and both actions at $scale text / $width width', (t) async {
        final coach = FakeCoach()..responses.add(fourSlots());
        var opened = 0;
        var checked = 0;
        await _pump(
          t,
          TodayWithMochiCard(
            client: coach,
            confirmedContext: () => {},
            onOpen: () => opened++,
            condensed: true,
            trailing: TextButton(onPressed: () => checked++, child: const Text('Check in')),
          ),
          scale: scale,
          width: width,
        );
        const summary = 'Today: seated marching · add a vegetable to dinner · lights out by 10';
        final summaryFinder = find.text(summary, findRichText: true);
        expect(summaryFinder, findsOneWidget);
        if (scale > 1) {
          _wholeWords(t, summaryFinder, scale);
        } else {
          final paragraph = t.renderObject<RenderParagraph>(summaryFinder);
          expect(paragraph.maxLines, 2, reason: 'normal-size Home keeps a compact preview');
          expect(paragraph.text.toPlainText(), summary, reason: 'the full plan remains in the accessible text');
        }
        expect(t.getRect(summaryFinder).overlaps(t.getRect(find.text('Check in'))), isFalse);
        await t.ensureVisible(summaryFinder);
        await t.tap(summaryFinder);
        expect(opened, 1);
        await t.ensureVisible(find.text('Check in'));
        await t.tap(find.text('Check in'));
        expect(checked, 1);
        expect(opened, 1, reason: 'Check in keeps its separate action');
        expect(t.takeException(), isNull);
      });
    }
  }
}
