import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_screen.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/widgets.dart' show LipButton;
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';

import 'checkin_controller_test.dart' show FakeCheckinGuide;
import 'support/app_fonts.dart';

/// The continuous-voice indicator (design VC-1 to VC-7, VCN-1): one status pill and ring per state.
/// The teal ring and the live dot are the honest mic indicator: they show only while the mic is open.
/// Replaying the line takes as long as the test says (the real one plays audio).
class HoldReplayOutput extends FakeSpeechOutput {
  Completer<void>? replayGate;

  @override
  Future<void> replay() async {
    replays++;
    await replayGate?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);

  const ring = {
    'listening': ValueKey('voice-ring-listening'),
    'speaking': ValueKey('voice-ring-speaking'),
    'thinking': ValueKey('voice-ring-thinking'),
  };
  const dot = ValueKey('voice-live-dot');
  const fill = ImportControl.label;

  // Pictures for review, written only when EVIDENCE_DIR is set.
  final evidenceDir = Platform.environment['EVIDENCE_DIR'];
  final shotKey = GlobalKey();

  Future<void> shot(WidgetTester t, String name) async {
    if (evidenceDir == null) return;
    await t.runAsync(() async {
      final c = t.element(find.byType(Scaffold).first);
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
      final b = shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$evidenceDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  group('onboarding conversation', () {
    late VoiceOnboardingController c;
    late FakeConversationGuide guide;
    late HoldReplayOutput output;
    late FakeSpeechInput input;

    Future<void> open(
      WidgetTester t, {
      bool voiceOver = false,
      bool reduced = false,
      double scale = 1,
      bool holdSpeech = false,
    }) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      guide = FakeConversationGuide();
      output = HoldReplayOutput()..holdSpeech = holdSpeech;
      input = FakeSpeechInput();
      c = VoiceOnboardingController(guide: guide, input: input, output: output, handsFree: true);
      await t.pumpWidget(
        MaterialApp(
          theme: lifeTwinTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              disableAnimations: reduced,
              accessibleNavigation: voiceOver,
              textScaler: TextScaler.linear(scale),
            ),
            child: RepaintBoundary(
              key: shotKey,
              child: VoiceOnboardingScreen(
                controller: c,
                onDone: (_) {},
                onUseHealth: () {},
                appearance: const TwinAppearance(name: 'Mochi', look: TwinLook.calHat),
              ),
            ),
          ),
        ),
      );
      unawaited(c.answerConsent(true)); // the consent questions are not part of this look
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
    }

    Future<void> end(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      c.dispose();
    }

    void expectRings(Set<String> shown) {
      for (final e in ring.entries) {
        expect(find.byKey(e.value), shown.contains(e.key) ? findsOneWidget : findsNothing, reason: e.key);
      }
    }

    void expectReachable(WidgetTester t) {
      expect(find.text(fill), findsOneWidget, reason: 'Fill from Apple Health or a document');
      expect(find.text('Type instead'), findsOneWidget);
      expect(t.getSize(find.byType(ImportControl)).height, greaterThanOrEqualTo(48));
    }

    testWidgets('VC-1 Speaking: gold ring and bars, "Mochi is talking", no teal ring, no Stop', (t) async {
      await open(t, holdSpeech: true);
      expect(c.phase, VoicePhase.speaking);
      expect(find.text('Mochi is talking'), findsOneWidget);
      expectRings({'speaking'});
      expect(find.byKey(dot), findsNothing);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('How old are you?'), findsWidgets, reason: 'the whole line, no word timings');
      expect(find.text('Mochi listens only on this screen.'), findsOneWidget);
      expectReachable(t);
      await shot(t, 'vc_1_speaking');
      output.finishSpeaking();
      await t.pump();
      await end(t);
    });

    testWidgets('VC-2 Listening: teal ring and live dot, "Listening…", live transcript with a softer last word', (
      t,
    ) async {
      await open(t);
      expect(c.phase, VoicePhase.listening);
      expect(find.text('Listening…'), findsOneWidget);
      expectRings({'listening'});
      expect(find.byKey(dot), findsOneWidget);
      expect(find.text('Mochi listens only on this screen.'), findsOneWidget);
      expect(find.text('Tap to talk'), findsNothing);
      expectReachable(t);
      input.onCaption!('I’m 64, and I’m a woman. Never');
      await t.pump();
      await t.pump(const Duration(milliseconds: 150));
      expect(find.text('You’re saying'), findsOneWidget);
      expect(find.textContaining('I’m a woman.', findRichText: true), findsOneWidget);
      await shot(t, 'vc_2_listening');
      await end(t);
    });

    testWidgets('the pill is a polite live label, not a button', (t) async {
      final handle = t.ensureSemantics();
      await open(t);
      final node = t.getSemantics(find.byKey(const ValueKey('voice-pill-listening')));
      expect(node.label, 'Listening');
      expect(node.flagsCollection.isLiveRegion, isTrue);
      expect(node.flagsCollection.isButton, isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      await end(t);
      handle.dispose();
    });

    testWidgets('VC-3 Thinking: dashed ring and dots only after 300 ms, never the teal ring or dot', (t) async {
      await open(t);
      guide.gate = Completer<void>();
      input.transcript = 'I’m 64, and I’m a woman. Never smoked.';
      input.onCaption!(input.transcript);
      await t.pump(voiceEndOfTurn);
      await t.pump(const Duration(milliseconds: 150));
      expect(c.phase, VoicePhase.interpreting);
      expect(input.listening, isFalse);
      // The first 300 ms: nothing claims anything.
      expect(find.text('Thinking…'), findsNothing);
      expect(find.text('Listening…'), findsNothing);
      expectRings({});
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Thinking…'), findsOneWidget);
      expectRings({'thinking'});
      expect(find.byKey(dot), findsNothing);
      expect(find.text('You said'), findsOneWidget);
      expectReachable(t);
      await shot(t, 'vc_3_thinking');
      guide.gate!.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await end(t);
    });

    testWidgets('VC-4 Nudge: the line is the smaller caption, the question stays; the mic is closed while it plays', (
      t,
    ) async {
      await open(t);
      output.holdSpeech = true;
      await t.pump(voiceNudgeAfter + const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 300));
      expect(output.spoken.last, listeningNudge);
      expect(c.nudgeSpeaking, isTrue);
      expect(find.text('Mochi is talking'), findsOneWidget);
      expectRings({'speaking'});
      expect(find.byKey(dot), findsNothing);
      expect(find.text(listeningNudge), findsOneWidget);
      output.finishSpeaking();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(c.phase, VoicePhase.listening);
      expect(c.nudgeSpeaking, isFalse);
      expect(find.text('Listening…'), findsOneWidget);
      expectRings({'listening'});
      expect(find.text(listeningNudge), findsOneWidget, reason: 'the caption stays under the question');
      expect(find.text('How old are you?'), findsWidgets);
      await shot(t, 'vc_4_nudge');
      await end(t);
    });

    testWidgets('VC-5 VoiceOver: no motion, "Waiting for your tap", the one 72 pt "Tap to talk to Mochi"', (t) async {
      await open(t, voiceOver: true);
      expect(input.starts, 0, reason: 'nothing opens by itself');
      expect(find.text('Waiting for your tap'), findsOneWidget);
      expectRings({});
      expect(find.byKey(dot), findsNothing);
      final tap = find.byKey(const ValueKey('tap-to-talk'));
      expect(tap, findsOneWidget);
      expect(
        find.byType(LipButton).evaluate().where((e) => (e.widget as LipButton).label.startsWith('Tap')),
        hasLength(1),
      );
      expect(find.byType(TalkButton), findsNothing);
      expect(t.getSize(tap).height, greaterThanOrEqualTo(72));
      expect(find.text('Tap to talk to Mochi'), findsOneWidget);
      expect(find.textContaining('VoiceOver is on', findRichText: true), findsOneWidget);
      expectReachable(t);
      await t.pump(const Duration(milliseconds: 500));
      expect(t.binding.transientCallbackCount, 0, reason: 'no running animation');
      await shot(t, 'vc_5_voiceover');
      await t.tap(tap);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(input.starts, 1);
      expect(find.text('Listening…'), findsOneWidget);
      expect(t.widget<LipButton>(tap).onTap, isNull, reason: 'inert while listening');
      await end(t);
    });

    testWidgets('VC-7 Typing: "Not listening", the text field, Send; "Talk instead" returns to Mochi speaking', (
      t,
    ) async {
      await open(t);
      await t.tap(find.text('Type instead'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(input.listening, isFalse);
      expect(find.text('Not listening'), findsOneWidget);
      expectRings({});
      expect(find.byKey(dot), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Talk instead'), findsOneWidget);
      await shot(t, 'vc_7_typing');
      output.replayGate = Completer<void>();
      await t.tap(find.text('Talk instead'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(c.phase, VoicePhase.speaking);
      expect(output.replays, 1, reason: 'Mochi repeats the question');
      expect(input.listening, isFalse);
      expect(find.text('Mochi is talking'), findsOneWidget);
      expectRings({'speaking'});
      output.replayGate!.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Listening…'), findsOneWidget);
      await end(t);
    });

    testWidgets('reduced motion: still ring, still dot and "Listening", nothing animates', (t) async {
      await open(t, reduced: true);
      expect(find.text('Listening'), findsOneWidget);
      expect(find.text('Listening…'), findsNothing);
      expectRings({'listening'});
      expect(find.byKey(dot), findsOneWidget);
      await t.pump(const Duration(milliseconds: 500));
      expect(t.binding.transientCallbackCount, 0, reason: 'no running animation');
      await t.pump(const Duration(seconds: 3));
      expect(t.binding.transientCallbackCount, 0);
      // The state swap is a short cross-fade, and settles.
      await t.tap(find.text('Type instead'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('Not listening'), findsOneWidget);
      expect(find.byKey(const ValueKey('voice-pill-listening')), findsNothing, reason: 'the 150 ms cross-fade is over');
      await end(t);
    });

    testWidgets('with motion the teal ring and the dot do run while listening (so reduced motion is a real switch)', (
      t,
    ) async {
      await open(t);
      await t.pump(const Duration(milliseconds: 500));
      expect(t.binding.transientCallbackCount, greaterThan(0));
      await end(t);
    });

    testWidgets(
      '1.6x text: no overflow, the Fill row is in the scroll, Type instead is in reach, the last line shows',
      (t) async {
        await open(t, scale: 1.6);
        input.onCaption!('I’m 64, and I’m a woman. Never smoked, and I walk most days.');
        await t.pump();
        await t.pump(const Duration(milliseconds: 20)); // the scroll animation starts on a frame of its own
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull);
        expect(find.text('Listening…'), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('story')), matching: find.text(fill)), findsOneWidget);
        expect(find.byType(ImportControl), findsNothing, reason: 'the Fill row moved out of the dock');
        final dock = t.getRect(find.byKey(const ValueKey('sheet')));
        final typeInstead = t.getRect(find.text('Type instead'));
        expect(typeInstead.bottom, lessThanOrEqualTo(844));
        expect(typeInstead.height, greaterThanOrEqualTo(17));
        final transcript = t.getRect(find.byKey(const ValueKey('transcript-live')));
        expect(transcript.bottom, lessThanOrEqualTo(dock.top), reason: 'the last line stays above the dock');
        await shot(t, 'vc_6_large_listening');
        await end(t);
      },
    );

    testWidgets('1.6x text in the other states: no overflow', (t) async {
      await open(t, scale: 1.6, voiceOver: true);
      expect(t.takeException(), isNull);
      expect(find.text('Waiting for your tap'), findsOneWidget);
      expect(find.text('Tap to talk to Mochi'), findsOneWidget);
      await end(t);
      await open(t, scale: 1.6, holdSpeech: true);
      expect(t.takeException(), isNull);
      expect(find.text('Mochi is talking'), findsOneWidget);
      output.finishSpeaking();
      await t.pump();
      await end(t);
    });
  });

  group('check-in', () {
    late TwinModelService model;
    setUpAll(() async => model = await TwinModelService.load());

    testWidgets('hands-free shows the same pill, the ring and a way back from typing', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repo = TwinRepository(
        model: model,
        store: await TwinStore.open(MemoryBackend()),
        clock: () => DateTime(2026, 10, 24, 10),
      );
      final output = HoldReplayOutput();
      final input = FakeSpeechInput();
      final c = CheckinController(
        guide: FakeCheckinGuide(),
        input: input,
        output: output,
        store: InMemoryCheckinStore(),
        clock: () => DateTime(2026, 10, 24, 10),
        voiceUsable: true,
        handsFree: true,
      );
      addTearDown(c.dispose);
      await t.pumpWidget(
        MaterialApp(
          theme: lifeTwinTheme(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
            child: RepaintBoundary(
              key: shotKey,
              child: CheckInScreen(
                controller: c,
                kind: CheckInKind.quick,
                repository: repo,
                appearance: const TwinAppearance(),
                onDone: () {},
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(c.phase, CheckinPhase.listening);
      expect(find.text('Listening'), findsOneWidget);
      expect(find.byKey(ring['listening']!), findsOneWidget);
      expect(find.text('Mochi listens only on this screen.'), findsOneWidget);
      expect(find.text('Type instead'), findsOneWidget);
      await shot(t, 'vc_checkin_listening');
      await t.tap(find.text('Type instead'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Not listening'), findsOneWidget);
      expect(find.byKey(ring['listening']!), findsNothing);
      output.replayGate = Completer<void>();
      await t.tap(find.text('Talk instead'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(c.phase, CheckinPhase.speaking);
      expect(find.text('Mochi is talking'), findsOneWidget);
      expect(find.byKey(ring['listening']!), findsNothing);
      output.replayGate!.complete();
      await t.pump();
      await t.pumpWidget(const SizedBox());
    });
  });
}
