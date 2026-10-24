import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetwin/app/app.dart';
import 'package:lifetwin/app/router.dart';
import 'package:lifetwin/features/activity/health_importer.dart';

class _FakeImporter implements HealthImporter {
  _FakeImporter(this.result);
  final HealthImportResult result;

  @override
  Future<HealthImportResult> importLast28Days(DateTime now) async => result;
}

Future<void> _pump(WidgetTester tester, HealthImportResult result) async {
  tester.view.physicalSize = const Size(780, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        healthImporterProvider.overrideWithValue(_FakeImporter(result)),
      ],
      child: LifeTwinApp(router: buildRouter(initialLocation: '/activity')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'empty activity log shows the empty state and both entry points',
    (tester) async {
      await _pump(tester, const HealthUnavailable());

      expect(find.text('Activity'), findsWidgets);
      expect(find.text('No workouts yet'), findsOneWidget);
      expect(find.text('Add your first workout'), findsOneWidget);
      expect(find.text('Import from Apple Health'), findsOneWidget);
      expect(find.text('Manual'), findsOneWidget); // source chip
      expect(find.textContaining('No average yet'), findsOneWidget);
    },
  );

  testWidgets('denied Apple Health keeps the manual log fully usable', (
    tester,
  ) async {
    await _pump(tester, const HealthDenied());

    await tester.tap(find.text('Import from Apple Health'));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Apple Health is off for LifeTwin'), findsOneWidget);
    expect(
      find.textContaining('manual log stays fully usable'),
      findsOneWidget,
    );

    // Log a workout from the denied screen.
    await tester.tap(find.text('Log a workout'));
    await tester.pumpAndSettle();
    expect(find.text('Duration'), findsWidgets);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Back on the Activity tab the workout is listed and the average moved.
    await tester.tap(find.text('Back to Activity'));
    await tester.pumpAndSettle();
    expect(find.text('No workouts yet'), findsNothing);
    expect(find.text('Walk'), findsWidgets);
    expect(find.textContaining('30 min'), findsWidgets);
  });

  testWidgets('successful import shows the on-device average with source', (
    tester,
  ) async {
    await _pump(tester, const HealthImported([100, 120, 140, 208]));

    await tester.tap(find.text('Import from Apple Health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('About 142 min/week'), findsOneWidget);
    expect(find.text('(Apple Health, last 4 weeks)'), findsOneWidget);
    expect(find.textContaining('self-reported'), findsOneWidget);
  });
}
