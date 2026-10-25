// The collapsible health score card on Home: collapse/expand, the chip, the kept state, the room window.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show HealthScoreStatus, TwinModelService;
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/wellness/home_panel.dart';
import 'package:lifesim/wellness/models.dart';
import 'package:lifesim/wellness/widgets.dart' show WellnessCard;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';
import 'support/settings_hub.dart';

const _profile = {
  'age': 55,
  'sex': 'male',
  'height_cm': 175.0,
  'weight_kg': 80.0,
  'sleep_hours': 5,
  'smoking_status': 'current',
  'diabetes': false,
  'hypertension_diagnosed': false,
  'general_health': 3,
  'vigorous_recreation_min_week': 0,
  'moderate_recreation_min_week': 20,
  'sedentary_min_day': 600,
};

WellnessSnapshot _snap({HealthScoreStatus status = HealthScoreStatus.available, double score = 0.53}) =>
    WellnessSnapshot(healthScore: score, status: status, ageGroupPercentile: 70);

Finder _semantic(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpCard(
    WidgetTester t,
    WellnessSnapshot snap, {
    double width = 390,
    double scale = 1,
    bool disableAnimations = false,
    Key? key,
  }) async {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 844),
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: CollapsibleHealthScore(key: key, snapshot: snap, onEstimate: () {}, onDrivers: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('collapse with the chevron, then expand with the chip', (t) async {
    await pumpCard(t, _snap());
    expect(find.byType(HomeWellnessPanel), findsOneWidget);
    expect(find.text('Health score'), findsOneWidget);
    final button = find.byTooltip('Collapse health score');
    expect(t.getSize(button).width, greaterThanOrEqualTo(48));
    expect(t.getSize(button).height, greaterThanOrEqualTo(48));
    await t.tap(button);
    await settle(t);
    expect(find.byType(HomeWellnessPanel), findsNothing);
    expect(find.text('+0.53'), findsOneWidget);
    expect(find.text('Healthier than', findRichText: true, skipOffstage: false), findsNothing);
    await t.tap(find.text('+0.53'));
    await settle(t);
    expect(find.byType(HomeWellnessPanel), findsOneWidget);
    expect(find.text('Health score'), findsOneWidget);
  });

  testWidgets('a swipe up on the card collapses it', (t) async {
    await pumpCard(t, _snap());
    await t.fling(find.byType(HomeWellnessPanel), const Offset(0, -150), 1000);
    await settle(t);
    expect(find.byType(HomeWellnessPanel), findsNothing);
    expect(find.text('+0.53'), findsOneWidget);
  });

  testWidgets('the collapsed chip: formatted score, semantics label, 48 pt, no rough mark when not rough', (t) async {
    await pumpCard(t, _snap());
    await t.tap(find.byTooltip('Collapse health score'));
    await settle(t);
    expect(find.text('+0.53'), findsOneWidget);
    expect(_semantic('Health score plus 0.53, collapsed. Tap to expand.'), findsOneWidget);
    expect(
      t.getSize(find.ancestor(of: find.text('+0.53'), matching: find.byType(InkWell)).first).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.text('Rough guide'), findsNothing);
  });

  testWidgets('a negative score is spoken with "minus"', (t) async {
    await pumpCard(t, _snap(score: -0.4));
    await t.tap(find.byTooltip('Collapse health score'));
    await settle(t);
    expect(find.text('−0.40'), findsOneWidget);
    expect(_semantic('Health score minus 0.40, collapsed. Tap to expand.'), findsOneWidget);
  });

  testWidgets('a rough status shows the Rough guide mark on the chip', (t) async {
    await pumpCard(t, _snap(status: HealthScoreStatus.extrapolated));
    await t.tap(find.byTooltip('Collapse health score'));
    await settle(t);
    expect(find.text('+0.53'), findsOneWidget);
    expect(find.text('Rough guide'), findsOneWidget);
  });

  testWidgets('first launch starts expanded; the state persists across a rebuild', (t) async {
    await pumpCard(t, _snap(), key: const ValueKey('a'));
    expect(find.byType(HomeWellnessPanel), findsOneWidget, reason: 'nothing stored: expanded');
    await t.tap(find.byTooltip('Collapse health score'));
    await settle(t);
    await t.pumpWidget(const SizedBox());
    await pumpCard(t, _snap(), key: const ValueKey('b'));
    await settle(t);
    expect(find.byType(HomeWellnessPanel), findsNothing, reason: 'restored collapsed');
    expect(find.text('+0.53'), findsOneWidget);
    await t.tap(find.text('+0.53'));
    await settle(t);
    await t.pumpWidget(const SizedBox());
    await pumpCard(t, _snap(), key: const ValueKey('c'));
    await settle(t);
    expect(find.byType(HomeWellnessPanel), findsOneWidget, reason: 'restored expanded');
  });

  testWidgets('a stored collapsed state is restored without a visible animation', (t) async {
    SharedPreferences.setMockInitialValues({CollapsibleHealthScore.prefsKey: true});
    await pumpCard(t, _snap());
    await t.pump();
    expect(find.byType(HomeWellnessPanel), findsNothing);
    expect(find.text('+0.53'), findsOneWidget);
  });

  testWidgets('reduced motion switches instantly', (t) async {
    await pumpCard(t, _snap(), disableAnimations: true);
    await t.tap(find.byTooltip('Collapse health score'));
    await t.pump();
    await t.pump();
    expect(find.byType(HomeWellnessPanel), findsNothing);
    expect(find.text('+0.53'), findsOneWidget);
  });

  testWidgets('under 18: no card and no chip', (t) async {
    await pumpCard(t, const WellnessSnapshot(status: HealthScoreStatus.underAge));
    expect(find.byTooltip('Collapse health score'), findsNothing);
    expect(find.text(HomeWellnessPanel.underAgeLine), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
  });

  for (final (w, scale) in [(390.0, 1.6), (320.0, 1.6)]) {
    for (final collapsed in [false, true]) {
      testWidgets('1.6x text at $w wide, ${collapsed ? 'collapsed' : 'expanded'}: no overflow', (t) async {
        await pumpCard(
          t,
          _snap(status: HealthScoreStatus.extrapolated),
          width: w,
          scale: scale,
        );
        if (collapsed) {
          await t.tap(find.byTooltip('Collapse health score'));
          await settle(t);
        }
        expect(t.takeException(), isNull);
        expect(find.text('+0.53'), findsOneWidget);
      });
    }
  }

  // The whole Home.
  final key = GlobalKey();

  Future<void> pumpHome(
    WidgetTester t, {
    double width = 390,
    double height = 844,
    double scale = 1,
    double topInset = 0,
    double bottomInset = 0,
  }) async {
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = await memoryRepo(model);
    await repo.saveConversationProfile(_profile);
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(scale),
            padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
            viewPadding: EdgeInsets.only(top: topInset, bottom: bottomInset),
          ),
          child: LifeTwinApp(
            controller: VoiceOnboardingController(
              guide: FakeConversationGuide(),
              input: FakeSpeechInput(),
              output: FakeSpeechOutput(),
            ),
            twin: Future.value(repo),
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump();
  }

  Future<void> loadArt(WidgetTester t) async {
    await t.runAsync(() async {
      final c = t.element(find.byType(Scaffold).first);
      await precacheImage(const AssetImage('assets/scene/room/room_bg.jpg'), c);
      for (final pose in TwinPose.values) {
        try {
          await precacheImage(AssetImage(twinAsset(TwinType.bear, TwinLook.calHat, pose)), c);
        } catch (_) {}
      }
    });
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    final shots = Directory('${Directory.current.path}/../../evidence_shots')..createSync(recursive: true);
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${shots.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Rect twinBody(WidgetTester t) {
    final twin = t.getRect(find.byType(TwinSprite).first);
    return Rect.fromCenter(center: twin.center, width: twin.width * 0.5, height: twin.height * 0.7);
  }

  Map<String, Rect> covers(WidgetTester t) {
    Rect box(Finder f, Type within) => t.getRect(find.ancestor(of: f.first, matching: find.byType(within)).first);
    return {
      'quiz icon': t.getRect(find.byTooltip('Quiz')),
      'score': t.getRect(find.byType(CollapsibleHealthScore)),
      'check in': box(find.text('Check in'), LipButton),
      'today row': box(find.textContaining('Today', findRichText: true), WellnessCard),
      'experiment': box(find.text('Experiment with your twin'), LipButton),
      'dock': t.getRect(find.text('Talk').first),
    };
  }

  for (final (w, h, top, bottom) in [(390.0, 844.0, 0.0, 0.0), (402.0, 874.0, 62.0, 34.0)]) {
    testWidgets('collapsed at $w x $h (top inset $top): the twin is not covered and the room grows', (t) async {
      await pumpHome(t, width: w, height: h, topInset: top, bottomInset: bottom);
      await loadArt(t);
      expect(find.byType(HomeWellnessPanel), findsOneWidget, reason: 'first launch is expanded');
      final cardBottom = t.getRect(find.byType(CollapsibleHealthScore)).bottom;
      final twinTopBefore = t.getRect(find.byType(TwinSprite).first).top;
      for (final e in covers(t).entries) {
        expect(twinBody(t).overlaps(e.value), isFalse, reason: 'expanded: ${e.key} covers the twin');
      }
      if (h == 874.0) await shot(t, 'score_expanded');

      await t.tap(find.byTooltip('Collapse health score'));
      await loadArt(t);
      expect(find.byType(HomeWellnessPanel), findsNothing);
      expect(t.takeException(), isNull);
      final chip = t.getRect(
        find.text('+0.53').evaluate().isEmpty ? find.byType(CollapsibleHealthScore) : find.text('+0.53'),
      );
      expect(chip.top, greaterThanOrEqualTo(top + 8));
      expect(
        t.getRect(find.byType(CollapsibleHealthScore)).bottom,
        lessThan(cardBottom - 40),
        reason: 'the card shrank',
      );
      for (final e in covers(t).entries) {
        expect(
          twinBody(t).overlaps(e.value),
          isFalse,
          reason: 'collapsed: ${e.key} ${e.value} covers the twin ${twinBody(t)}',
        );
      }
      expect(
        t.getRect(find.byType(TwinSprite).first).top,
        lessThanOrEqualTo(twinTopBefore + 1),
        reason: 'the freed space goes to the room, Mochi does not sink',
      );
      if (h == 874.0) await shot(t, 'score_collapsed');
    });
  }

  testWidgets('Home at 1.6x text: no overflow expanded or collapsed', (t) async {
    await pumpHome(t, scale: 1.6);
    await loadArt(t);
    expect(t.takeException(), isNull);
    await t.tap(find.byTooltip('Collapse health score'));
    await loadArt(t);
    expect(t.takeException(), isNull);
  });
}
