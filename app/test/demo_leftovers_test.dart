// Leftovers from the demo hunts (#243, #245, #246): one test per fix. With EVIDENCE_DIR set, the
// visual ones also write a PNG for review.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_screen.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/customize/customize_screen.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/twin/twin_checkin_store.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/lip_button.dart' show RoundBackButton;
import 'package:lifesim/ui/widgets/plate_window.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/voice_indicator.dart';

import 'checkin_controller_test.dart' show FakeCheckinGuide;
import 'experiment/experiment_screen_test.dart' show older;
import 'missing_answers_test.dart' show AskOnlyGuide;
import 'support/app_fonts.dart';
import 'twin/store_and_checkin_test.dart' show fullProfile;
import 'visual_sweep_test.dart' show loadMaterialIcons;

/// A microphone whose start never answers (a voice token server that hangs).
class HangingInput extends FakeSpeechInput {
  @override
  Future<void> start(void Function(String text) onCaption, {void Function(Object error)? onDropped}) {
    starts++;
    return Completer<void>().future;
  }
}

const phone = Size(402, 874);
const se = Size(375, 667);
const narrow = Size(320, 568);
const look = TwinAppearance(name: 'Mochi', look: TwinLook.calHat);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    await loadMaterialIcons();
    model = await TwinModelService.load();
  });

  final evidenceDir = Platform.environment['EVIDENCE_DIR'];
  final shotKey = GlobalKey();

  Future<void> shot(WidgetTester t, String name) async {
    if (evidenceDir == null) return;
    await t.runAsync(() async {
      final c = t.element(find.byKey(shotKey));
      await precacheImage(const AssetImage('assets/scene/room/room_bg.jpg'), c);
      for (final pose in TwinPose.values) {
        try {
          await precacheImage(AssetImage(twinAsset(TwinType.bear, TwinLook.calHat, pose)), c);
        } catch (_) {}
      }
    });
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(() async {
      Directory(evidenceDir).createSync(recursive: true);
      final b = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$evidenceDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  /// [home] on a phone of [size] at [scale] text, with the iPhone's safe areas.
  Future<void> pumpPhone(
    WidgetTester t,
    Widget home, {
    Size size = phone,
    double scale = 1,
    ValueListenable<bool>? voiceOver,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    t.view.padding = FakeViewPadding(top: size.height > 700 ? 62 : 20, bottom: size.height > 700 ? 34 : 0);
    addTearDown(t.view.reset);
    final vo = voiceOver ?? ValueNotifier(false);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: (context, child) => ValueListenableBuilder<bool>(
          valueListenable: vo,
          builder: (context, on, _) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true, accessibleNavigation: on),
            child: RepaintBoundary(key: shotKey, child: child!),
          ),
        ),
        home: home,
      ),
    );
    await t.pump();
  }

  Future<void> frames(WidgetTester t, Duration total) async {
    for (var left = total; left > Duration.zero; left -= const Duration(milliseconds: 250)) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<TwinRepository> repository() async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    await repo.saveConversationProfile(older);
    return repo;
  }

  Future<VoiceOnboardingController> onboarding(
    WidgetTester t, {
    Size size = phone,
    double scale = 1,
    bool handsFree = true,
    FakeSpeechInput? input,
    ValueListenable<bool>? voiceOver,
  }) async {
    final c = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: input ?? FakeSpeechInput(),
      output: FakeSpeechOutput(),
      handsFree: handsFree,
    );
    addTearDown(c.dispose);
    await pumpPhone(
      t,
      VoiceOnboardingScreen(controller: c, onDone: (_) {}, onUseHealth: () {}, appearance: look),
      size: size,
      scale: scale,
      voiceOver: voiceOver,
    );
    return c;
  }

  /// The part of [f] its scroll view (if any) and the screen show.
  Rect visible(WidgetTester t, Finder f, Size size) {
    var r = t.getRect(f);
    final list = Scrollable.maybeOf(t.element(f));
    if (list != null) {
      final box = list.context.findRenderObject()! as RenderBox;
      r = r.intersect(box.localToGlobal(Offset.zero) & box.size);
    }
    return r.intersect(Offset.zero & size);
  }

  void expectFullyVisible(WidgetTester t, Finder f, Size size, String why) {
    expect(f, findsOneWidget, reason: why);
    final whole = t.getRect(f);
    final seen = visible(t, f, size);
    expect(seen.height, closeTo(whole.height, 0.5), reason: '$why: $whole, only $seen in view');
  }

  /// Places on screen whose words contain [words]. Outlined display text is the same words painted
  /// twice (stroke and fill) in one place: counted once.
  int shownWith(WidgetTester t, String words) {
    final places = <Offset>[];
    for (final p in t.allRenderObjects.whereType<RenderParagraph>()) {
      if (!p.attached || !p.hasSize || !p.text.toPlainText(includeSemanticsLabels: false).contains(words)) continue;
      final at = p.localToGlobal(p.size.center(Offset.zero));
      if (places.every((o) => (o - at).distance >= 3)) places.add(at);
    }
    return places.length;
  }

  // 1 -------------------------------------------------------------------------------------------
  testWidgets('1 check-in: the question is shown once, in full', (t) async {
    final repo = await repository();
    final c = CheckinController(
      guide: FakeCheckinGuide(),
      input: FakeSpeechInput(),
      output: FakeSpeechOutput(),
      store: TwinCheckinStore(repo),
      voiceUsable: false,
    );
    addTearDown(c.dispose);
    await pumpPhone(
      t,
      CheckInScreen(controller: c, kind: CheckInKind.quick, repository: repo, appearance: look, onDone: () {}),
    );
    await frames(t, const Duration(seconds: 1));
    await shot(t, '1-checkin-question');
    expect(shownWith(t, 'How did you sleep'), 1, reason: 'one place says the question');
    expect(
      find.text('How did you sleep last night?'),
      findsOneWidget,
      reason: 'the full question, not a short caption',
    );
  });

  // 2 -------------------------------------------------------------------------------------------
  testWidgets('2 onboarding typing: no voice status pill', (t) async {
    final c = await onboarding(t);
    await t.tap(find.text("No, I'll type"));
    await t.pump(const Duration(milliseconds: 800));
    if (find.text('Not now').evaluate().isNotEmpty) {
      await t.tap(find.text('Not now'));
      await t.pump();
    }
    await frames(t, const Duration(seconds: 1));
    expect(c.typing, isTrue);
    await shot(t, '2-onboarding-typing');
    expect(find.text('Not listening'), findsNothing);
    expect(find.byType(VoicePill), findsNothing);
    expect(find.text('Talk instead'), findsOneWidget, reason: 'the way back to voice stays');
  });

  // 3 -------------------------------------------------------------------------------------------
  for (final (name, size) in [('402x874', phone), ('375x667', se)]) {
    testWidgets('3 onboarding at 2x on $name: the read-back and its answer are in view', (t) async {
      final input = FakeSpeechInput()..captions = ['I am 70'];
      final c = await onboarding(t, size: size, scale: 2, input: input);
      unawaited(c.answerConsent(true));
      await frames(t, const Duration(seconds: 1)); // asked, then "I am 70" heard
      input.captions = const []; // the next listen hears nothing yet
      await frames(t, const Duration(seconds: 5)); // the end-of-turn quiet, then the read-back
      expect(c.confirming, isTrue);
      await shot(t, '3-onboarding-readback-2x-$name');
      expectFullyVisible(
        t,
        find.text('I heard you are 70. Is that right?', findRichText: true),
        size,
        'the read-back question',
      );
      expectFullyVisible(t, find.text('Age 70', findRichText: true), size, 'the read-back answer');
      expect(t.takeException(), isNull);
    });
  }

  // 4 -------------------------------------------------------------------------------------------
  testWidgets('4 onboarding at 320 wide and 2x: one scroll area', (t) async {
    final c = await onboarding(t, size: narrow, scale: 2);
    unawaited(c.answerConsent(true));
    await frames(t, const Duration(seconds: 1));
    await shot(t, '4-onboarding-320-2x');
    final lists = find
        .descendant(of: find.byType(VoiceOnboardingScreen), matching: find.byType(Scrollable))
        .evaluate()
        .where((e) => e.findAncestorWidgetOfExactType<EditableText>() == null)
        .toList();
    expect(lists, hasLength(1), reason: 'one scroll for the whole page');
    // Everything is still reachable in it.
    await t.scrollUntilVisible(find.text('Type instead'), 200, scrollable: find.byWidget(lists.single.widget));
    expect(t.takeException(), isNull);
  });

  // 5 -------------------------------------------------------------------------------------------
  for (final (name, size) in [('402', phone), ('375', se), ('320', narrow)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('5 Customize tabs at $name / ${scale}x: even rows, same order', (t) async {
        final appearance = ValueNotifier(look);
        addTearDown(appearance.dispose);
        await pumpPhone(
          t,
          CustomizeScreen(appearance: appearance, onDone: () {}),
          size: size,
          scale: scale,
        );
        await t.pumpAndSettle();
        await shot(t, '5-customize-$name-${scale.toInt()}x');
        const order = ['Hats', 'Tops', 'Glasses', 'Fur', 'Helpers', 'Room'];
        final rects = {for (final l in order) l: t.getRect(find.text(l))};
        final rows = <double, List<String>>{};
        for (final l in order) {
          final top = rows.keys.where((y) => (y - rects[l]!.center.dy).abs() < 8).firstOrNull ?? rects[l]!.center.dy;
          (rows[top] ??= []).add(l);
        }
        final counts = {for (final r in rows.values) r.length};
        expect(counts, hasLength(1), reason: 'every row has as many tabs: $rows');
        final reading = [...order]
          ..sort((a, b) {
            final dy = rects[a]!.center.dy - rects[b]!.center.dy;
            return dy.abs() >= 8 ? dy.sign.toInt() : rects[a]!.left.compareTo(rects[b]!.left);
          });
        expect(reading, order, reason: 'tab order is unchanged');
        expect(t.takeException(), isNull);
      });
    }
  }

  // 6 -------------------------------------------------------------------------------------------
  for (final (name, size) in [('402x874', phone), ('375x667', se)]) {
    testWidgets('6 check-in at 2x on $name: the name banner clears the back button', (t) async {
      final repo = await repository();
      final c = CheckinController(
        guide: FakeCheckinGuide(),
        input: FakeSpeechInput(),
        output: FakeSpeechOutput(),
        store: TwinCheckinStore(repo),
        voiceUsable: false,
      );
      addTearDown(c.dispose);
      await pumpPhone(
        t,
        CheckInScreen(controller: c, kind: CheckInKind.quick, repository: repo, appearance: look, onDone: () {}),
        size: size,
        scale: 2,
      );
      await frames(t, const Duration(seconds: 1));
      await shot(t, '6-banner-2x-$name');
      final banner = t.getRect(find.byType(NameBanner));
      final back = t.getRect(find.byType(RoundBackButton).first);
      expect(back.inflate(8).overlaps(banner), isFalse, reason: 'back $back, banner $banner');
    });
  }

  for (final (name, size) in [('402x874', phone), ('375x667', se), ('320x568', narrow)]) {
    testWidgets('6 Customize at 2x on $name: the name banner clears the back button', (t) async {
      final appearance = ValueNotifier(look);
      addTearDown(appearance.dispose);
      await pumpPhone(
        t,
        CustomizeScreen(appearance: appearance, onDone: () {}),
        size: size,
        scale: 2,
      );
      await t.pumpAndSettle();
      await shot(t, '6-customize-banner-2x-$name');
      final banner = t.getRect(find.byType(NameBanner));
      final back = t.getRect(find.byType(RoundBackButton).first);
      expect(back.inflate(8).overlaps(banner), isFalse, reason: 'back $back, banner $banner');
    });
  }

  // 7 -------------------------------------------------------------------------------------------
  testWidgets('7 three rounds of "Answer N more questions" leave no controller, timer or listener behind', (t) async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    await repo.saveConversationProfile({...fullProfile}..remove('sleep_hours'));
    final input = FakeSpeechInput();
    final output = FakeSpeechOutput();
    final intake = VoiceOnboardingController(guide: AskOnlyGuide(), input: input, output: output, handsFree: true);
    addTearDown(intake.dispose);
    final routes = AgenticRoutes(look: ValueNotifier(const TwinAppearance()), api: ApiBase(), voice: () => intake)
      ..attach(repo);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => routes.answerMissing(c), child: const Text('origin')),
            ),
          ),
        ),
      ),
    );
    final talks = <VoiceOnboardingController>[];
    for (var round = 0; round < 3; round++) {
      await t.tap(find.text('origin'));
      await frames(t, const Duration(seconds: 2));
      final talk = routes.lastMissingTalk!;
      expect(talks, isNot(contains(talk)));
      talks.add(talk);
      Navigator.of(t.element(find.byType(VoiceOnboardingScreen))).pop();
      await frames(t, const Duration(seconds: 2));
      expect(find.text('origin'), findsOneWidget);
    }
    for (final talk in talks) {
      expect(() => ChangeNotifier.debugAssertNotDisposed(talk), throwsFlutterError, reason: 'disposed when closed');
    }
    expect(input.disposals, 0, reason: 'the shared speech input is the intake’s, never disposed here');
    expect(input.listening, isFalse);
    // The test binding fails the test if a timer is still pending here.
  });

  // 8 -------------------------------------------------------------------------------------------
  testWidgets('8 onboarding: a hanging token says Connecting, and one retry later the trouble notice', (t) async {
    final input = HangingInput();
    final c = await onboarding(t, input: input);
    unawaited(c.answerConsent(true));
    await frames(t, const Duration(seconds: 1));
    expect(c.phase, VoicePhase.listening);
    await shot(t, '8-onboarding-connecting');
    expect(find.textContaining('Connecting'), findsOneWidget);
    expect(find.textContaining('Listening'), findsNothing, reason: 'nothing is heard yet');
    await frames(t, const Duration(seconds: 10)); // the start limit
    await frames(t, const Duration(seconds: 1)); // the one retry
    await frames(t, const Duration(seconds: 11)); // its start limit
    expect(input.starts, 2, reason: 'one retry, not three');
    expect(c.notice, voiceTroubleNotice);
    expect(c.phase, VoicePhase.idle);
    await shot(t, '8-onboarding-trouble');
  });

  test('8 check-in: a hanging token gets one retry, then the trouble notice', () {
    fakeAsync((fa) {
      final input = HangingInput();
      final c = CheckinController(
        guide: FakeCheckinGuide(),
        input: input,
        output: FakeSpeechOutput(),
        store: InMemoryCheckinStore(
          checkins: [const CheckinEntry(kind: 'quick', date: '2026-10-23', answers: {})],
        ),
        clock: () => DateTime(2026, 10, 25, 9),
        handsFree: true,
      );
      c.start();
      fa.flushMicrotasks();
      expect(c.phase, CheckinPhase.listening);
      expect(c.connecting, isTrue, reason: 'the screen says Connecting, not Listening');
      fa.elapse(const Duration(seconds: 23));
      expect(input.starts, 2);
      expect(c.notice, voiceTroubleNotice);
      c.dispose();
    });
  });

  // 9 -------------------------------------------------------------------------------------------
  testWidgets('9 onboarding: VoiceOver turned off while waiting for a tap opens the mic', (t) async {
    final voiceOver = ValueNotifier(true);
    addTearDown(voiceOver.dispose);
    final input = FakeSpeechInput();
    final c = await onboarding(t, input: input, voiceOver: voiceOver);
    unawaited(c.answerConsent(true));
    await frames(t, const Duration(seconds: 1));
    expect(c.screenReader, isTrue);
    expect(input.listening, isFalse, reason: 'with VoiceOver the mic waits for a tap');
    voiceOver.value = false;
    await frames(t, const Duration(seconds: 1));
    expect(c.screenReader, isFalse);
    expect(input.listening, isTrue, reason: 'listens now, not at the next turn');
    expect(c.phase, VoicePhase.listening);
  });

  test('9 check-in: VoiceOver turned off while waiting for a tap opens the mic', () {
    fakeAsync((fa) {
      final input = FakeSpeechInput();
      final c = CheckinController(
        guide: FakeCheckinGuide(),
        input: input,
        output: FakeSpeechOutput(),
        store: InMemoryCheckinStore(
          checkins: [const CheckinEntry(kind: 'quick', date: '2026-10-23', answers: {})],
        ),
        clock: () => DateTime(2026, 10, 25, 9),
        handsFree: true,
      )..screenReader = true;
      c.start();
      fa.flushMicrotasks();
      expect(input.listening, isFalse);
      c.screenReader = false;
      fa.flushMicrotasks();
      expect(input.listening, isTrue);
      c.dispose();
    });
  });
}
