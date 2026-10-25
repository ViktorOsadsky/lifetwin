import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/wellness/coach_client.dart';
import 'package:lifesim/wellness/daily_plan_screen.dart';

import 'screens_test.dart' show phone, reveal;

Map<String, dynamic> planJson({String revision = 'r1'}) => {
  'schema_version': '1.0',
  'status': 'ok',
  'revision_id': revision,
  'local_date': '2026-10-24',
  'based_on': null,
  'inputs': {'snapshot_id': 'snapshot1'},
  'plan_type': 'general',
  'changes': [],
  'trace': [],
  'items': [
    {
      'id': 'move',
      'kind': 'workout',
      'catalog_id': 'walk',
      'title': 'A short walk',
      'message': 'Choose a comfortable pace.',
      'why': 'A general activity idea.',
      'minutes': 10,
      'time_of_day': 'morning',
      'source_title': 'CDC activity guidance',
      'source_url':
          'https://www.cdc.gov/physical-activity-basics/guidelines/adults.html',
      'reviewed_by': 'awaiting professional review',
      'causal_interpretation': false,
    },
  ],
};

class FakeCoach extends CoachClient {
  final requests = <Map<String, dynamic>>[];
  final responses = <Object>[];
  @override
  Future<DailyPlan> plan(Map<String, dynamic> value) async {
    requests.add(jsonDecode(jsonEncode(value)) as Map<String, dynamic>);
    final response = responses.removeAt(0);
    if (response is DailyPlan) return response;
    throw response;
  }
}

void main() {
  test('coach parser excludes supplements, unknown actions and unsupported sources', () {
    final json = planJson();
    final item = (json['items'] as List).first as Map;
    json['items'] = [
      item,
      {...item, 'id': 'food', 'title': 'Try a vitamin supplement'},
      {...item, 'kind': 'prescription'},
    ];
    final plan = DailyPlan.fromJson(json);
    expect(plan.items.length, 1);
    expect(plan.items.single['title'], 'A short walk');
    expect(
      () => DailyPlan.fromJson({
        ...planJson(),
        'items': [
          {...item, 'source_url': 'javascript:alert(1)'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => DailyPlan.fromJson({
        ...planJson(),
        'items': [
          {...item, 'causal_interpretation': true},
        ],
      }),
      throwsFormatException,
    );
  });
  test(
    'HTTP adapter posts only supplied context and preserves typed failures',
    () async {
      final client = HttpCoachClient(
        base: ApiBase('https://example.test'),
        client: MockClient((request) async {
          expect(request.url.path, '/api/coach/plan');
          expect(jsonDecode(request.body), {
            'local_date': '2026-10-24',
            'outside_ai_consent': {'muse': false},
          });
          return http.Response(jsonEncode(planJson()), 200);
        }),
      );
      expect(
        (await client.plan({
          'local_date': '2026-10-24',
          'outside_ai_consent': {'muse': false},
        })).revision,
        'r1',
      );
      final failed = HttpCoachClient(
        base: ApiBase('https://example.test'),
        client: MockClient((_) async => http.Response('{}', 429)),
      );
      await expectLater(
        failed.plan({}),
        throwsA(isA<CoachFailure>().having((e) => e.statusCode, 'status', 429)),
      );
    },
  );
  testWidgets(
    'not-done feedback includes revision and optional reason, with fresh consent',
    (t) async {
      final client = FakeCoach()
        ..responses.add(DailyPlan.fromJson(planJson(revision: 'r2')));
      final context = {
        'local_date': '2026-10-24',
        'memory_consent': false,
        'habit_notes': ['not authorized'],
        'outside_ai_consent': {'muse': false},
      };
      await phone(
        t,
        DailyPlanScreen(
          client: client,
          confirmedContext: () => context,
          initialPlan: DailyPlan.fromJson(planJson()),
          onBack: () {},
          onTalk: () {},
        ),
      );
      await reveal(t, find.text('Not done'));
      await t.tap(find.text('Not done'));
      await t.pumpAndSettle();
      await t.tap(find.text('Knee hurt'));
      await t.pump();
      await t.tap(find.text('Tell Mochi'));
      await t.pumpAndSettle();
      final sent = client.requests.single;
      expect(sent['habit_notes'], isNull);
      expect(context['habit_notes'], isNotNull);
      expect(sent['latest_revision_id'], 'r1');
      expect(sent['feedback'], {
        'revision_id': 'r1',
        'items': [
          {'item_id': 'move', 'status': 'not_done', 'reason': 'Knee hurt'},
        ],
      });
      expect(sent['outside_ai_consent'], {'muse': false});
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'stale feedback preserves the old plan and refreshes from current inputs',
    (t) async {
      final client = FakeCoach()
        ..responses.addAll([
          const CoachFailure(409),
          DailyPlan.fromJson(planJson(revision: 'r3')),
        ]);
      var consent = false;
      await phone(
        t,
        DailyPlanScreen(
          client: client,
          confirmedContext: () => {
            'local_date': '2026-10-24',
            'outside_ai_consent': {'muse': consent},
          },
          initialPlan: DailyPlan.fromJson(planJson()),
          onBack: () {},
          onTalk: () {},
        ),
      );
      await reveal(t, find.text('Yes'));
      final yes = find.widgetWithText(OutlinedButton, 'Yes');
      expect(t.getSize(yes).height, greaterThanOrEqualTo(48));
      final color = t
          .widget<OutlinedButton>(yes)
          .style!
          .foregroundColor!
          .resolve({})!;
      expect(
        (LtColors.paper.computeLuminance() + .05) /
            (color.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
      await t.tap(find.text('Yes'));
      await t.pumpAndSettle();
      expect(find.text('On your plan'), findsNothing);
      await t.scrollUntilVisible(
        find.text('Refresh plan'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      consent = true;
      await t.tap(find.text('Refresh plan'));
      await t.pumpAndSettle();
      expect(client.requests.last['previous_plan'], isNull);
      expect(client.requests.last['feedback'], isNull);
      expect(client.requests.last['outside_ai_consent'], {'muse': true});
      expect(t.takeException(), isNull);
    },
  );

  for (final entry in {
    422: 'Mochi couldn’t make today’s plan from what’s saved',
    503: 'The plan couldn’t connect. Your saved plan is still here.',
    429: 'A lot is happening. Give it a moment, then try again.',
  }.entries) {
    testWidgets('HTTP ${entry.key} shows the right plan message', (t) async {
      final client = FakeCoach()..responses.add(CoachFailure(entry.key));
      await phone(
        t,
        DailyPlanScreen(
          client: client,
          confirmedContext: () => {'local_date': '2026-10-24'},
          initialPlan: DailyPlan.fromJson(planJson()),
          onBack: () {},
          onTalk: () {},
        ),
      );
      await reveal(t, find.text('Yes'));
      await t.tap(find.text('Yes'));
      await t.pumpAndSettle();
      final message = find.textContaining(entry.value, findRichText: true);
      await t.scrollUntilVisible(
        message,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(message, findsOneWidget);
      if (entry.key == 422) {
        expect(
          find.textContaining('couldn’t connect', findRichText: true),
          findsNothing,
        );
      }
      expect(t.takeException(), isNull);
    });
  }
}
