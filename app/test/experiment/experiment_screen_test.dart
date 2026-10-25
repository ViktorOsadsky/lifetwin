import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/experiment/experiment_screen.dart';
import 'package:lifesim/experiment/lever_copy.dart';
import 'package:lifesim/experiment/room_pills.dart';
import 'package:lifesim/experiment/result_display.dart';
import 'package:lifesim/experiment/side_by_side_screen.dart';
import 'package:lifesim/experiment/wellness_panel.dart';
import 'package:lifesim/experiment/weight_screen.dart';
import 'package:lifesim/experiment/widgets/widgets.dart';
import 'package:lifesim/twin/twin_experiment.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService, extrapolationCaveat;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/widgets/rough_guide_badge.dart';

import '../support/app_fonts.dart';

/// 66-year-old man who smokes, sleeps 6 h, sits a lot: every lever is offered, and the
/// differences are whole people in 100.
const older = {
  'age': 66,
  'sex': 'male',
  'height_cm': 175.0,
  'weight_kg': 80.0,
  'sleep_hours': 6,
  'smoking_status': 'current',
  'diabetes': false,
  'hypertension_diagnosed': false,
  'general_health': 3,
  'vigorous_recreation_min_week': 0,
  'moderate_recreation_min_week': 30,
  'sedentary_min_day': 480,
  'alcohol_drinks_weekly': 3,
};

