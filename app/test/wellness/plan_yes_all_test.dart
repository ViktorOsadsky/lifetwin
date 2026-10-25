import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/widgets/widgets.dart' show LipButton;
import 'package:lifesim/wellness/coach_client.dart';
import 'package:lifesim/wellness/daily_plan_screen.dart';
import 'package:lifesim/wellness/plan_acceptance.dart';
import 'package:lifesim/wellness/today_card.dart';
import 'package:lifesim/wellness/widgets.dart' show WellnessCard;

import 'coach_test.dart' show FakeCoach;
import 'screens_test.dart' show phone, reveal;

Map<String, dynamic> _item(String id, String kind, String title, {String? swap}) => {
  'id': swap ?? id,
  'kind': kind,
  'catalog_id': id,
  'title': swap == null ? title : 'Swapped $title',
  'message': '$title, gently.',
  'why': 'Why $id.',
  'minutes': null,
  'time_of_day': 'morning',
  'source_title': 'CDC guidance',
  'source_url': 'https://www.cdc.gov/physical-activity-basics/guidelines/adults.html',
  'reviewed_by': 'awaiting professional review',
  'causal_interpretation': false,
};

DailyPlan _plan({String revision = 'r1', String? swapMove, bool cheer = false}) => DailyPlan.fromJson({
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
    _item('move', 'workout', 'Walk', swap: swapMove),
    _item('eat', 'diet', 'Veg'),
    _item('habit', 'habit', 'Lights out'),
    if (cheer) {..._item('hi', 'encourage', 'Cheer'), 'message': 'You are doing great.'},
  ],
});

class _SlowCoach extends FakeCoach {
  final gate = Completer<void>();
  @override
  Future<DailyPlan> plan(Map<String, dynamic> value) async {
    await gate.future;
    return super.plan(value);
  }
}

Widget _screen(CoachClient c, PlanAcceptance a, {DailyPlan? plan, Future<void> Function()? remind}) => DailyPlanScreen(
  client: c,
  confirmedContext: () => {'local_date': '2026-10-24'},
  initialPlan: plan ?? _plan(),
  acceptance: a,
  onRemind: remind,
  onBack: () {},
  onTalk: () {},
);

