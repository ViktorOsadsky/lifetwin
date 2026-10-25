import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/wellness/coach_client.dart';
import 'package:lifesim/wellness/today_card.dart';

import '../support/app_fonts.dart';
import 'coach_test.dart' show FakeCoach;

Map<String, dynamic> item(String id, String kind, String title, {int? minutes, String tod = 'morning'}) => {
  'id': id,
  'kind': kind,
  'catalog_id': id,
  'title': title,
  'message': '$title, gently.',
  'why': 'Why $id: a general idea.',
  'minutes': minutes,
  'time_of_day': tod,
  'source_title': 'CDC guidance',
  'source_url': 'https://www.cdc.gov/physical-activity-basics/guidelines/adults.html',
  'reviewed_by': 'awaiting professional review',
  'causal_interpretation': false,
};

DailyPlan fourSlots({String revision = 'r1'}) => DailyPlan.fromJson({
  'schema_version': '1.0',
  'status': 'ok',
  'revision_id': revision,
  'local_date': '2026-10-24',
  'based_on': null,
  'inputs': {'snapshot_id': 's1'},
  'plan_type': 'personal',
  'changes': [],
  'trace': [],
  'items': [
    item('move', 'workout', 'Seated marching', minutes: 10),
    item('eat', 'diet', 'Add a vegetable to dinner', tod: 'evening'),
    item('habit', 'habit', 'Lights out by 10', tod: 'evening'),
    item('hello', 'encourage', 'You are doing great', tod: 'afternoon'),
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester t, Widget card) async {
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: Scaffold(body: SingleChildScrollView(child: card)),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('shows the four slots from the coach, asks the consent first, and Why? shows the reason', (t) async {
    final coach = FakeCoach()..responses.add(fourSlots());
    final order = <String>[];
    var opened = 0;
    await pump(
      t,
      TodayWithMochiCard(
        client: coach,
        confirmedContext: () => {'local_date': '2026-10-24'},
        beforeFirstPlan: () async => order.add('consent'),
        onOpen: () => opened++,
      ),
    );
    expect(order, ['consent']);
    expect(coach.requests, hasLength(1));
    for (final text in [
      'Seated marching · 10 min',
      'Add a vegetable to dinner',
      'Lights out by 10',
      'You are doing great',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('Why?'), findsNWidgets(4));
    await t.tap(find.text('Why?').first);
    await t.pumpAndSettle();
    expect(find.text('Why move: a general idea.'), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    await t.tap(find.text('Today with Mochi'));
    expect(opened, 1);
  });

  testWidgets('feedback goes back to the coach as a revision with the previous plan', (t) async {
    final coach = FakeCoach()..responses.addAll([fourSlots(), fourSlots(revision: 'r2')]);
    await pump(
      t,
      TodayWithMochiCard(client: coach, confirmedContext: () => {'local_date': '2026-10-24'}, onOpen: () {}),
    );
    await t.tap(find.text('Not for me').first);
    await t.pumpAndSettle();
    expect(coach.requests, hasLength(2));
    final sent = coach.requests.last;
    expect(sent['latest_revision_id'], 'r1');
    expect((sent['previous_plan'] as Map)['revision_id'], 'r1');
    expect(sent['feedback'], {
      'revision_id': 'r1',
      'items': [
        {'item_id': 'move', 'status': 'not_done', 'reason': 'Not for me'},
      ],
    });
    await t.tap(find.text('👍').at(1));
    await t.pumpAndSettle();
    expect((coach.requests.last['feedback'] as Map)['items'], [
      {'item_id': 'eat', 'status': 'accepted'},
    ]);
  });

  testWidgets('an error or a slow server shows Mochi alone, never an empty card', (t) async {
    final coach = FakeCoach()..responses.add(const CoachFailure(null));
    await pump(t, TodayWithMochiCard(client: coach, confirmedContext: () => {}, onOpen: () {}));
    expect(find.text('Today with Mochi'), findsOneWidget);
    expect(find.text(todayFallbackLine), findsOneWidget);
    expect(find.text('Why?'), findsNothing);
  });
}
