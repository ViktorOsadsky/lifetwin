// Ideas for you, creative (design set I2): kind -> pose, the hero, Another idea, Not for me, and every way in.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/checkin/checkin_client.dart';
import 'package:lifesim/checkin/checkin_models.dart' show QuickPlan;
import 'package:lifesim/checkin/consents.dart';
import 'package:lifesim/experiment/idea_kind.dart';
import 'package:lifesim/experiment/ideas_hub.dart';
import 'package:lifesim/experiment/ideas_list_screen.dart';
import 'package:lifesim/experiment/idea_detail_screen.dart';
import 'package:lifesim/experiment/recommendations.dart';
import 'package:lifesim/experiment/side_by_side_screen.dart';
import 'package:lifesim/experiment/widgets/idea_hero.dart';
import 'package:lifesim/experiment/widgets/idea_scene.dart';
import 'package:lifesim/experiment/widgets/ideas_turn_cards.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/twin/twin_experiment.dart' show LeverId;
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/twin_sprite.dart' show TwinSprite;
import 'package:lifesim/ui/widgets/widgets.dart' show TwinStateSprite;
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/wellness/home_panel.dart' show showHealthScoreSheet;
import 'package:lifesim/wellness/models.dart';
import 'package:lifesim/wellness/today_card.dart' show TodayWithMochiCard;

import '../checkin/readback_flow_test.dart' show ContractGuide;
import '../checkin_controller_test.dart' show FakeCheckinGuide;
import '../support/app_fonts.dart';
import '../wellness/coach_test.dart' show FakeCoach;
import 'experiment_screen_test.dart' show older;

Map<String, dynamic> json(
  String id,
  String kind, {
  String title = 'Walk-and-talk',
  Object? effect = 'some',
  String lever = 'moderate_plus_90',
  Object? expLever = 'moderate_recreation_min_week',
  List<Map<String, dynamic>> alternatives = const [],
}) => {
  'id': id,
  'lever': lever,
  'kind': kind,
  'title': title,
  'message': 'Call a friend, then stroll.',
  'based_on': ['moderate_recreation_min_week'],
  'wellness_card': 'activity',
  'source_title': 'CDC: Physical activity for adults',
  'source_url': 'https://www.cdc.gov/physical-activity-basics/guidelines/adults.html',
  'effect': effect,
  'effect_note': 'Modeled difference for people like you, not a promise.',
  'experiment_lever': expLever,
  'experiment_target': 120,
  'why_short': id == 'social_walk' ? 'Call a friend while you stroll.' : 'A line for $title.',
  'source_domain': 'cdc.gov',
  'causal_interpretation': false,
  'alternatives': alternatives,
};

/// The sample from the board: featured Walk-and-talk with three alternatives, and two more ideas.
Map<String, dynamic> body({String? featured = 'social_walk', bool alts = true}) => {
  'status': 'ok',
  'featured': featured,
  'recommendations': [
    json(
      'social_walk',
      'social',
      alternatives: alts
          ? [
              json('kettle_dance', 'dance', title: 'Kettle dance'),
              json(
                'pace',
                'walk',
                title: 'Pick up the pace',
                lever: 'vigorous_plus_60',
                expLever: 'vigorous_recreation_min_week',
              ),
              json('chair_stands', 'stretch', title: 'Chair stands', effect: null, expLever: null),
            ]
          : const [],
    ),
    json(
      'sit_ad_breaks',
      'stand',
      title: 'Ad-break stand',
      effect: 'small',
      lever: 'sitting_minus_60',
      expLever: 'sedentary_min_day',
    ),
    json(
      'calm_bed',
      'sleep',
      title: 'A calm bedtime',
      effect: 'small',
      lever: 'sleep_plus_1h',
      expLever: 'sleep_hours',
    ),
  ],
};

class FakeIdeas implements RecommendationsSource, FullIdeasSource {
  FakeIdeas([Map<String, dynamic>? b]) : result = b ?? body();
  Object result;
  int calls = 0;
  final excluded = <List<String>>[];
  @override
  Future<List<Recommendation>> load() async => (await fetch()).recommendations;
  @override
  Future<IdeasResponse> fetch({List<String> excludedIds = const []}) async {
    calls++;
    excluded.add(excludedIds);
    final r = result;
    if (r is Exception) throw r;
    return IdeasResponse.fromJson(Map<String, dynamic>.from(r as Map));
  }
}

