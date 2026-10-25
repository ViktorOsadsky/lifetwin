// The plan's "What changed" card (bug hunt A): the live coach reports every kept item ("Nothing new since
// today's plan, so it stays the same.") and Mochi's fresh words as changes too. After "Yes to all" the card
// read the same sentence four times. It lists only real changes, each once.
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/wellness/coach_client.dart';
import 'package:lifesim/wellness/daily_plan_screen.dart';
import 'package:lifesim/wellness/plan_acceptance.dart';

import 'coach_test.dart' show FakeCoach;
import 'screens_test.dart' show phone;

const _kept = "Nothing new since today's plan, so it stays the same.";

Map<String, dynamic> _item(String id, String kind, String title) => {
  'id': id,
  'kind': kind,
  'catalog_id': id,
  'title': title,
  'message': '$title, gently.',
  'why': 'Why $id.',
  'minutes': null,
  'time_of_day': 'morning',
  'source_title': 'CDC guidance',
  'source_url': 'https://www.cdc.gov/physical-activity-basics/guidelines/adults.html',
  'reviewed_by': 'awaiting professional review',
  'causal_interpretation': false,
};

DailyPlan _plan(List<Map<String, dynamic>> changes) => DailyPlan.fromJson({
  'schema_version': '1.0',
  'status': 'ok',
  'revision_id': 'r2',
  'local_date': '2026-10-24',
  'based_on': 'r1',
  'inputs': {'snapshot_id': 's1'},
  'plan_type': 'personal',
  'trace': [],
  'items': [
    _item('move', 'workout', 'Swimming'),
    _item('food', 'diet', 'Protein at each meal'),
    _item('habit', 'habit', 'Up during the ad breaks'),
    _item('cheer', 'encourage', 'A word from Mochi'),
  ],
  'changes': changes,
});

/// Shows the plan and scrolls the lazy list to its end, where "What changed" sits.
Future<void> _show(WidgetTester t, DailyPlan plan) async {
  await phone(
    t,
    DailyPlanScreen(
      client: FakeCoach(),
      confirmedContext: () => {'local_date': '2026-10-24'},
      initialPlan: plan,
      acceptance: PlanAcceptance(MemoryPlanStore()),
      onBack: () {},
      onTalk: () {},
    ),
  );
  await t.scrollUntilVisible(find.textContaining('Habit ideas, not medical advice'), 300);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('kept items and fresh encouragement are not listed under What changed', (t) async {
    await _show(
      t,
      _plan([
        for (final id in ['move', 'food', 'habit']) {'item_id': id, 'change': 'kept', 'explanation': _kept},
        {'item_id': 'cheer', 'change': 'new', 'explanation': 'Fresh words from how your days went.'},
      ]),
    );
    expect(find.text('What changed', skipOffstage: false), findsNothing);
    expect(find.text(_kept, skipOffstage: false), findsNothing);
    expect(find.text('Fresh words from how your days went.', skipOffstage: false), findsNothing);
  });

  testWidgets('a real change is listed once, without the kept lines', (t) async {
    const swap = 'You said a brisk walk hurt your knee, so today is swimming.';
    await _show(
      t,
      _plan([
        {'item_id': 'move', 'change': 'swapped', 'explanation': swap},
        {'item_id': 'move', 'change': 'swapped', 'explanation': swap},
        {'item_id': 'food', 'change': 'kept', 'explanation': _kept},
        {'item_id': 'habit', 'change': 'kept', 'explanation': _kept},
      ]),
    );
    expect(find.text('What changed', skipOffstage: false), findsOneWidget);
    expect(find.text(swap, skipOffstage: false), findsOneWidget);
    expect(find.text(_kept, skipOffstage: false), findsNothing);
  });
}