Future<void> _top(WidgetTester t) async {
  await t.drag(find.byType(ListView), const Offset(0, 5000));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Yes to all marks every item accepted and shows the confirmation', (t) async {
    final handle = t.ensureSemantics();
    final coach = FakeCoach()..responses.add(_plan(revision: 'r2', cheer: true));
    final a = PlanAcceptance(MemoryPlanStore());
    await phone(t, _screen(coach, a, plan: _plan(cheer: true)));
    await reveal(t, find.text('Yes to all'));
    await t.tap(find.text('Yes to all'));
    await t.pumpAndSettle();
    final items = (coach.requests.single['feedback'] as Map)['items'] as List;
    expect(items.length, 4);
    expect(items.every((i) => (i as Map)['status'] == 'accepted'), isTrue);
    await reveal(t, find.text('You’re set for today ✓'));
    expect(find.text('✓ In your plan', skipOffstage: false), findsWidgets);
    expect(find.text('You are doing great.', skipOffstage: false), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('You’re set for today')), findsWidgets);
    await _top(t);
    expect(find.bySemanticsLabel(RegExp('In your plan: Walk')), findsOneWidget);
    expect(find.text('Remind me later'), findsNothing);
    expect(a.idsFor('2026-10-24'), {'move', 'eat', 'habit', 'hi'});
    expect(a.unsyncedFor('2026-10-24'), isFalse);
    handle.dispose();
  });

  testWidgets('template cheer, Remind me later when reminders are on, and Back to Home lands on the first route', (
    t,
  ) async {
    var reminded = 0;
    final coach = FakeCoach()..responses.add(_plan(revision: 'r2'));
    final a = PlanAcceptance(MemoryPlanStore());
    t.view.physicalSize = const Size(320, 693);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<void>(builder: (_) => _screen(coach, a, remind: () async => reminded++)),
                ),
                child: const Text('The Room'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('The Room'));
    await t.pumpAndSettle();
    await reveal(t, find.text('Yes to all'));
    await t.tap(find.text('Yes to all'));
    await t.pumpAndSettle();
    await reveal(t, find.text('Remind me later'));
    expect(find.text('Nice. Small steps add up.'), findsOneWidget);
    await t.tap(find.text('Remind me later'));
    await t.pumpAndSettle();
    expect(reminded, 1);
    expect(find.text('Remind me later'), findsNothing);
    await reveal(t, find.text('Back to Home'));
    await t.tap(find.text('Back to Home'));
    await t.pumpAndSettle();
    expect(find.text('The Room'), findsOneWidget);
    expect(find.byType(DailyPlanScreen), findsNothing);
  });

  testWidgets('Home Today card reads accepted and survives a rebuild from the store', (t) async {
    final store = MemoryPlanStore();
    final a = PlanAcceptance(store);
    final coach = FakeCoach()..responses.add(_plan(revision: 'r2'));
    await phone(t, _screen(coach, a));
    await reveal(t, find.text('Yes to all'));
    await t.tap(find.text('Yes to all'));
    await t.pumpAndSettle();

    // Leave, and come back later: a new object over the same store.
    final again = PlanAcceptance(store);
    await again.load();
    final home = FakeCoach()..responses.add(_plan());
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: Scaffold(
          body: TodayWithMochiCard(client: home, confirmedContext: () => {}, onOpen: () {}, condensed: true, acceptance: again),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Today: 3 things planned ✓', findRichText: true), findsOneWidget);

    // A different day starts fresh.
    expect(again.idsFor('2026-10-25'), isEmpty);
  });

  testWidgets('Not for me and Skip after Yes to all change one item and the count', (t) async {
    final coach = FakeCoach()
      ..responses.addAll([_plan(revision: 'r2'), _plan(revision: 'r3', swapMove: 'x'), _plan(revision: 'r4', swapMove: 'x')]);
    final a = PlanAcceptance(MemoryPlanStore());
    await phone(t, _screen(coach, a));
    await reveal(t, find.text('Yes to all'));
    await t.tap(find.text('Yes to all'));
    await t.pumpAndSettle();
    await _top(t);
    expect(find.text('3 of 3 in your plan'), findsOneWidget);

    await _top(t);
    await reveal(t, find.text('Not for me').first);
    await t.tap(find.text('Not for me').first);
    await t.pumpAndSettle();
    await _top(t);
    expect(find.text('2 of 3 in your plan'), findsOneWidget);
    expect(find.text('Swapped Walk'), findsOneWidget);
    await reveal(t, find.text('Yes to all'));
    expect(find.text('You’re set for today ✓'), findsNothing);

    await _top(t);
    await reveal(t, find.text('Lights out'));
    final skip = find.descendant(
      of: find.ancestor(of: find.text('Lights out'), matching: find.byType(WellnessCard)),
      matching: find.text('Skip'),
    );
    await reveal(t, skip);
    await t.tap(skip);
    await t.pumpAndSettle();
    await _top(t);
    expect(find.text('1 of 3 in your plan'), findsOneWidget);
    expect(a.idsFor('2026-10-24'), {'eat'});
  });

  testWidgets('Yes to all is disabled with a visible reason while the plan is busy', (t) async {
    final coach = _SlowCoach()..responses.add(_plan(revision: 'r2'));
    await phone(t, _screen(coach, PlanAcceptance(MemoryPlanStore())));
    await reveal(t, find.text('Skip').first);
    await t.tap(find.text('Skip').first);
    await t.pump();
    await reveal(t, find.text('Yes to all'));
    expect(find.text('Plan is still loading. Try again in a moment.'), findsOneWidget);
    coach.gate.complete();
    await t.pumpAndSettle();
    expect(find.text('Plan is still loading. Try again in a moment.'), findsNothing);
  });

  testWidgets('a failed request keeps the accepted state, shows no error, and retries on the next open', (t) async {
    final store = MemoryPlanStore();
    final a = PlanAcceptance(store);
    final coach = FakeCoach()..responses.add(const CoachFailure(null));
    await phone(t, _screen(coach, a));
    await reveal(t, find.text('Yes to all'));
    await t.tap(find.text('Yes to all'));
    await t.pumpAndSettle();
    await reveal(t, find.text('You’re set for today ✓'));
    expect(find.text('Saved on this phone'), findsOneWidget);
    expect(find.text('Refresh plan'), findsNothing);
    expect(find.textContaining('couldn’t'), findsNothing);
    expect(a.unsyncedFor('2026-10-24'), isTrue);

    // Next time the screen opens, the feedback is sent again, quietly.
    final b = PlanAcceptance(store);
    await b.load();
    final retry = FakeCoach()..responses.add(_plan(revision: 'r2'));
    await t.pumpWidget(const SizedBox());
    await phone(t, _screen(retry, b));
    await t.pumpAndSettle();
    expect(retry.requests.single['feedback'], {
      'revision_id': 'r1',
      'items': [
        for (final id in ['move', 'eat', 'habit']) {'item_id': id, 'status': 'accepted'},
      ],
    });
    expect(b.unsyncedFor('2026-10-24'), isFalse);
    await reveal(t, find.text('You’re set for today ✓'));
    expect(find.text('Saved on this phone'), findsNothing);
  });

  testWidgets('the confirmation has no overflow at 1.6x text', (t) async {
    final coach = FakeCoach()..responses.add(_plan(revision: 'r2', cheer: true));
    await phone(t, _screen(coach, PlanAcceptance(MemoryPlanStore()), plan: _plan(cheer: true), remind: () async {}), scale: 1.6);
    await reveal(t, find.text('Yes to all'));
    await t.tap(find.text('Yes to all'));
    await t.pumpAndSettle();
    await reveal(t, find.text('Back to Home'));
    final r = t.getRect(find.ancestor(of: find.text('Back to Home'), matching: find.byType(LipButton)).first);
    expect(r.height, greaterThanOrEqualTo(48));
    expect(r.right, lessThanOrEqualTo(320));
    expect(t.takeException(), isNull);
  });
}
