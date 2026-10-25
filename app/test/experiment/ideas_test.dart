// Ideas for you (design set I): the list, detail, effect sheet, not-yet and error states, Try with a
// preset, the entry points, the under-18 gate, and the Today card's two Home rules (compact; no consent
// ask until the person taps).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/consents.dart';
import 'package:lifesim/experiment/experiment_screen.dart';
import 'package:lifesim/experiment/idea_detail_screen.dart';
import 'package:lifesim/experiment/ideas_list_screen.dart';
import 'package:lifesim/experiment/lever_detail_screen.dart';
import 'package:lifesim/experiment/recommendations.dart';
import 'package:lifesim/experiment/widgets/idea_card.dart';
import 'package:lifesim/twin/twin_experiment.dart' show LeverId;
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/wellness/coach_client.dart' show DailyPlan;
import 'package:lifesim/wellness/today_card.dart';

import '../support/app_fonts.dart';
import '../wellness/coach_test.dart' show FakeCoach;
import '../wellness/today_card_test.dart' show fourSlots, item;
import 'experiment_screen_test.dart' show older;

class FakeSource implements RecommendationsSource {
  FakeSource(this.result);
  Object result;
  int calls = 0;
  @override
  Future<List<Recommendation>> load() async {
    calls++;
    final r = result;
    if (r is Exception) throw r;
    return r as List<Recommendation>;
  }
}

class FakeCaps implements CapabilitiesClient {
  FakeCaps(this.provider);
  final AiProvider? provider;
  @override
  Future<AiProvider?> personalize() async => provider;
}