/// 38-year-old non-smoker: every difference is under one person in 100.
final younger = {...older, 'age': 38, 'smoking_status': 'never', 'moderate_recreation_min_week': 0};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  late LeverRanking ranking;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
    ranking = await loadLeverRanking();
  });

  Future<TwinRepository> repoWith(Map<String, dynamic>? profile) async {
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      leverRanking: ranking,
      clock: () => DateTime(2026, 10, 26),
    );
    if (profile != null) await repo.saveConversationProfile(profile);
    return repo;
  }

  final opened = <Uri>[];
  Future<void> fakeOpen(Uri u) async => opened.add(u);
  final told = <String?>[];

  Future<void> pumpApp(WidgetTester t, Widget home, {double textScale = 1}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(textScale)),
          child: home,
        ),
      ),
    );
    await t.pump();
  }

  Future<void> pumpHub(WidgetTester t, TwinRepository repo, {double textScale = 1}) => pumpApp(
    t,
    ExperimentScreen(
      repository: repo,
      appearance: const TwinAppearance(name: 'Mochi'),
      onBack: () {},
      onTellMochi: told.add,
      openUrl: fakeOpen,
    ),
    textScale: textScale,
  );

  Iterable<String> texts(WidgetTester t) => t
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
      .where((s) => s.isNotEmpty);
  bool anyText(WidgetTester t, Pattern p) => texts(t).any((s) => s.contains(p));

  Future<void> openLever(WidgetTester t, String semanticsStart) async {
    final row = find.bySemanticsLabel(RegExp('^$semanticsStart'));
    await t.ensureVisible(row);
    await t.pump();
    await t.tap(row);
    await t.pumpAndSettle();
  }

  setUp(() {
    opened.clear();
    told.clear();
  });

  group('hub (Y-1)', () {
    testWidgets('twins side by side, levers in engine order with today and what-if, honesty dock', (t) async {
      final h = t.ensureSemantics();
      final repo = await repoWith(older);
      await pumpHub(t, repo);
      expect(find.text('Experiment'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('What-if'), findsOneWidget);
      expect(find.text('Mochi'), findsOneWidget);
      expect(find.textContaining('Linked, not proven.'), findsOneWidget);
      expect(find.textContaining('What-if only.'), findsOneWidget);
      expect(find.text('Why?'), findsOneWidget);
      final order = ['Smoking', 'Hard', 'Moderate', 'Sleep', 'Sitting'];
      final ys = [for (final o in order) t.getTopLeft(find.text(o)).dy];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.text('Today smoking'), findsOneWidget);
      expect(find.text('Today 0 min a week'), findsOneWidget);
      expect(find.text('Today 30 min a week'), findsOneWidget);
      expect(find.text('Today 6 h a night'), findsOneWidget);
      expect(find.text('Today 8 h a day'), findsOneWidget);
      // Nothing moved yet: five dashed "Same" values, "Pick a change", no number.
      expect(find.byType(SamePill), findsNWidgets(5));
      expect(find.text('Pick a change'), findsOneWidget);
      expect(find.byType(BearArray), findsNothing);
      expect(anyText(t, RegExp(r'About \d|in 100')), isFalse);
      expect(find.bySemanticsLabel('Smoking, today smoking, what-if the same. Opens Smoking.'), findsOneWidget);
      h.dispose();
    });

    testWidgets('no weight anywhere: no row, no word, no number', (t) async {
      final h = t.ensureSemantics();
      final repo = await repoWith(older);
      await pumpHub(t, repo);
      expect(LeverCopy.of(LeverId.weightKg), isNull);
      for (final s in texts(t)) {
        expect(s.toLowerCase(), isNot(contains('weight')), reason: s);
        expect(s.toLowerCase(), isNot(contains('bmi')), reason: s);
        expect(s.toLowerCase(), isNot(contains('death')), reason: s);
        expect(s.toLowerCase(), isNot(contains('years gained')), reason: s);
      }
      expect(find.bySemanticsLabel(RegExp('weight|BMI', caseSensitive: false)), findsNothing);
      h.dispose();
    });

    testWidgets('levers the engine does not offer are hidden', (t) async {
      final repo = await repoWith({
        ...older,
        'smoking_status': 'never',
        'sleep_hours': 8,
        'vigorous_recreation_min_week': 300,
        'moderate_recreation_min_week': 600,
        'sedentary_min_day': 60,
      });
      await pumpHub(t, repo);
      expect(find.byType(LeverRow), findsNothing);
      expect(find.textContaining('nothing to try'), findsOneWidget);
    });
  });

  group('lever detail and the shared what-if (Y-2, Y-7)', () {
    testWidgets('a stepper previews "Just this change"; Use in my what-if sets the hub; nothing is saved', (t) async {
      final h = t.ensureSemantics();
      final repo = await repoWith(older);
      final before = jsonEncode({
        'p': repo.profile,
        'c': repo.store.checkins.length,
        'w': repo.store.dayLogs.length,
      });
      await pumpHub(t, repo);
      await openLever(t, 'Sleep, today');
      expect(find.text('Sleep'), findsWidgets);
      expect(find.text('Just this change'), findsNWidgets(2)); // the tag and the card
      expect(find.text('6 h'), findsOneWidget);
      // Sleep goes up in half hours, only to 8.
      await t.tap(find.bySemanticsLabel('Half an hour more sleep'));
      await t.pump();
      expect(find.text('6½ h'), findsOneWidget);
      expect(find.text('+30 min'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await t.tap(find.bySemanticsLabel('Half an hour more sleep'));
        await t.pump();
      }
      expect(find.text('+1½ hours'), findsOneWidget); // 6 -> 7½
      expect(find.text('7½ h'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Half an hour more sleep'));
      await t.pump();
      expect(find.text('8 h'), findsOneWidget);
      expect(find.text('8 h is the top'), findsOneWidget);
      // The plus is now disabled: it does nothing.
      await t.tap(find.bySemanticsLabel('Half an hour more sleep'));
      await t.pump();
      expect(find.text('8 h'), findsOneWidget);
      await t.tap(find.bySemanticsLabel(RegExp(r'^Use 8 hours in my what-if')));
      await t.pumpAndSettle();
      // Back on the hub, the lever shows its what-if value.
      expect(find.text('8 h a night'), findsOneWidget);
      expect(find.byType(SamePill), findsNWidgets(4));
      expect(
        jsonEncode({'p': repo.profile, 'c': repo.store.checkins.length, 'w': repo.store.dayLogs.length}),
        before,
      );
      h.dispose();
    });

    testWidgets('smoking is a two-option control, Quit selected shows its own result', (t) async {
      final h = t.ensureSemantics();
      final repo = await repoWith(older);
      await pumpHub(t, repo);
      await openLever(t, 'Smoking, today');
      expect(find.text('Smoke now'), findsOneWidget);
      expect(find.text('Quit'), findsOneWidget);
      expect(find.byType(BigStepper), findsNothing);
      await t.tap(find.text('Quit'));
      await t.pump();
      expect(find.text('Quitting alone vs today'), findsOneWidget);
      expect(find.byType(BearArray), findsNWidgets(2));
      // The US quitline is off until the owner approves it.
      expect(find.textContaining('QUIT-NOW'), findsNothing);
      h.dispose();
    });
  });

  group('result states (Y-3, Y-4, Y-15)', () {
    testWidgets('1 or more: the headline, today and what-if counts, two arrays', (t) async {
      final repo = await repoWith(older);
      await pumpHub(t, repo);
      final exp = repo.experiment()!
        ..set(LeverId.smoking, 1)
        ..set(LeverId.moderate, 120);
      final d = ResultDisplay.of(exp.result);
      expect(d.kind, ResultKind.big);
      await pumpApp(
        t,
        SideBySideScreen(repository: repo, whatIf: exp, appearance: const TwinAppearance(), open: fakeOpen),
      );
      expect(find.text('Side by side'), findsOneWidget);
      expect(find.text('About ${d.gap} more in 100'), findsOneWidget);
      expect(find.text('Today: ${d.today}'), findsOneWidget);
      expect(find.text('What-if: ${d.whatIf}'), findsOneWidget);
      expect(find.byType(BearArray), findsNWidgets(2));
      expect(find.text('Smoke-free'), findsOneWidget);
      expect(find.text('Moderate exercise 2 h a week'), findsOneWidget);
      expect(find.text('See years 1 to 5'), findsOneWidget);
    });

    testWidgets('under 1: "Less than 1 more in 100", an (i) with the exact figure, no arrays', (t) async {
      final h = t.ensureSemantics();
      final repo = await repoWith(younger);
      final exp = repo.experiment()!..set(LeverId.vigorous, 15);
      final d = ResultDisplay.of(exp.result);
      expect(d.kind, isIn([ResultKind.tiny, ResultKind.same]));
      exp.set(LeverId.vigorous, 150);
      exp.set(LeverId.moderate, 150);
      final tiny = ResultDisplay.of(exp.result);
      expect(tiny.kind, ResultKind.tiny, reason: '${exp.result.difference5}');
      await pumpApp(
        t,
        SideBySideScreen(repository: repo, whatIf: exp, appearance: const TwinAppearance(), open: fakeOpen),
      );
      expect(find.text('Less than 1 more in 100'), findsOneWidget);
      expect(find.text('A tiny bit more'), findsOneWidget);
      expect(find.byType(BearArray), findsNothing);
      expect(anyText(t, RegExp(r'About \d+ more in 100')), isFalse);
      await t.tap(find.bySemanticsLabel(RegExp('^Exact figure')));
      await t.pumpAndSettle();
      expect(find.textContaining('in 1,000'), findsOneWidget);
      expect(find.textContaining('Too small for a 100-bear picture'), findsOneWidget);
      h.dispose();
    });

    testWidgets('About the same: words only, no number, no (i)', (t) async {
      // Already active: one more step is a difference the model cannot see.
      final repo = await repoWith({
        ...younger,
        'moderate_recreation_min_week': 150,
        'vigorous_recreation_min_week': 150,
      });
      final exp = repo.experiment()!;
      var found = false;
      for (final v in [165.0, 180.0, 195.0]) {
        exp.set(LeverId.moderate, v);
        if (ResultDisplay.of(exp.result).kind == ResultKind.same) {
          found = true;
          break;
        }
      }
      expect(found, isTrue, reason: '${exp.result.difference5}');
      await pumpApp(
        t,
        SideBySideScreen(repository: repo, whatIf: exp, appearance: const TwinAppearance(), open: fakeOpen),
      );
      expect(find.text('About the same'), findsOneWidget);
      expect(find.byType(BearArray), findsNothing);
      expect(find.textContaining('in 1,000'), findsNothing);
      expect(anyText(t, RegExp(r'more in 100')), isFalse);
    });

    Future<void> pumpCard(WidgetTester t, ExperimentResult r) => pumpApp(
      t,
      Scaffold(
        body: SingleChildScrollView(
          child: ResultCard(display: ResultDisplay.of(r), leverName: (id) => LeverCopy.of(id)?.full ?? id),
        ),
      ),
    );

    testWidgets('every status without a number shows a dashed box and no number (Y-15)', (t) async {
      await pumpCard(t, const ExperimentResult(status: 'no_change'));
      expect(find.text('Pick a change'), findsOneWidget);
      await pumpCard(
        t,
        const ExperimentResult(
          status: 'not_counted',
          levers: [LeverFlag(id: LeverId.sitting, counted: false, reason: LeverReason.counterIntuitive)],
        ),
      );
      expect(find.text('No number'), findsOneWidget);
      expect(find.byType(NotCountedPill), findsNWidgets(2));
      expect(find.text('Sitting'), findsOneWidget);
      await t.tap(find.byIcon(Icons.info_outline_rounded).last);
      await t.pumpAndSettle();
      expect(find.textContaining('runs against health guidance'), findsOneWidget);
      await t.tap(find.text('Close'));
      await t.pumpAndSettle();
      await pumpCard(
        t,
        const ExperimentResult(
          status: 'alternative_unavailable',
          message: 'Annual estimates are withheld for this profile.',
        ),
      );
      expect(find.text('Try a smaller step.'), findsOneWidget);
      await pumpCard(t, const ExperimentResult(status: 'invalid_input', message: 'More than 24 hours a day.'));
      expect(find.text('Too many hours'), findsOneWidget);
      expect(find.text('Try smaller changes.'), findsOneWidget);
      await pumpCard(t, const ExperimentResult(status: 'current_unavailable', message: 'Needs more answers.'));
      expect(find.text('No number'), findsOneWidget);
      for (final status in [
        'no_change',
        'not_counted',
        'alternative_unavailable',
        'invalid_input',
        'current_unavailable',
      ]) {
        await pumpCard(
          t,
          ExperimentResult(status: status, differenceByYear: const {5: 4.0}, currentPercentByYear: const {5: 90}),
        );
        expect(find.byType(BearArray), findsNothing, reason: status);
        expect(anyText(t, RegExp(r'About \d|more in 100')), isFalse, reason: status);
      }
    });
  });

  group('Rough guide (Y-16, Y-17)', () {
    testWidgets('badge beside the number; tapping opens the engine caveat inline; Close hides it', (t) async {
      final repo = await repoWith({...older, 'age': 82});
      expect(repo.current!.extrapolated, isTrue);
      final exp = repo.experiment()!
        ..set(LeverId.smoking, 1)
        ..set(LeverId.moderate, 120);
      await pumpApp(
        t,
        SideBySideScreen(repository: repo, whatIf: exp, appearance: const TwinAppearance(), open: fakeOpen),
      );
      expect(find.byType(RoughGuideBadge), findsWidgets);
      expect(find.text('Rough guide'), findsWidgets);
      expect(t.getSize(find.byType(RoughGuideBadge).first).height, greaterThanOrEqualTo(48));
      expect(find.text(extrapolationCaveat), findsNothing);
      await t.tap(find.byType(RoughGuideBadge).first);
      await t.pump();
      expect(find.text(extrapolationCaveat), findsOneWidget);
      await t.tap(find.byIcon(Icons.close_rounded));
      await t.pump();
      expect(find.text(extrapolationCaveat), findsNothing);
    });

    testWidgets('no badge at a checked age, and none without a number', (t) async {
      final repo = await repoWith(older);
      final exp = repo.experiment()!..set(LeverId.smoking, 1);
      await pumpApp(
        t,
        SideBySideScreen(repository: repo, whatIf: exp, appearance: const TwinAppearance(), open: fakeOpen),
      );
      expect(find.byType(RoughGuideBadge), findsNothing);
      final old = await repoWith({...older, 'age': 82, 'smoking_status': 'never'});
      await pumpHub(t, old);
      expect(find.byType(RoughGuideBadge), findsNothing); // nothing moved: no number
    });
  });

  group('the curve (Y-5)', () {
    testWidgets('zoomed and labelled by default; full scale behind a switch; the numbers sheet', (t) async {
      final repo = await repoWith(older);
      final exp = repo.experiment()!
        ..set(LeverId.smoking, 1)
        ..set(LeverId.moderate, 120);
      final d = ResultDisplay.of(exp.result);
      await pumpApp(t, CurveScreen(display: d));
      expect(find.text('Years 1 to 5'), findsOneWidget);
      expect(find.text('Modeled survival of similar people'), findsOneWidget);
      expect(find.textContaining('Zoomed in: '), findsOneWidget);
      expect(find.textContaining(' to 100'), findsWidgets);
      await t.tap(find.text('Show full scale'));
      await t.pump();
      expect(find.textContaining('Zoomed in'), findsNothing);
      await t.tap(find.text('Show full scale'));
      await t.pump();
      expect(find.textContaining('Zoomed in'), findsOneWidget);
      await t.tap(find.text('See the numbers'));
      await t.pumpAndSettle();
      expect(find.byType(NumbersTable), findsOneWidget);
      final last = d.rows.last;
      expect(find.text('${last.whatIf}'), findsOneWidget);
    });
  });

  group('not available (Y-8, Y-9, Y-10, Y-13)', () {
    testWidgets('Still learning lists missingLabels in plain words; Tell Mochi opens the change conversation', (
      t,
    ) async {
      final repo = await repoWith(
        // Three missing: no number (one or two give a rough, flagged one).
        {...older}
          ..remove('sedentary_min_day')
          ..remove('general_health')
          ..remove('sleep_hours'),
      );
      expect(repo.experiment()!.current.status, 'missing_inputs');
      await pumpHub(t, repo);
      expect(find.text('Almost ready'), findsOneWidget);
      expect(find.text('Time spent sitting each day'), findsOneWidget);
      expect(find.text('How you rate your health'), findsOneWidget);
      expect(find.textContaining('I don’t know'), findsOneWidget);
      expect(find.byType(LeverRow), findsNothing);
      expect(anyText(t, RegExp(r'About \d|in 100')), isFalse);
      await t.tap(find.text('Tell Mochi'));
      await t.pump();
      expect(told, [null]);
    });

    testWidgets('an age outside 18 to 85: no number, the cards that are going well, each with its source', (t) async {
      final repo = await repoWith({...older, 'age': 90, 'smoking_status': 'never'});
      expect(repo.experiment()!.current.status, 'unsupported_age');
      await pumpHub(t, repo);
      expect(find.text('Outside my range'), findsOneWidget);
      expect(find.text('My numbers cover ages 18 to 85.'), findsOneWidget);
      expect(find.byType(LeverRow), findsNothing);
      expect(anyText(t, RegExp(r'About \d|in 100')), isFalse);
      final strengths = repo.wellnessCards.where((c) => c.level == 'strength').length;
      expect(strengths, greaterThan(0));
      expect(find.byType(SourceLink), findsNWidgets(strengths));
    });

    testWidgets('a rare answer: "Too rare to estimate", the answer in words, Change opens a Mochi talk', (t) async {
      final repo = await repoWith({...older, 'vigorous_recreation_min_week': 720});
      final status = repo.experiment()!.current.status;
      expect(status, 'unsupported_profile');
      await pumpHub(t, repo);
      expect(find.text('Rare answers'), findsOneWidget);
      expect(find.text('Too rare to estimate'), findsOneWidget);
      expect(find.text('12 h a week'), findsOneWidget);
      await t.tap(find.text('Change'));
      await t.pump();
      expect(told, ['vigorous_recreation_min_week']);
      expect(anyText(t, RegExp(r'in 100')), isFalse);
    });

    testWidgets('no profile at all: Still learning, no number', (t) async {
      final repo = await repoWith(null);
      await pumpHub(t, repo);
      expect(find.text('Still learning'), findsWidgets);
      expect(find.byType(LeverRow), findsNothing);
    });
  });

  group('weight (Y-6): an info card, never a lever', () {
    testWidgets('shows words and the source, no number, no stepper', (t) async {
      final repo = await repoWith(older);
      final bmi = repo.wellnessCards.where((c) => c.id == 'bmi').firstOrNull;
      expect(bmi, isNotNull);
      await pumpApp(t, WeightInfoScreen(appearance: const TwinAppearance(), card: bmi!, onBack: () {}, open: fakeOpen));
      expect(find.text('About weight'), findsOneWidget);
      expect(find.text('Weight is one clue'), findsOneWidget);
      expect(find.byType(BigStepper), findsNothing);
      expect(find.byType(TwoOptionControl), findsNothing);
      expect(anyText(t, RegExp(r'\d')), isFalse);
      await t.tap(find.text('CDC: Healthy weight'));
      expect(opened.single.toString(), bmi.sourceUrl);
    });
  });

  group('wellness cards (Y-12)', () {
    testWidgets('each card has its own source link and the row opens the engine text verbatim', (t) async {
      final repo = await repoWith(older);
      final cards = repo.wellnessCards.where((c) => c.level != 'info').toList();
      expect(cards, isNotEmpty);
      await pumpApp(
        t,
        SingleChildScrollView(
          child: WellnessPanel(cards: repo.wellnessCards, open: fakeOpen),
        ),
      );
      expect(find.byType(SourceLink), findsNWidgets(cards.length));
      // Every link goes to its own card's source.
      for (var i = 0; i < cards.length; i++) {
        await t.tap(find.byType(SourceLink).at(i));
        expect(opened.last.toString(), cards[i].sourceUrl, reason: cards[i].id);
        expect(cards[i].sourceUrl, startsWith('https://'));
      }
      // The row is "Learn more": it opens the card's own words.
      final c = cards.first;
      await t.tap(find.text(WellnessPanel.uiTitle(c)).first);
      await t.pumpAndSettle();
      expect(find.text(c.message), findsOneWidget);
      expect(find.text(c.level == 'strength' ? 'Going well' : 'Room to grow'), findsOneWidget);
    });

    test('every card the engine returns for a profile carries a source link', () async {
      for (final p in [
        older,
        younger,
        {...older, 'age': 82},
      ]) {
        final repo = await repoWith(p);
        expect(repo.wellnessCards, isNotEmpty);
        for (final c in repo.wellnessCards) {
          expect(Uri.tryParse(c.sourceUrl)?.hasAuthority, isTrue, reason: '${c.id} ${c.sourceUrl}');
        }
      }
    });
  });

  group('Room entries (Y-12)', () {
    testWidgets('Still learning shows the count of missing answers; What I see needs cards; both open', (t) async {
      final missing = await repoWith(
        {...older}
          ..remove('sedentary_min_day')
          ..remove('general_health'),
      );
      var learning = 0, cards = 0, tried = 0;
      Future<void> pumpRoom(TwinRepository repo) => pumpApp(
        t,
        RoomScreen(
          appearance: ValueNotifier(const TwinAppearance()),
          onTalk: () {},
          onCustomize: () {},
          extraPills: roomPills(
            repository: repo,
            onExperiment: () => tried++,
            onStillLearning: () => learning++,
            onWellness: () => cards++,
          ),
        ),
      );
      await pumpRoom(missing);
      expect(find.text('Still learning 2'), findsOneWidget);
      await t.tap(find.text('Still learning 2'));
      expect(learning, 1);
      // A complete profile: nothing is missing, so the pill is gone; the cards and Experiment are there.
      final full = await repoWith(older);
      await pumpRoom(full);
      expect(find.textContaining('Still learning'), findsNothing);
      expect(find.text('What I see'), findsOneWidget);
      await t.tap(find.text('What I see'));
      await t.tap(find.text('Try a change'));
      expect((cards, tried), (1, 1));
    });
  });

  group('the experiment never writes', () {
    testWidgets('levers, "use in my what-if" and start over leave the profile, history and repository alone', (
      t,
    ) async {
      final h = t.ensureSemantics();
      final repo = await repoWith(older);
      String snapshot() => jsonEncode({
        'profile': repo.profile,
        'checkins': repo.store.checkins.length,
        'daily': repo.store.dayLogs.length,
        'weekly': repo.store.dayLogs.length,
        'twin': repo.store.twin,
      });
      final before = snapshot();
      final current = repo.current;
      var notified = 0;
      repo.addListener(() => notified++);
      await pumpHub(t, repo);
      await openLever(t, 'Moderate exercise, today');
      await t.tap(find.bySemanticsLabel('15 minutes more moderate exercise'));
      await t.tap(find.bySemanticsLabel('15 minutes more moderate exercise'));
      await t.pump();
      await t.tap(find.bySemanticsLabel(RegExp(r'^Use ')));
      await t.pumpAndSettle();
      await openLever(t, 'Smoking, today');
      await t.tap(find.text('Quit'));
      await t.pump();
      await t.tap(find.bySemanticsLabel(RegExp(r'^Use ')));
      await t.pumpAndSettle();
      expect(snapshot(), before);
      expect(identical(repo.current, current), isTrue);
      expect(notified, 0);
      h.dispose();
    });
  });

  testWidgets('every control is at least 48 and text follows the text scale', (t) async {
    final h = t.ensureSemantics();
    final repo = await repoWith(older);
    await pumpHub(t, repo, textScale: 2);
    expect(t.takeException(), isNull);
    final big = t.getSize(find.text('Try a change')).height;
    await pumpHub(t, repo);
    expect(big, greaterThan(t.getSize(find.text('Try a change')).height));
    for (final label in [RegExp(r'^Smoking, today'), RegExp(r'^Sleep, today'), RegExp('Why\\? Linked')]) {
      final s = t.getSize(find.bySemanticsLabel(label));
      expect(s.height, greaterThanOrEqualTo(48), reason: '$label');
    }
    h.dispose();
  });

  test('Lottie assets for the Experiment are bundled', () {
    for (final n in ['whatif_appear', 'bear_pop_in', 'outlook_glow', 'fortune_loading', 'thinking_dots']) {
      expect(jsonDecode(File('assets/lottie/$n.json').readAsStringSync()), isA<Map>(), reason: n);
    }
  });
}