class FakeCaps implements CapabilitiesClient {
  FakeCaps(this.provider);
  final AiProvider? provider;
  @override
  Future<AiProvider?> personalize() async => provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  final voiceController = VoiceOnboardingController(
    guide: FakeConversationGuide(),
    input: FakeSpeechInput(),
    output: FakeSpeechOutput(),
  );
  final day = DateTime(2026, 10, 26, 9);
  Future<TwinRepository> repo([Map<String, dynamic> p = older]) async {
    final r = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => day);
    await r.saveConversationProfile(p);
    return r;
  }

  final shot = GlobalKey();
  final shotsDir = Platform.environment['SHOTS'];
  Future<void> evidence(WidgetTester t, String name) async {
    if (shotsDir == null) return;
    Directory(shotsDir).createSync(recursive: true);
    // Widget tests do not decode images by themselves: load the ones on screen first.
    await t.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        try {
          await precacheImage((e.widget as Image).image, e);
        } catch (_) {}
      }
    });
    await t.pump();
    await t.runAsync(() async {
      final b = shot.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage();
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$shotsDir/ideas2_$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  Future<void> pumpIn(
    WidgetTester t,
    Widget home, {
    double scale = 1,
    Size size = const Size(390, 844),
    IdeasAccess? scope,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          theme: lifeTwinTheme(),
          builder: (c, child) => IdeasScope(
            access: scope,
            child: MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: home,
        ),
      ),
    );
    await t.pump();
    await t.pump();
  }

  IdeasHub hubFor(FakeIdeas src, {TwinRepository? r, bool Function()? allowed}) =>
      IdeasHub(source: src, repo: r, now: () => day, allowed: allowed ?? () => true);

  Widget list(IdeasHub hub, {AiProvider? worded, void Function(Recommendation)? onTry}) => IdeasListScreen(
    hub: hub,
    appearance: const TwinAppearance(),
    origin: 'Today',
    worded: worded,
    onBack: () {},
    onTry: onTry ?? (_) {},
  );

  const note = 'Modeled difference for people like you, not a promise.';

  group('the contract', () {
    test('kind, alternatives and featured are parsed; coping tips keep effect null', () {
      final res = IdeasResponse.fromJson(body());
      expect(res.featuredId, 'social_walk');
      final first = res.recommendations.first;
      expect(first.kind, 'social');
      expect(first.lever, 'moderate_plus_90');
      expect(first.alternatives.map((a) => a.id), ['kettle_dance', 'pace', 'chair_stands']);
      expect(first.alternatives.map((a) => a.kind), ['dance', 'walk', 'stretch']);
      expect(first.alternatives.last.effect, isNull);
      expect(first.alternatives[1].leverId, LeverId.vigorous);
      expect(IdeasResponse.fromJson(body(featured: null)).featuredId, isNull);
    });

    test('a server that sends neither kind, alternatives nor featured still parses', () {
      final j = json('x', 'walk')
        ..remove('kind')
        ..remove('alternatives');
      final res = IdeasResponse.fromJson({
        'recommendations': [j],
      });
      expect(res.featuredId, isNull);
      expect(res.recommendations.single.kind, isNull);
      expect(res.recommendations.single.alternatives, isEmpty);
    });

    test('the request carries local_date, and excluded_ids only when something is hidden', () async {
      final r = await repo();
      expect(recommendationsRequestBody(r, localDate: '2026-10-26').containsKey('excluded_ids'), isFalse);
      final b = recommendationsRequestBody(r, localDate: '2026-10-26', excludedIds: ['a', 'b']);
      expect(b['local_date'], '2026-10-26');
      expect(b['excluded_ids'], ['a', 'b']);
      expect(jsonEncode(b), isNot(contains('"featured"')));
    });

    test('the kind picks the pose, with a stand fallback', () {
      expect(ideaPose('walk'), TwinPose.walkSide);
      expect(ideaPose('social'), TwinPose.walkSide);
      expect(ideaPose('dance'), TwinPose.jump);
      expect(ideaPose('stand'), TwinPose.stand);
      expect(ideaPose('stretch'), TwinPose.stretch);
      expect(ideaPose('sleep'), TwinPose.sleepy);
      expect(ideaPose('eat'), TwinPose.eat);
      expect(ideaPose('breath'), TwinPose.sit);
      expect(ideaPose('craving'), TwinPose.think);
      expect(ideaPose('teleport'), TwinPose.stand);
      expect(ideaPose(null), TwinPose.stand);
      expect(ideaProps('social'), hasLength(2));
      expect(ideaProps('teleport'), isEmpty);
    });
  });

  group('the hero', () {
    TwinPose? heroPose(WidgetTester t) => t.widgetList<TwinStateSprite>(find.byType(TwinStateSprite)).first.pose;

    testWidgets('shows today\'s idea with the pose for its kind, the server\'s words and the effect word', (t) async {
      await pumpIn(t, list(hubFor(FakeIdeas())));
      await t.pumpAndSettle();
      expect(find.text('Today’s idea'), findsWidgets);
      expect(find.text('Walk-and-talk'), findsOneWidget);
      expect(find.text('Call a friend while you stroll.'), findsOneWidget);
      expect(find.text('Some'), findsOneWidget);
      expect(heroPose(t), TwinPose.walkSide);
      expect(find.text('Idea 1 of 4'), findsOneWidget);
      expect(find.text('Try it with my twin'), findsWidgets);
      // The other recommendations sit below as cards.
      expect(find.text('More ideas'), findsOneWidget);
      expect(find.text('Ad-break stand'), findsOneWidget);
      await evidence(t, 'list');
    });

    testWidgets('an unknown kind stands; a null effect shows the Guideline chip, not a meter', (t) async {
      final b = {
        'status': 'ok',
        'featured': 'x',
        'recommendations': [json('x', 'teleport', title: 'Coping tip', effect: null, expLever: null)],
      };
      await pumpIn(t, list(hubFor(FakeIdeas(b))));
      await t.pumpAndSettle();
      expect(heroPose(t), TwinPose.stand);
      expect(find.text('Guideline'), findsOneWidget);
      expect(find.text('Some'), findsNothing);
      expect(find.text('Another idea'), findsNothing, reason: 'no alternatives: no pager and no Another idea');
      expect(find.textContaining('Idea 1 of'), findsNothing);
      expect(find.text('Not for me'), findsOneWidget);
    });

    testWidgets('props are decorative: small, no border or shadow, not announced', (t) async {
      await pumpIn(t, list(hubFor(FakeIdeas())));
      await t.pumpAndSettle();
      final props = find.byType(IdeaProp);
      expect(props, findsNWidgets(2));
      for (final e in props.evaluate()) {
        final size = t.getSize(find.byWidget(e.widget));
        expect(size.width, lessThanOrEqualTo(40));
        final box = t.widget<Container>(
          find.descendant(of: find.byWidget(e.widget), matching: find.byType(Container)).first,
        );
        final deco = box.decoration! as BoxDecoration;
        expect(deco.border, isNull);
        expect(deco.boxShadow, isNull);
      }
      expect(find.descendant(of: props.first, matching: find.byType(ExcludeSemantics)), findsWidgets);
    });

    testWidgets('Another idea steps through the featured idea and its alternatives, then the end card', (t) async {
      await pumpIn(t, list(hubFor(FakeIdeas())));
      await t.pumpAndSettle();
      final titles = ['Walk-and-talk', 'Kettle dance', 'Pick up the pace', 'Chair stands'];
      final poses = [TwinPose.walkSide, TwinPose.jump, TwinPose.walkSide, TwinPose.stretch];
      for (var i = 0; i < 4; i++) {
        expect(find.text('Idea ${i + 1} of 4'), findsOneWidget);
        expect(find.text(titles[i]), findsOneWidget);
        expect(heroPose(t), poses[i]);
        if (i < 3) {
          await t.tap(find.text('Another idea'));
          await t.pumpAndSettle();
        }
      }
      // Chair stands has no effect of its own: the Guideline chip, never the parent's word.
      expect(find.text('Guideline'), findsOneWidget);
      expect(find.text('Some'), findsNothing);
      await t.tap(find.text('Another idea'));
      await t.pumpAndSettle();
      expect(find.text('That’s all for today'), findsOneWidget);
      expect(find.textContaining('tomorrow'), findsNothing);
      await t.tap(find.text('Back to the first'));
      await t.pumpAndSettle();
      expect(find.text('Idea 1 of 4'), findsOneWidget);
    });

    testWidgets('Not for me hides it, persists the id for the day, sends excluded_ids, and Undo restores it', (
      t,
    ) async {
      final r = await repo();
      final src = FakeIdeas();
      final hub = hubFor(src, r: r);
      await pumpIn(t, list(hub));
      await t.pumpAndSettle();
      await t.tap(find.text('Not for me'));
      await t.pumpAndSettle();
      expect(find.text('Walk-and-talk'), findsNothing, reason: 'the next card is in');
      expect(find.text('Kettle dance'), findsOneWidget);
      expect(find.text('Idea 1 of 3'), findsOneWidget);
      expect(find.text('Hidden. Mochi will skip it.'), findsOneWidget);
      expect(hub.hidden, ['social_walk']);
      // Persisted on the phone for today; a fresh hub (a new app run) still skips it.
      expect(r.ideasState['hidden_ids'], ['social_walk']);
      final again = hubFor(FakeIdeas(), r: r);
      expect(again.hidden, ['social_walk']);
      expect(again.deck.map((i) => i.id), ['kettle_dance', 'pace', 'chair_stands']);
      // The next request carries it.
      await hub.refresh();
      expect(src.excluded.last, ['social_walk']);
      await evidence(t, 'not_for_me');
      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();
      expect(hub.hidden, isEmpty);
      expect(r.ideasState['hidden_ids'], isEmpty);
      expect(find.text('Walk-and-talk'), findsOneWidget);
    });

    testWidgets('hidden ideas are for today only', (t) async {
      final r = await repo();
      final hub = hubFor(FakeIdeas(), r: r);
      await hub.hide('social_walk');
      var later = day.add(const Duration(days: 1));
      final tomorrow = IdeasHub(source: FakeIdeas(), repo: r, now: () => later, allowed: () => true);
      expect(tomorrow.hidden, isEmpty);
      later = day;
    });

    testWidgets('the effect caveat is visible on the first screen at 1.0x and 1.6x', (t) async {
      for (final scale in [1.0, 1.6]) {
        await pumpIn(t, list(hubFor(FakeIdeas())), scale: scale);
        await t.pumpAndSettle();
        final line = find.text(note);
        expect(line, findsOneWidget, reason: '$scale');
        expect(t.getRect(line).bottom, lessThan(844), reason: 'on the first screen at $scale');
        expect(find.text('Linked, not proven.'), findsOneWidget);
        if (scale > 1) await evidence(t, 'list_large');
      }
    });

    testWidgets('featured null: no hero, the list is set I', (t) async {
      await pumpIn(t, list(hubFor(FakeIdeas(body(featured: null)))));
      await t.pumpAndSettle();
      expect(find.byType(IdeaHero), findsNothing);
      expect(find.text('Try it with my twin'), findsNWidgets(3));
    });

    testWidgets('VoiceOver: one merged hero element, with Another idea and Not for me as custom actions and buttons', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await pumpIn(t, list(hubFor(FakeIdeas())));
      await t.pumpAndSettle();
      final merged = find.bySemanticsLabel(
        RegExp('Today’s idea: Walk-and-talk. Call a friend while you stroll. Modeled effect: some. Idea 1 of 4.'),
      );
      expect(merged, findsOneWidget);
      final data = t.getSemantics(merged).getSemanticsData();
      final actions = data.customSemanticsActionIds!.map((id) => CustomSemanticsAction.getAction(id)!.label);
      expect(actions, containsAll(['Another idea', 'Not for me']));
      expect(find.bySemanticsLabel('Not for me'), findsOneWidget);
      expect(find.bySemanticsLabel('Another idea'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the training line shows only when the provider may train', (t) async {
      const off = AiProvider(id: 'claude', displayName: 'Claude by Anthropic', configured: true, company: 'Anthropic');
      const on = AiProvider(
        id: 'muse',
        displayName: 'Muse by Meta',
        configured: true,
        company: 'Meta',
        mayTrainOnContent: true,
      );
      await pumpIn(t, list(hubFor(FakeIdeas()), worded: off));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.textContaining('Worded with'), 200);
      expect(find.text('Worded with Claude by Anthropic.'), findsOneWidget);
      expect(find.textContaining('may use what you share'), findsNothing);
      await pumpIn(t, list(hubFor(FakeIdeas()), worded: on));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.textContaining('Worded with'), 200);
      expect(find.text('Worded with Muse by Meta. Meta may use what you share to improve its AI.'), findsOneWidget);
    });

    testWidgets('Try it with my twin opens the lever of the idea on show', (t) async {
      final tried = <String?>[];
      await pumpIn(t, list(hubFor(FakeIdeas()), onTry: (i) => tried.add(i.leverId)));
      await t.pumpAndSettle();
      await t.tap(find.text('Another idea'));
      await t.pumpAndSettle();
      await t.tap(find.text('Another idea'));
      await t.pumpAndSettle();
      await t.tap(find.text('Try it with my twin').first);
      expect(tried, [LeverId.vigorous]);
    });
  });

  group('the detail', () {
    testWidgets('Mochi\'s scene and a short bubble, then the rest of the detail', (t) async {
      final idea = IdeasResponse.fromJson(body()).recommendations.first;
      await pumpIn(
        t,
        IdeaDetailScreen(
          idea: idea,
          appearance: const TwinAppearance(),
          onBack: () {},
          backLabel: 'Back',
          onTry: () {},
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(IdeaScene), findsOneWidget);
      expect(find.text('Call a friend, then stroll.'), findsOneWidget, reason: 'the server\'s line, as is');
      expect(find.text('Walk-and-talk'), findsOneWidget);
      expect(find.text('Try it with my twin'), findsOneWidget);
      expect(t.widgetList<TwinStateSprite>(find.byType(TwinStateSprite)).first.pose, TwinPose.walkSide);
      await evidence(t, 'detail');
    });
  });

  group('the ways in', () {
    Future<AgenticRoutes> routes(Map<String, dynamic> p, {FakeIdeas? src, AiProvider? provider}) async {
      final r = await repo(p);
      final a = AgenticRoutes(
        look: ValueNotifier(const TwinAppearance(name: 'Mochi')),
        api: ApiBase(),
        voice: () => voiceController,
        coach: FakeCoach(),
        capabilities: FakeCaps(provider),
        ideasSource: (_) => src ?? FakeIdeas(),
      );
      a.attach(r);
      return a;
    }

    Future<void> pumpHome(WidgetTester t, AgenticRoutes a, {Size size = const Size(390, 844), double top = 0}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      t.view.padding = FakeViewPadding(top: top);
      t.view.viewPadding = FakeViewPadding(top: top);
      addTearDown(t.view.reset);
      await t.pumpWidget(
        RepaintBoundary(
          key: shot,
          child: LifeTwinApp(
            controller: VoiceOnboardingController(
              guide: FakeConversationGuide(),
              input: FakeSpeechInput(),
              output: FakeSpeechOutput(),
            ),
            twin: Future.value(a.repo),
            agentic: a,
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    bool scrolls(WidgetTester t) => [
      for (final e in find.descendant(of: find.byType(RoomScreen), matching: find.byType(Scrollable)).evaluate())
        if ((e as StatefulElement).state is ScrollableState &&
            ((e.state as ScrollableState).position.maxScrollExtent > 0.5))
          true,
    ].isNotEmpty;

    for (final (size, top) in [(const Size(390, 844), 0.0), (const Size(402, 874), 62.0)]) {
      testWidgets('(a) Home: Today\'s idea line opens the idea, Home does not scroll, Mochi is not covered ($size)', (
        t,
      ) async {
        final a = await routes(older);
        await pumpHome(t, a, size: size, top: top);
        final line = find.descendant(
          of: find.byType(TodayWithMochiCard),
          matching: find.textContaining('Today’s idea: ', findRichText: true),
        );
        expect(line, findsOneWidget);
        expect(find.textContaining('Walk-and-talk', findRichText: true), findsWidgets);
        expect(scrolls(t), isFalse, reason: 'Home must not scroll');
        final lineRect = t.getRect(line);
        final twin = t.getRect(find.byKey(const ValueKey('room-twin')));
        expect(lineRect.overlaps(twin.deflate(twin.shortestSide * 0.2)), isFalse, reason: 'not over Mochi');
        expect(lineRect.height, lessThan(60));
        await evidence(t, size.width == 390 ? 'home' : 'home_402');
        await t.tap(line);
        await t.pumpAndSettle();
        expect(find.byType(IdeaDetailScreen), findsOneWidget);
        expect(find.text('Walk-and-talk'), findsWidgets);
      });
    }

    testWidgets('(a) hidden under 18, and with featured null', (t) async {
      final under = await routes({...older, 'age': 16});
      await pumpHome(t, under);
      expect(find.textContaining('Today’s idea: ', findRichText: true), findsNothing);
      expect(find.text('Walk-and-talk', findRichText: true), findsNothing);
      final none = await routes(older, src: FakeIdeas(body(featured: null)));
      await pumpHome(t, none);
      expect(find.textContaining('Today’s idea: ', findRichText: true), findsNothing);
    });

    Rect twinBody(WidgetTester t) {
      final twin = t.getRect(find.byType(TwinSprite).first);
      return Rect.fromCenter(center: twin.center, width: twin.width * 0.5, height: twin.height * 0.7);
    }

    for (final (size, top) in [(const Size(390, 844), 0.0), (const Size(402, 874), 62.0)]) {
      testWidgets('(b) no automatic bubble beside the Today line; a tap shows it clear of Mochi and the pill ($size)', (
        t,
      ) async {
        final a = await routes(older);
        await pumpHome(t, a, size: size, top: top);
        // The Today card's idea line is the daily cue: no bubble by itself, and the day is not "used up".
        expect(find.byKey(const ValueKey('room-idea-bubble')), findsNothing);
        expect(find.text('See ideas ›'), findsNothing);
        expect(a.ideasHub.bubbleDue, isTrue);
        // A tap on Mochi shows it.
        await t.tap(find.byKey(const ValueKey('room-twin')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        final bubble = find.byKey(const ValueKey('room-idea-bubble'));
        expect(bubble, findsOneWidget);
        expect(find.text('See ideas ›'), findsOneWidget);
        final rect = t.getRect(bubble);
        expect(rect.overlaps(twinBody(t)), isFalse, reason: 'covers Mochi: $rect vs ${twinBody(t)}');
        expect(
          rect.overlaps(t.getRect(find.byKey(const ValueKey('room-twin')))),
          isFalse,
          reason: 'covers the twin box',
        );
        expect(
          rect.overlaps(t.getRect(find.byKey(const ValueKey('room-activity')))),
          isFalse,
          reason: 'covers the pill',
        );
        expect(rect.height, lessThan(80), reason: 'compact');
        await evidence(t, size.width == 390 ? 'bubble_390' : 'bubble');
        // It hides itself after 6 seconds.
        await t.pump(const Duration(seconds: 6));
        await t.pump(const Duration(milliseconds: 50));
        expect(bubble, findsNothing);
      });
    }

    testWidgets('(b) the bubble opens the list from See ideas, and Close dismisses it', (t) async {
      final a = await routes(older);
      await pumpHome(t, a);
      await t.tap(find.byKey(const ValueKey('room-twin')));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byTooltip('Close'));
      await t.pump();
      expect(find.text('See ideas ›'), findsNothing);
      await t.tap(find.byKey(const ValueKey('room-twin')));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('See ideas ›'));
      await t.pumpAndSettle();
      expect(find.byType(IdeasListScreen), findsOneWidget);
      expect(find.bySemanticsLabel('Back to room'), findsOneWidget);
    });

    testWidgets('(b) with Reduce Motion the bubble has no timer and stays until closed', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final a = await routes(older);
      await pumpHome(t, a);
      await t.tap(find.byKey(const ValueKey('room-twin')));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('See ideas ›'), findsOneWidget);
      await t.pump(const Duration(seconds: 20));
      expect(find.text('See ideas ›'), findsOneWidget);
      await t.tap(find.byTooltip('Close'));
      await t.pump();
      expect(find.text('See ideas ›'), findsNothing);
    });

    testWidgets('(b) without the Today card the daily bubble shows by itself, once', (t) async {
      final a = await routes(older);
      await a.ideasHub.ensureToday();
      final look = ValueNotifier(const TwinAppearance(name: 'Mochi'));
      addTearDown(look.dispose);
      Widget room() => RoomScreen(
        appearance: look,
        hasProfile: true,
        onTalk: () {},
        onCustomize: () {},
        onFortune: () async {},
        ideas: a.ideasAccess,
      );
      await pumpIn(t, room());
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('See ideas ›'), findsOneWidget);
      expect(a.ideasHub.bubbleDue, isFalse);
      await t.pump(const Duration(seconds: 7));
      expect(find.text('See ideas ›'), findsNothing);
    });

    testWidgets('(b) a new run on the same day does not show the bubble by itself again', (t) async {
      final r = await repo();
      final first = hubFor(FakeIdeas(), r: r);
      await first.ensureToday();
      expect(first.bubbleDue, isTrue);
      await first.markBubbleShown();
      expect(hubFor(FakeIdeas(), r: r).bubbleDue, isFalse);
      final tomorrow = IdeasHub(
        source: FakeIdeas(),
        repo: r,
        now: () => day.add(const Duration(days: 1)),
        allowed: () => true,
      );
      expect(tomorrow.bubbleDue, isTrue);
    });

    testWidgets('(b) the bubble is not for under 18, and at 1.5x text Mochi opens the list directly', (t) async {
      final under = await routes({...older, 'age': 16});
      await pumpHome(t, under);
      await t.tap(find.byKey(const ValueKey('room-twin')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('See ideas ›'), findsNothing);
      final a = await routes(older);
      await a.ideasHub.ensureToday();
      final look = ValueNotifier(const TwinAppearance(name: 'Mochi'));
      addTearDown(look.dispose);
      await pumpIn(
        t,
        RoomScreen(
          appearance: look,
          hasProfile: true,
          onTalk: () {},
          onCustomize: () {},
          onFortune: () async {},
          ideas: a.ideasAccess,
        ),
        scale: 1.5,
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('See ideas ›'), findsNothing, reason: 'no automatic bubble at large text');
      await t.tap(find.byKey(const ValueKey('room-twin')));
      await t.pumpAndSettle();
      expect(find.byType(IdeasListScreen), findsOneWidget);
    });

    group('(c) after the daily check-in', () {
      late TwinRepository r;
      late IdeasAccess access;
      Future<void> finishCheckIn(WidgetTester t, {required bool care}) async {
        r = await repo({
          'age': 55,
          'sex': 'male',
          'height_cm': 175.0,
          'weight_kg': 80.0,
          'sleep_hours': 7,
          'smoking_status': 'never',
          'diabetes': false,
          'hypertension_diagnosed': false,
          'general_health': 3,
          'vigorous_recreation_min_week': 30,
          'moderate_recreation_min_week': 90,
          'sedentary_min_day': 360,
        });
        final hub = hubFor(FakeIdeas(), r: r);
        await hub.ensureToday();
        final opened = <String>[];
        access = IdeasAccess(
          hub: hub,
          openIdea: (c, i) => opened.add(i.id),
          openList: (c, {required origin, levers}) {},
        );
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final look = ValueNotifier(const TwinAppearance(name: 'Mochi'));
        addTearDown(look.dispose);
        await t.pumpWidget(
          MaterialApp(
            theme: lifeTwinTheme(),
            builder: (context, child) => CheckInScope(
              repository: r,
              guide: care ? CareGuide(ContractGuide()) : ContractGuide(),
              speechInput: FakeSpeechInput(),
              speechOutput: FakeSpeechOutput(),
              appearance: look,
              now: () => DateTime(2026, 10, 24, 9),
              ideas: () => access,
              child: child!,
            ),
            home: RoomScreen(
              appearance: look,
              hasProfile: true,
              onTalk: () {},
              onCustomize: () {},
              onFortune: () async {},
            ),
          ),
        );
        await t.pump();
        await t.tap(find.text('Check in'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), '7 hours');
        await t.testTextInput.receiveAction(TextInputAction.send);
        await t.pumpAndSettle();
        await t.tap(find.text('About 6 hours'));
        await t.pumpAndSettle();
        await t.tap(find.text('Looks right'));
        await t.pumpAndSettle();
      }

      testWidgets('Done shows "Mochi has an idea for today" and it opens the idea', (t) async {
        await finishCheckIn(t, care: false);
        expect(find.text('Back to my room'), findsOneWidget);
        expect(find.text('Mochi has an idea for today'), findsOneWidget);
        expect(find.text('Walk-and-talk'), findsOneWidget);
        await t.tap(find.text('Walk-and-talk'));
        await t.pump();
      });

      testWidgets('hidden once the care line was shown', (t) async {
        await finishCheckIn(t, care: true);
        expect(find.text('Back to my room'), findsOneWidget);
        expect(find.text('Mochi has an idea for today'), findsNothing);
      });
    });

    testWidgets('(d) the Experiment result: "More ideas like this" for the levers that moved, hidden when none match', (
      t,
    ) async {
      final a = await routes(older);
      await a.ideasHub.ensureToday();
      final r = a.repo!;
      Future<void> open(IdeasAccess? access, String lever) async {
        final exp = r.experiment()!..set(lever, lever == LeverId.moderate ? 150 : 1);
        await pumpIn(
          t,
          SideBySideScreen(repository: r, whatIf: exp, appearance: const TwinAppearance(), ideas: access),
        );
        await t.pumpAndSettle();
      }

      await open(a.ideasAccess, LeverId.moderate);
      expect(find.text('More ideas like this ›'), findsOneWidget);
      await open(a.ideasAccess, LeverId.smoking);
      expect(find.text('More ideas like this ›'), findsNothing, reason: 'no idea for smoking today');
      await open(null, LeverId.moderate);
      expect(find.text('More ideas like this ›'), findsNothing);
    });

    testWidgets('(d) "More ideas like this" opens the list filtered to those levers', (t) async {
      final a = await routes(older);
      await pumpIn(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () => a.ideas(c, origin: 'result', levers: {LeverId.sleepHours}),
            child: const Text('go'),
          ),
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('A calm bedtime'), findsOneWidget);
      expect(find.text('Ad-break stand'), findsNothing);
      expect(find.text('Walk-and-talk'), findsNothing);
    });

    testWidgets('(e) the score sheet has "Ideas linked to a healthier score"; hidden without ideas', (t) async {
      final a = await routes(older);
      await a.ideasHub.ensureToday();
      const snap = WellnessSnapshot();
      Future<void> pumpSheet(IdeasAccess? access) async {
        await t.pumpWidget(const SizedBox());
        await pumpIn(
          t,
          Builder(
            builder: (c) => TextButton(onPressed: () => showHealthScoreSheet(c, snap), child: const Text('go')),
          ),
          scope: access,
        );
        await t.tap(find.text('go'));
        await t.pumpAndSettle();
      }

      await pumpSheet(a.ideasAccess);
      expect(find.text('Ideas linked to a healthier score'), findsOneWidget);
      await t.tap(find.text('Ideas linked to a healthier score'));
      await t.pumpAndSettle();
      expect(find.byType(IdeasListScreen), findsOneWidget);
      await pumpSheet(null);
      expect(find.text('Ideas linked to a healthier score'), findsNothing);
      final empty = await routes(
        older,
        src: FakeIdeas({'status': 'not_enough_information', 'recommendations': <dynamic>[]}),
      );
      await empty.ideasHub.ensureToday();
      await pumpSheet(empty.ideasAccess);
      expect(find.text('Ideas linked to a healthier score'), findsNothing);
    });

    testWidgets('(f) the end of onboarding: Mochi\'s first ideas, one or two, with the caveat; under 18 none', (
      t,
    ) async {
      final a = await routes(older);
      final recs = IdeasResponse.fromJson(body()).recommendations;
      await pumpIn(
        t,
        Material(
          child: SingleChildScrollView(
            child: IdeasClosingCard(access: a.ideasAccess!, appearance: const TwinAppearance(), ideas: recs),
          ),
        ),
      );
      expect(find.text('Mochi’s first ideas for you'), findsOneWidget);
      expect(find.text('Walk-and-talk'), findsOneWidget);
      expect(find.text('Ad-break stand'), findsOneWidget);
      expect(find.text('A calm bedtime'), findsNothing, reason: 'at most two');
      expect(find.text('See all ideas ›'), findsOneWidget);
      expect(find.text(note), findsOneWidget);
      expect(a.ideasHub.featured?.id, 'social_walk', reason: 'kept as today\'s ideas');
      await evidence(t, 'onboarding_close');
      final under = await routes({...older, 'age': 16});
      await pumpIn(
        t,
        Material(
          child: SingleChildScrollView(
            child: IdeasClosingCard(access: under.ideasAccess!, appearance: const TwinAppearance(), ideas: recs),
          ),
        ),
      );
      expect(under.ideasHub.featured, isNull, reason: 'never an entry point under 18');
    });

    testWidgets('(g) open_ideas shows the featured idea and See ideas; no featured idea: Mochi says it needs more', (
      t,
    ) async {
      final a = await routes(older);
      await a.ideasHub.ensureToday();
      await pumpIn(
        t,
        Material(
          child: IdeasOpenCard(access: a.ideasAccess!, appearance: const TwinAppearance()),
        ),
      );
      expect(find.text('Walk-and-talk'), findsOneWidget);
      expect(find.text('See ideas ›'), findsOneWidget);
      final none = await routes(older, src: FakeIdeas(body(featured: null)));
      await pumpIn(
        t,
        Material(
          child: IdeasOpenCard(access: none.ideasAccess!, appearance: const TwinAppearance()),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Walk-and-talk'), findsNothing);
      expect(find.text('I’ll have ideas once I know a bit more.'), findsOneWidget);
    });

    testWidgets('the day\'s answer is cached on the phone and Delete my data clears it', (t) async {
      final a = await routes(older);
      await a.ideasHub.refresh();
      expect(a.repo!.ideasState['response'], isNotNull);
      final fresh = IdeasHub(
        source: FakeIdeas(),
        repo: a.repo,
        now: () => DateTime.parse(a.ideasHub.today),
        allowed: () => true,
      );
      expect(fresh.featured?.id, 'social_walk', reason: 'Home shows it without a second call');
      await a.repo!.deleteMyData();
      expect(a.repo!.ideasState, isEmpty);
    });

    testWidgets('offline: the cached ideas still show, with a connection line', (t) async {
      final src = FakeIdeas();
      final hub = hubFor(src);
      await hub.refresh();
      src.result = const RecommendationsFailure(null);
      await pumpIn(t, list(hub));
      await t.pumpAndSettle();
      expect(find.text('Walk-and-talk'), findsOneWidget);
      expect(find.textContaining('Check your connection'), findsOneWidget);
    });
  });
}

/// Marks every finished turn with the care line, as the server does after a low mood answer.
class CareGuide extends FakeCheckinGuide {
  CareGuide(this.inner);
  final ContractGuide inner;
  @override
  Future<CheckinTurn> start({
    required String kind,
    required String localDate,
    Map<String, dynamic> previous = const {},
    QuickPlan? quick,
  }) async => _mark(await inner.start(kind: kind, localDate: localDate, previous: previous, quick: quick));
  @override
  Future<CheckinTurn> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  }) async => _mark(await inner.turn(action: action, state: state, text: text, fromTranscript: fromTranscript));
  CheckinTurn _mark(CheckinTurn t) => CheckinTurn({
    ...t.raw,
    'state': {...t.state, 'care_line_shown': true},
  });
}