const pace = Recommendation(
  id: 'vigorous_plus_60',
  title: 'Pick up the pace',
  tip: 'You said you walk with your dog. You could try a faster pace for part of it.',
  wellnessCardId: 'activity',
  leverId: LeverId.vigorous,
  leverValue: 60,
  whyShort: 'Walk faster for part of your dog walks, toward the weekly 150.',
  effect: 'some',
  sourceTitle: 'CDC: Physical activity for adults',
  sourceUrl:
      'https://www.cdc.gov/physical-activity-basics/guidelines/adults.html',
  sourceDomain: 'cdc.gov',
);
const sleep = Recommendation(
  id: 'short_sleep_plus_1h',
  title: 'A bit more sleep',
  tip: 'A bedtime that leaves room for 7 hours.',
  wellnessCardId: 'sleep',
  leverId: LeverId.sleepHours,
  leverValue: 7,
  whyShort: 'A bedtime that leaves room for 7 hours.',
  effect: 'small',
);
const sit = Recommendation(
  id: 'sitting_minus_60',
  title: 'Sit a little less',
  tip: 'Stand up for a few minutes every hour.',
  wellnessCardId: 'sitting',
  leverId: LeverId.sitting,
  whyShort: 'Stand up for a few minutes every hour.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<TwinRepository> repo([Map<String, dynamic> p = older]) async {
    final r = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => DateTime(2026, 10, 26),
    );
    await r.saveConversationProfile(p);
    return r;
  }

  Future<AgenticRoutes> routes(
    Map<String, dynamic> p, {
    FakeCoach? coach,
    AiProvider? provider,
    FakeSource? source,
  }) async {
    final r = await repo(p);
    final a = AgenticRoutes(
      look: ValueNotifier(const TwinAppearance()),
      api: ApiBase(),
      voice: () => throw UnimplementedError(),
      coach: coach ?? FakeCoach(),
      capabilities: FakeCaps(provider),
      ideasSource: (_) => source ?? FakeSource([pace]),
    );
    a.attach(r);
    return a;
  }

  final shot = GlobalKey();
  Future<void> pumpIn(WidgetTester t, Widget home, {double scale = 1}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          theme: lifeTwinTheme(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await t.pump();
    await t.pump();
  }

  Widget list(
    RecommendationsSource source, {
    void Function(Recommendation)? onTry,
    AiProvider? worded,
    List<String> missing = const [],
  }) => IdeasListScreen(
    source: source,
    appearance: const TwinAppearance(),
    origin: 'Today',
    missingInputs: missing,
    worded: worded,
    onBack: () {},
    onTry: onTry ?? (_) {},
  );

  Future<void> evidence(WidgetTester t, String name) async {
    final dir = Directory(
      const String.fromEnvironment('SHOTS', defaultValue: '/tmp/ideas_shots'),
    )..createSync(recursive: true);
    await t.runAsync(() async {
      final b =
          shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage();
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/$name.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  const note = 'Modeled difference for people like you, not a promise.';

  group('the list', () {
    testWidgets(
      'renders three cards, the first with the filled Try, and a Back to {origin}',
      (t) async {
        await pumpIn(t, list(FakeSource([pace, sleep, sit])));
        expect(find.byType(IdeaCard), findsNWidgets(3));
        expect(find.text('Pick up the pace'), findsOneWidget);
        expect(find.text('Try it with my twin'), findsNWidgets(3));
        expect(find.bySemanticsLabel('Back to Today'), findsOneWidget);
        expect(find.text('Linked, not proven.'), findsOneWidget);
        expect(find.text('About this ›'), findsOneWidget);
        await evidence(t, 'ideas_list');
      },
    );

    testWidgets('the effect note is on the first screen, at 1.0x and 1.6x', (
      t,
    ) async {
      for (final scale in [1.0, 1.6]) {
        await pumpIn(t, list(FakeSource([pace, sleep, sit])), scale: scale);
        final line = find.text(note);
        expect(line, findsOneWidget, reason: '$scale');
        final rect = t.getRect(line);
        expect(
          rect.bottom,
          lessThan(844),
          reason: 'visible on the first screen at $scale',
        );
        expect(
          rect.top,
          lessThan(t.getTopLeft(find.byType(IdeaCard).first).dy),
          reason: 'above the first card',
        );
        final style = t
            .widget<Text>(
              find.descendant(of: find.byType(Scaffold), matching: line),
            )
            .style!;
        expect(style.fontSize, 17);
        expect(style.color, const Color(0xFF6B4E42));
        if (scale > 1) await evidence(t, 'ideas_list_large');
      }
    });

    testWidgets('the why line stays at 1.6x and wraps', (t) async {
      await pumpIn(t, list(FakeSource([pace, sleep, sit])), scale: 1.6);
      expect(find.text(pace.whyShort), findsOneWidget);
      expect(t.takeException(), isNull);
      // Wrapped: taller than one line of 18px at 1.6x.
      expect(
        t.getSize(find.text(pace.whyShort)).height,
        greaterThan(18 * 1.6 * 1.4),
      );
    });

    testWidgets(
      'the effect cue shows the level; a null effect has no cue; the cue opens the sheet',
      (t) async {
        await pumpIn(t, list(FakeSource([pace, sleep, sit])));
        // Only ideas with an effect level draw a cue.
        expect(find.byType(EffectCue), findsNWidgets(2));
        expect(find.text('Some'), findsOneWidget);
        expect(find.text('Small'), findsOneWidget);
        await t.tap(find.text('Some'));
        await t.pumpAndSettle();
        expect(find.text('Linked, not proven.'), findsNWidgets(2));
        expect(find.text('Got it'), findsOneWidget);
        await t.tap(find.text('Got it'));
        await t.pumpAndSettle();
        expect(find.text('Got it'), findsNothing);
      },
    );

    testWidgets(
      'the training line shows only when may_train_on_content is true',
      (t) async {
        const on = AiProvider(
          id: 'muse',
          displayName: 'Muse by Meta',
          configured: true,
          company: 'Meta',
          mayTrainOnContent: true,
        );
        const off = AiProvider(
          id: 'muse',
          displayName: 'Muse by Meta',
          configured: true,
          company: 'Meta',
        );
        await pumpIn(
          t,
          list(FakeSource([pace, sleep, sit]), worded: on),
          scale: 1,
        );
        expect(
          find.textContaining('Worded with Muse by Meta.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Meta may use what you share to improve its AI.'),
          findsOneWidget,
        );
        await pumpIn(t, list(FakeSource([pace, sleep, sit]), worded: off));
        expect(
          find.textContaining('Worded with Muse by Meta.'),
          findsOneWidget,
        );
        expect(find.textContaining('may use what you share'), findsNothing);
        await pumpIn(t, list(FakeSource([pace, sleep, sit])));
        expect(find.textContaining('Worded with'), findsNothing);
      },
    );

    testWidgets('Try hands over the tapped idea', (t) async {
      final tried = <Recommendation>[];
      await pumpIn(t, list(FakeSource([pace, sleep, sit]), onTry: tried.add));
      await t.tap(find.text('Try it with my twin').first);
      expect(tried.map((i) => i.id), ['vigorous_plus_60']);
    });

    testWidgets(
      'tapping a card opens the detail with the full why line and the source',
      (t) async {
        await pumpIn(t, list(FakeSource([pace, sleep, sit])));
        await t.tap(find.text('Pick up the pace'));
        await t.pumpAndSettle();
        expect(find.byType(IdeaDetailScreen), findsOneWidget);
        expect(
          find.textContaining('toward the weekly 150.', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('What the model says'), findsOneWidget);
        expect(find.text(note), findsOneWidget);
        expect(
          find.textContaining('CDC: Physical activity for adults'),
          findsOneWidget,
        );
        expect(find.text('Add to my plan'), findsNothing);
        await evidence(t, 'ideas_detail');
      },
    );
  });

  group('states', () {
    testWidgets('offline: connection copy and Try again reloads', (t) async {
      final src = FakeSource(const RecommendationsFailure(null));
      await pumpIn(t, list(src));
      expect(
        find.text('Check your connection, then try again.'),
        findsOneWidget,
      );
      expect(find.text('Your answers are safe.'), findsOneWidget);
      src.result = [pace];
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(src.calls, 2);
      expect(find.byType(IdeaCard), findsOneWidget);
    });

    testWidgets('a server status is "Something went wrong on our side"', (
      t,
    ) async {
      await pumpIn(t, list(FakeSource(const RecommendationsFailure(500))));
      expect(
        find.text('Something went wrong on our side. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Check your connection, then try again.'), findsNothing);
      await evidence(t, 'ideas_error');
    });

    testWidgets(
      'not enough information: the message and the missing answers in plain words',
      (t) async {
        await pumpIn(
          t,
          list(
            FakeSource(<Recommendation>[]),
            missing: const ['sleep_hours', 'sedentary_min_day'],
          ),
        );
        expect(find.text('A few more answers'), findsOneWidget);
        expect(find.text('Hours of sleep'), findsOneWidget);
        expect(find.text('Time spent sitting each day'), findsOneWidget);
        expect(find.text('Answer 2 more questions'), findsOneWidget);
        await evidence(t, 'ideas_not_yet');
      },
    );
  });

  group('Try opens the Experiment with the lever preset', () {
    testWidgets('a value presets the lever', (t) async {
      final r = await repo();
      await pumpIn(
        t,
        ExperimentScreen(
          repository: r,
          appearance: const TwinAppearance(),
          presetLever: LeverId.sleepHours,
          presetValue: 8,
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(LeverDetailScreen), findsOneWidget);
      expect(find.textContaining('8'), findsWidgets);
      expect(find.text('Use in my what-if'), findsOneWidget);
    });

    testWidgets(
      'a null value opens the lever with no preset (the person\'s own value, never 0)',
      (t) async {
        final r = await repo();
        await pumpIn(
          t,
          ExperimentScreen(
            repository: r,
            appearance: const TwinAppearance(),
            presetLever: LeverId.sleepHours,
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(LeverDetailScreen), findsOneWidget);
        expect(find.textContaining('6'), findsWidgets);
        expect(find.textContaining('0 hours'), findsNothing);
      },
    );

    testWidgets(
      'the hub shows the Ideas row only when it is given an entry, and Back follows the origin',
      (t) async {
        final r = await repo();
        await pumpIn(
          t,
          ExperimentScreen(repository: r, appearance: const TwinAppearance()),
        );
        expect(find.text('Ideas for you'), findsNothing);
        var opened = 0;
        await pumpIn(
          t,
          ExperimentScreen(
            repository: r,
            appearance: const TwinAppearance(),
            onIdeas: () => opened++,
            backLabel: 'Back to ideas',
          ),
        );
        await t.tap(find.text('Ideas for you'));
        expect(opened, 1);
        expect(find.bySemanticsLabel('Back to ideas'), findsOneWidget);
      },
    );
  });

  group('entry points and the age gate', () {
    testWidgets(
      'under 18: not allowed, no entry point, and the endpoint is never called',
      (t) async {
        final src = FakeSource([pace]);
        final a = await routes({...older, 'age': 16}, source: src);
        expect(a.ideasAllowed, isFalse);
        await pumpIn(
          t,
          Builder(
            builder: (c) => TextButton(
              onPressed: () => a.drivers(c),
              child: const Text('go'),
            ),
          ),
        );
        await t.tap(find.text('go'));
        await t.pumpAndSettle();
        expect(find.text('See ideas'), findsNothing);
        await a.ideas(t.element(find.byType(Scaffold)), origin: 'room');
        await t.pumpAndSettle();
        expect(find.byType(IdeasListScreen), findsNothing);
        expect(src.calls, 0);
      },
    );

    testWidgets(
      '18 and over: See ideas in the drivers sheet opens the list, Back to what moves it',
      (t) async {
        final src = FakeSource([pace, sleep]);
        final a = await routes(older, source: src);
        await pumpIn(
          t,
          Builder(
            builder: (c) => TextButton(
              onPressed: () => a.drivers(c),
              child: const Text('go'),
            ),
          ),
        );
        await t.tap(find.text('go'));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.text('See ideas'), 200);
        await t.pump();
        await t.tap(find.text('See ideas'));
        await t.pumpAndSettle();
        expect(find.byType(IdeasListScreen), findsOneWidget);
        expect(find.byType(IdeaCard), findsNWidgets(2));
        expect(find.bySemanticsLabel('Back to what moves it'), findsOneWidget);
        // Try opens the Experiment on that lever, Back to ideas.
        await t.tap(find.text('Try it with my twin').first);
        await t.pumpAndSettle();
        expect(find.byType(LeverDetailScreen), findsOneWidget);
      },
    );

    testWidgets(
      'the Today card: More ideas in the full card only when allowed',
      (t) async {
        final coach = FakeCoach()..responses.addAll([fourSlots(), fourSlots()]);
        final a = await routes(older, coach: coach);
        await pumpIn(
          t,
          Builder(builder: (c) => SingleChildScrollView(child: a.todayCard(c))),
        );
        await t.pumpAndSettle();
        expect(find.text('More ideas ›'), findsOneWidget);
        final under = await routes({
          ...older,
          'age': 15,
        }, coach: FakeCoach()..responses.add(fourSlots()));
        await pumpIn(
          t,
          Builder(
            builder: (c) => SingleChildScrollView(child: under.todayCard(c)),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('More ideas ›'), findsNothing);
      },
    );
  });

  group('Today card on Home', () {
    testWidgets(
      'stays compact with a full long plan: at most 140 pt tall at 390x844',
      (t) async {
        const long =
            'A very long title that goes on and on about taking a gentle walk around the neighbourhood after dinner';
        final plan = DailyPlan.fromJson({
          ...fourSlotsJson(),
          'items': [
            item('move', 'workout', long, minutes: 10),
            item('eat', 'diet', long, tod: 'evening'),
            item('habit', 'habit', long, tod: 'evening'),
            item('hello', 'encourage', long, tod: 'afternoon'),
          ],
        });
        final coach = FakeCoach()..responses.add(plan);
        final a = await routes(older, coach: coach);
        await pumpIn(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (c) => a.todayCard(
                  c,
                  condensed: true,
                  trailing: const SizedBox(
                    width: 96,
                    height: 48,
                    child: Center(child: Text('Check in')),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(
          t.getSize(find.byType(TodayWithMochiCard)).height,
          lessThanOrEqualTo(140),
        );
        expect(
          find.text('Why?'),
          findsNothing,
          reason: 'the slots live behind the tap',
        );
        expect(
          find.text('More ideas ›'),
          findsNothing,
          reason: 'More ideas lives on the plan screen',
        );
      },
    );

    testWidgets(
      'no outside-AI consent sheet is shown by the card, even with AI configured; a tap asks',
      (t) async {
        const p = AiProvider(
          id: 'muse',
          displayName: 'Muse by Meta',
          configured: true,
          company: 'Meta',
          mayTrainOnContent: true,
        );
        final coach = FakeCoach()..responses.addAll([fourSlots(), fourSlots()]);
        final a = await routes(older, coach: coach, provider: p);
        await pumpIn(
          t,
          Scaffold(
            body: Builder(builder: (c) => a.todayCard(c, condensed: true)),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Personal suggestions?'), findsNothing);
        expect(
          coach.requests,
          hasLength(1),
          reason: 'the plan still loads (templates)',
        );
        await t.tap(find.byType(TodayWithMochiCard));
        await t.pumpAndSettle();
        expect(
          find.text('Personal suggestions?'),
          findsOneWidget,
          reason: 'asked only after the person tapped',
        );
      },
    );
  });
}

Map<String, dynamic> fourSlotsJson() => {
  'schema_version': '1.0',
  'status': 'ok',
  'revision_id': 'r1',
  'local_date': '2026-10-24',
  'based_on': null,
  'inputs': {'snapshot_id': 's1'},
  'plan_type': 'personal',
  'changes': [],
  'trace': [],
};
