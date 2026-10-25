import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/experiment/ideas_hub.dart';
import 'package:lifesim/experiment/recommendations.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/wellness/coach_client.dart';
import 'package:lifesim/wellness/today_card.dart';

import 'today_card_test.dart' show fourSlots;

class _IdeasOverHttp implements RecommendationsSource {
  _IdeasOverHttp(this.client);
  final http.Client client;
  @override
  Future<List<Recommendation>> load() async {
    await client.post(Uri.parse('http://a/api/recommendations'));
    return const [];
  }
}

class _CountingIdeas implements RecommendationsSource {
  _CountingIdeas(this.onLoad);
  final void Function() onLoad;
  @override
  Future<List<Recommendation>> load() async {
    onLoad();
    return const [];
  }
}

class _SlowCoach extends CoachClient {
  int calls = 0;
  @override
  Future<DailyPlan> plan(Map<String, dynamic> confirmedContext) async {
    calls++;
    await Future<void>.delayed(const Duration(seconds: 3));
    return fourSlots(revision: 'r2');
  }
}

IdeasAccess _access(IdeasHub hub) =>
    IdeasAccess(hub: hub, openIdea: (_, _) {}, openList: (_, {required origin, levers}) {});

void main() {
  testWidgets('the plan shows when the plan request returns, whatever the slow ideas call does', (t) async {
    final start = t.binding.clock.now();
    final log = <String>[];
    int ms() => t.binding.clock.now().difference(start).inMilliseconds;
    final planBody = jsonEncode(fourSlots().json);
    final mock = MockClient((r) async {
      final began = ms();
      final delay = switch (r.url.path) {
        '/api/coach/plan' => const Duration(milliseconds: 5),
        '/api/recommendations' => const Duration(seconds: 10),
        _ => const Duration(milliseconds: 20),
      };
      await Future<void>.delayed(delay);
      log.add('${r.url.path} $began-${ms()}');
      return http.Response(r.url.path == '/api/coach/plan' ? planBody : '{}', 200);
    });
    final base = ApiBase('http://a,http://b', mock);
    final hub = IdeasHub(source: _IdeasOverHttp(mock));

    t.view.physicalSize = const Size(390, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: Scaffold(
          body: TodayWithMochiCard(
            client: HttpCoachClient(base: base, client: mock),
            ideas: _access(hub),
            condensed: true,
            confirmedContext: () => {'local_date': '2026-10-24'},
            onOpen: () {},
          ),
        ),
      ),
    );
    var shownAt = -1;
    for (var i = 0; i < 12000 && shownAt < 0; i += 50) {
      await t.pump(const Duration(milliseconds: 50));
      if (find.textContaining('seated marching', findRichText: true).evaluate().isNotEmpty) shownAt = ms();
    }
    // ignore: avoid_print
    print('plan visible at ${shownAt}ms; requests: $log');
    expect(shownAt, inInclusiveRange(0, 1500));
    await t.pump(const Duration(seconds: 11));
    expect(log.where((e) => e.startsWith('/api/coach/plan')), hasLength(1));
    expect(log.where((e) => e.startsWith('/api/recommendations')), hasLength(1));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('leaving before the plan returns asks for no ideas and throws nothing', (t) async {
    var ideasAsked = 0;
    final hub = IdeasHub(source: _CountingIdeas(() => ideasAsked++));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayWithMochiCard(client: _SlowCoach(), ideas: _access(hub), confirmedContext: () => {}, onOpen: () {}),
        ),
      ),
    );
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
    expect(ideasAsked, 0);
  });

  testWidgets('a plan from earlier shows at once while the new one is fetched', (t) async {
    final coach = _SlowCoach();
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TodayWithMochiCard(client: coach, initialPlan: fourSlots(), confirmedContext: () => {}, onOpen: () {}),
          ),
        ),
      ),
    );
    expect(find.text('Seated marching · 10 min'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    expect(coach.calls, 1);
    await t.pumpWidget(const SizedBox());
  });
}
