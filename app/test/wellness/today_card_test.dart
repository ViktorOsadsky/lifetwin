import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/wellness/coach_client.dart';
import 'package:lifesim/wellness/today_card.dart';

import '../support/app_fonts.dart';
import '../checkin/daily_checkin_test.dart' show profile;
import '../checkin/readback_flow_test.dart' show ContractGuide;
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
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

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

  Future<int> afterCheckIn(WidgetTester t, TodayUpdate update) async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    await repo.saveConversationProfile(profile);
    var opened = 0;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final look = ValueNotifier(const TwinAppearance(name: 'Mochi'));
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: (c, child) => CheckInScope(
          repository: repo,
          guide: ContractGuide(),
          speechInput: FakeSpeechInput(),
          speechOutput: FakeSpeechOutput(),
          appearance: look,
          todayPlan: TodayPlanHook(update: () async => update, open: (_) => opened++),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openCheckIn(context, kind: CheckInKind.quick),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '7 hours');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
    await t.tap(find.text('About 6 hours'));
    await t.pumpAndSettle();
    await t.tap(find.text('Looks right'));
    await t.pumpAndSettle();
    return opened;
  }

  testWidgets('after a check-in the plan changed: one line per change, then Here\'s today\'s plan', (t) async {
    await afterCheckIn(
      t,
      const TodayUpdate(
        encouragement: 'Thanks for telling me.',
        changes: [
          'Swapped the brisk walk for chair marching, because you said your knee hurt.',
          'Moved dinner earlier.',
        ],
      ),
    );
    expect(find.text('Mochi updated your plan'), findsOneWidget);
    expect(find.text('Swapped the brisk walk for chair marching, because you said your knee hurt.'), findsOneWidget);
    expect(find.text('Moved dinner earlier.'), findsOneWidget);
    expect(find.text('Your plan stays the same today.'), findsNothing);
    await t.tap(find.text('Here’s today’s plan'));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget, reason: 'back on the screen the check-in was opened from');
  });

  testWidgets('after a check-in with nothing changed: Your plan stays the same today', (t) async {
    await afterCheckIn(t, const TodayUpdate(encouragement: 'Nice work.', changes: []));
    expect(find.text('Your plan stays the same today.'), findsOneWidget);
    expect(find.text('Mochi updated your plan'), findsNothing);
    expect(find.text('Here’s today’s plan'), findsOneWidget);
  });

  test('a revision lists only real changes (the live coach also reports kept items and fresh encouragement)', () {
    final plan = DailyPlan.fromJson({
      'schema_version': '1.0',
      'status': 'ok',
      'revision_id': 'r2',
      'local_date': '2026-10-24',
      'based_on': 'r1',
      'inputs': {'snapshot_id': 's1'},
      'plan_type': 'personal',
      'items': [
        item('move', 'workout', 'Swimming', minutes: 20),
        item('food', 'diet', 'Protein at each meal'),
        item('cheer', 'encourage', 'A word from Mochi'),
      ],
      'changes': [
        {
          'item_id': 'move',
          'change': 'swapped',
          'explanation': 'You said a brisk walk hurt your knee, so today is swimming.',
        },
        {'item_id': 'food', 'change': 'kept', 'explanation': 'Kept protein, since nothing called for a change.'},
        {'item_id': 'cheer', 'change': 'new', 'explanation': 'Fresh words from how your days went.'},
      ],
    });
    expect(plan.changedLines, ['You said a brisk walk hurt your knee, so today is swimming.']);
  });

  test('the coach request maps the phone\'s 1-5 general health to the server labels, and passes labels through', () {
    for (final (n, label) in [(1, 'excellent'), (2, 'very_good'), (3, 'good'), (4, 'fair'), (5, 'poor')]) {
      final body = coachRequestBody({
        'profile': {'age': 64, 'general_health': n},
      });
      expect((body['profile'] as Map)['general_health'], label);
    }
    expect(
      (coachRequestBody({
            'profile': {'general_health': 'good'},
          })['profile']
          as Map)['general_health'],
      'good',
    );
    expect(
      (coachRequestBody({
            'profile': {'general_health': 7},
          })['profile']
          as Map)['general_health'],
      7,
    );
    expect(coachRequestBody({'local_date': 'x'}), {'local_date': 'x'});
  });
}
