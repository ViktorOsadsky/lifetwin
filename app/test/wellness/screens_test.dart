import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/wellness/history_screen.dart';
import 'package:lifesim/wellness/home_panel.dart';
import 'package:lifesim/twin/twin_model.dart' show HealthScoreStatus;
import 'package:lifesim/ui/widgets/rough_guide_badge.dart';
import 'package:lifesim/wellness/models.dart';
import 'package:lifesim/wellness/outlook_drivers_screen.dart';
import 'package:lifesim/wellness/settings_screen.dart';

Future<void> reveal(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
}

Future<void> phone(
  WidgetTester t,
  Widget screen, {
  double scale = 1,
  Size size = const Size(320, 693),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: lifeTwinTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: screen,
      ),
    ),
  );
  await t.pump();
}

void main() {
  testWidgets('home shows no invented score and no second check-in', (t) async {
    var estimates = 0;
    await phone(
      t,
      Scaffold(
        body: SingleChildScrollView(
          child: HomeWellnessPanel(snapshot: const WellnessSnapshot(), onEstimate: () => estimates++),
        ),
      ),
      scale: 2,
    );
    expect(find.text('Getting to know you'), findsOneWidget);
    expect(find.text('Check in'), findsNothing);
    expect(find.textContaining('days this week'), findsNothing);
    await reveal(t, find.text('See your estimate'));
    await t.tap(find.text('See your estimate'));
    expect(estimates, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('home shows the model score, its age group and a rough guide when extrapolated', (t) async {
    await phone(
      t,
      Scaffold(
        body: SingleChildScrollView(
          child: HomeWellnessPanel(
            snapshot: const WellnessSnapshot(
              healthScore: -0.42,
              status: HealthScoreStatus.extrapolated,
              ageGroupPercentile: 61.6,
            ),
            onEstimate: () {},
          ),
        ),
      ),
    );
    expect(find.text('\u22120.4'), findsOneWidget);
    expect(find.text(HomeWellnessPanel.tagline), findsOneWidget);
    expect(find.text('Healthier than 62 of 100 people your age'), findsOneWidget);
    expect(find.text(RoughGuideBadge.label), findsOneWidget);
    expect(find.textContaining('/ 100'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('home drops the tagline at large text and shows no number under 18', (t) async {
    await phone(
      t,
      Scaffold(
        body: SingleChildScrollView(
          child: HomeWellnessPanel(
            snapshot: const WellnessSnapshot(healthScore: 0.3, status: HealthScoreStatus.available),
            onEstimate: () {},
          ),
        ),
      ),
      scale: 1.6,
    );
    expect(find.text(HomeWellnessPanel.tagline), findsNothing);
    expect(find.text('+0.3'), findsOneWidget);
    expect(find.text(RoughGuideBadge.label), findsNothing);
    await phone(
      t,
      Scaffold(
        body: HomeWellnessPanel(
          snapshot: const WellnessSnapshot(healthScore: 0.3, status: HealthScoreStatus.underAge),
          onEstimate: () {},
        ),
      ),
    );
    expect(find.text('+0.3'), findsNothing);
    expect(find.text(HomeWellnessPanel.underAgeLine), findsOneWidget);
    expect(find.text('See your estimate'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'history is read-only, filters dates and labels every value source',
    (t) async {
      var talks = 0;
      final now = DateTime(2026, 10, 24);
      final days = [
        WellnessDay(
          date: now,
          values: [
            for (final source in ValueSource.values)
              HistoryValue(
                label: 'Reading',
                value: source.name,
                source: source,
                estimated: source == ValueSource.wristband,
              ),
          ],
        ),
        WellnessDay(
          date: DateTime(2026, 9, 10),
          values: const [
            HistoryValue(label: 'Older reading', value: 'recorded'),
          ],
        ),
      ];
      await phone(
        t,
        HistoryScreen(
          days: days,
          goodWeeks: 2,
          now: now,
          onBack: () {},
          onTalk: () => talks++,
        ),
      );
      expect(find.text('2 good weeks'), findsOneWidget);
      expect(find.text('Wristband · Estimated'), findsOneWidget);
      expect(find.text('Older reading: recorded'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.text('All time'));
      await t.pump();
      await reveal(t, find.text('Older reading: recorded'));
      expect(find.text('Older reading: recorded'), findsOneWidget);
      await reveal(t, find.text('Talk with Mochi'));
      await t.tap(find.text('Talk with Mochi'));
      expect(talks, 1);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'settings opens owned choice routes and reflects their current values',
    (t) async {
      final settings = ValueNotifier(const WellnessSettings());
      addTearDown(settings.dispose);
      var memory = 0;
      var suggestions = 0;
      var reminders = 0;
      await phone(
        t,
        WellnessSettingsScreen(
          settings: settings,
          onMemory: () => memory++,
          onSuggestions: () {
            suggestions++;
            settings.value = settings.value.copyWith(personalSuggestions: true);
          },
          onReminders: () => reminders++,
          onMyData: () {},
          onBack: () {},
        ),
        scale: 2,
      );
      await reveal(t, find.text('Personal suggestions'));
      await t.tap(find.text('Personal suggestions'));
      await t.pump();
      expect(suggestions, 1);
      expect(find.text('On'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Memory & notebook'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Memory & notebook'));
      expect(memory, 1);
      await reveal(t, find.text('Reminders'));
      await t.tap(find.text('Reminders'));
      expect(reminders, 1);
      expect(settings.value.reminderMinutes, 600);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('My data delegates deletion to the existing owner route', (
    t,
  ) async {
    final settings = ValueNotifier(const WellnessSettings());
    addTearDown(settings.dispose);
    var opens = 0;
    await phone(
      t,
      WellnessSettingsScreen(
        settings: settings,
        onMemory: () {},
        onSuggestions: () {},
        onReminders: () {},
        onMyData: () => opens++,
        onBack: () {},
      ),
    );
    await reveal(t, find.text('My data'));
    await t.tap(find.text('My data'));
    expect(opens, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'directions are labeled in words and experiment uses its existing entry',
    (t) async {
      var experiments = 0;
      await phone(
        t,
        OutlookDriversScreen(
          drivers: const [
            OutlookDriver(
              label: 'Movement',
              direction: DriverDirection.higher,
              reason: 'A supported comparison with more activity.',
            ),
          ],
          onBack: () {},
          onExperiment: () => experiments++,
        ),
        scale: 2,
      );
      expect(find.text('Linked with a higher modeled outlook'), findsOneWidget);
      expect(find.textContaining('percentage point'), findsNothing);
      await reveal(t, find.text('Explore an experiment'));
      await t.tap(find.text('Explore an experiment'));
      expect(experiments, 1);
      expect(t.takeException(), isNull);
    },
  );
}
