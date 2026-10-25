import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/checkin/outlook_change.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';

import '../support/app_fonts.dart';
import '../support/assessments.dart';

import 'package:lifesim/voice/fakes.dart';

import '../support/fake_weekly_guide.dart';
import 'daily_checkin_test.dart' show profile;

TwinAssessment at(double p5, {bool extrapolated = false}) {
  final a = availableAssessment({1: 0.99, 2: 0.98, 3: 0.97, 4: 0.96, 5: p5 / 100});
  return TwinAssessment({...a, if (extrapolated) 'extrapolated': true});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  group('outlook change: real updates anchor on this week (Z-17, Z-33, Z-34)', () {
    test('up under 1: "Up a little", Rosa 96.9201 to 97.8238', () {
      final c = OutlookChange.between(at(96.9201), at(97.8238));
      expect(c.kind, OutlookChangeKind.up);
      expect(c.headline, 'Up a little');
      expect(c.subline, 'Less than 1 more in 100 still alive, at 5 years');
      expect(c.exact, 'Last week 96.9 in 100, this week 97.8 in 100: 0.9 more');
      expect(c.showsArrays, isFalse);
    });

    test('1 or more: this week = round(current), gap = round(difference), last week = this week - gap', () {
      // June: 87.48 to 93.81 (6.33): round(93.81) = 94, round(6.33) = 6, last week 88.
      var c = OutlookChange.between(at(87.48), at(93.81));
      expect(
        (c.kind, c.thisWeek, c.gap, c.lastWeek, c.headline),
        (OutlookChangeKind.moreBig, 94, 6, 88, 'About 6 more in 100'),
      );
      expect(c.showsArrays, isTrue);
      // Age 82 (extrapolated): 90.56 to 93.26 (2.70): 93, 3, last week 90; the badge caveat rides along.
      c = OutlookChange.between(at(90.56), at(93.26, extrapolated: true));
      expect((c.thisWeek, c.gap, c.lastWeek, c.headline), (93, 3, 90, 'About 3 more in 100'));
      expect(c.caveat, extrapolationCaveat);
    });

    test('down a little, about the same, and fewer', () {
      var c = OutlookChange.between(at(97.8238), at(96.9201));
      expect((c.kind, c.headline, c.weeksVary), (OutlookChangeKind.down, 'Down a little', true));
      expect(c.subline, 'Less than 1 fewer in 100 still alive, at 5 years');
      c = OutlookChange.between(at(90.000), at(90.013));
      expect((c.kind, c.headline), (OutlookChangeKind.same, 'About the same'));
      expect(c.subline, 'Still alive at 5 years');
      c = OutlookChange.between(at(94), at(91.4));
      expect((c.kind, c.headline, c.gap), (OutlookChangeKind.fewerBig, 'About 3 fewer in 100', 3));
    });

    test('no number unless both are available: the status and what is still needed', () {
      final missing = TwinAssessment({
        ...unavailableAssessment(
          status: 'missing_inputs',
          message: 'Complete every model input.',
          missing: ['sedentary_min_day'],
        ),
      });
      for (final c in [
        OutlookChange.between(at(95), missing),
        OutlookChange.between(missing, at(95)),
        OutlookChange.between(null, at(95)),
      ]) {
        expect(c.kind, OutlookChangeKind.unavailable);
        expect(c.hasNumber, isFalse);
        expect(c.thisWeek, isNull);
        expect(c.gap, isNull);
        expect(c.exact, isNull);
      }
      final c = OutlookChange.between(at(95), missing);
      expect(c.headline, 'No number yet');
      expect(c.subline, 'Still needed: time spent sitting each day');
    });
  });

  testWidgets('a weekly check-in: the engine controller records it once, then the outlook update shows', (t) async {
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => DateTime(2026, 11, 1, 18),
    );
    await repo.saveConversationProfile(profile);
    final before = repo.current!.percentByYear[5]!;
    final guide = FakeWeeklyGuide();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: (c, child) => CheckInScope(
          repository: repo,
          guide: guide,
          speechInput: FakeSpeechInput(),
          speechOutput: FakeSpeechOutput(),
          appearance: look,
          now: () => DateTime(2026, 11, 1, 18),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openCheckIn(context, kind: CheckInKind.weekly),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Weekly check-in'), findsWidgets);
    await t.enterText(find.byType(TextField), '3 hours');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    expect(find.text('Yes'), findsOneWidget);
    expect(repo.store.checkins, isEmpty);
    expect(repo.profile['sedentary_min_day'], 360);
    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    expect(repo.store.checkins.single.kind, 'weekly');
    expect(repo.profile['sedentary_min_day'], 180);
    expect(find.text('Outlook updated'), findsOneWidget);
    final after = repo.current!.percentByYear[5]!;
    expect(after, isNot(before));
    expect(find.text('Linked, not proven.'), findsOneWidget);
    expect(find.text('Exact numbers'), findsOneWidget);
    expect(find.text('Your confirmed week'), findsOneWidget);
  });

  testWidgets('the weekly check-in shows the same Keep going / Stop for today choice for the care reply', (t) async {
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => DateTime(2026, 11, 1, 18),
    );
    await repo.saveConversationProfile(profile);
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: (c, child) => CheckInScope(
          repository: repo,
          guide: FakeWeeklyGuide(),
          speechInput: FakeSpeechInput(),
          speechOutput: FakeSpeechOutput(),
          appearance: look,
          now: () => DateTime(2026, 11, 1, 18),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openCheckIn(context, kind: CheckInKind.weekly),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'awful');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    expect(find.text('Keep going'), findsOneWidget);
    expect(find.text('Stop for today'), findsOneWidget);
    expect(find.text('Call 911'), findsNothing, reason: 'not the emergency pause');
    await t.tap(find.text('Stop for today'));
    await t.pumpAndSettle();
    expect(find.text('Keep going'), findsNothing);
  });
}
