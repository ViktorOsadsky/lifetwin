import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';

class Rig {
  final guide = FakeConversationGuide();
  final input = FakeSpeechInput();
  final output = FakeSpeechOutput();
  late final c = VoiceOnboardingController(guide: guide, input: input, output: output);
  Map<String, dynamic>? done;
  bool health = false;

  Future<void> pump(WidgetTester t, {double scale = 1}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale), size: const Size(390, 844)),
        child: VoiceOnboardingScreen(controller: c, onDone: (p) => done = p, onUseHealth: () => health = true),
      ),
    ));
  }
}

/// Answers both consent questions: voice, then the AI helper.
Future<void> choose(WidgetTester t, String voiceLabel, {bool aiHelper = false}) async {
  await t.ensureVisible(find.text(voiceLabel));
  await t.pumpAndSettle();
  await t.tap(find.text(voiceLabel));
  await t.pumpAndSettle();
  final second = aiHelper ? 'Yes, turn it on' : 'Not now';
  await t.ensureVisible(find.text(second));
  await t.pumpAndSettle();
  await t.tap(find.text(second));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('consent explains Cartesia and offers Yes / Type instead; nothing starts before', (t) async {
    final r = Rig();
    await r.pump(t);
    expect(find.textContaining('sent to Cartesia, a voice service, only while you hold the Talk button'), findsOneWidget);
    expect(r.guide.calls, isEmpty);
    expect(r.output.spoken, isEmpty);
    for (final label in ['Yes, I can talk', 'Type instead']) {
      expect(t.getSize(find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))).height, greaterThanOrEqualTo(72));
    }
  });

  testWidgets('Type instead on consent starts the same conversation by typing', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, 'Type instead');
    expect(find.text('How old are you?'), findsOneWidget);
    expect(find.text('Hold to talk'), findsNothing);
    expect(r.output.spoken, isEmpty);
    await t.tap(find.text('Use my Health app instead'));
    expect(r.health, true);
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('Yes consent shows caption, speaks it, and tap-to-talk works', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, 'Yes, I can talk');
    expect(find.text('How old are you?'), findsOneWidget);
    expect(r.output.spoken, ['How old are you?']);
    expect(find.text('Hear it again'), findsOneWidget);
    expect(find.text('Hold to talk'), findsOneWidget);

    r.input.captions = ['I am 70'];
    await t.tap(find.text('Hold to talk')); // quick tap = start
    await t.pumpAndSettle();
    expect(find.textContaining('Hearing: I am 70'), findsOneWidget);
    expect(find.textContaining('Tap or let go'), findsOneWidget);
    await t.tap(find.byType(TalkButton)); // second tap = stop
    await t.pumpAndSettle();
    expect(r.guide.calls.last['text'], 'I am 70');
    expect(find.text('Yes'), findsOneWidget);

    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    await t.tap(find.text('Continue'));
    expect(r.done, {'age': 70});
  });

  testWidgets('holding the button sends when let go', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, 'Yes, I can talk');
    final g = await t.startGesture(t.getCenter(find.byType(TalkButton)));
    await t.pump();
    expect(r.c.phase, VoicePhase.listening);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
    await g.up();
    await t.pumpAndSettle();
    expect(r.input.finishes, 1);
    expect(find.text('Yes'), findsOneWidget);
  });

  testWidgets('mic denied: plain message stays, typing box appears', (t) async {
    final r = Rig();
    r.input.startError = const MicDeniedException();
    await r.pump(t);
    await choose(t, 'Yes, I can talk');
    await t.tap(find.text('Hold to talk'));
    await t.pumpAndSettle();
    expect(find.textContaining('open Settings'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
    expect(find.textContaining('open Settings'), findsOneWidget); // never auto-dismissed
  });

  testWidgets('empty transcript message and large text scale do not overflow', (t) async {
    final r = Rig();
    r.input.transcript = '';
    await r.pump(t, scale: 2.0);
    await choose(t, 'Yes, I can talk');
    await t.ensureVisible(find.text('Hold to talk'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hold to talk'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byType(TalkButton));
    await t.pumpAndSettle();
    await t.tap(find.byType(TalkButton));
    await t.pumpAndSettle();
    expect(find.text(emptyTranscriptNotice), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('app starts on the voice screen and can open Apple Health import', (t) async {
    final r = Rig();
    await t.pumpWidget(LifeTwinApp(controller: r.c));
    expect(find.text('Talk with me?'), findsOneWidget);
    await choose(t, 'Type instead');
    await t.tap(find.text('Use my Health app instead'));
    await t.pumpAndSettle();
    expect(find.text("Use your iPhone's Health app?"), findsOneWidget);
  });

  testWidgets('AI helper consent explains where answers go; yes turns it on for every turn', (t) async {
    final r = Rig();
    await r.pump(t);
    await t.tap(find.text('Type instead'));
    await t.pumpAndSettle();
    expect(find.text('Turn on the AI helper?'), findsOneWidget);
    expect(find.textContaining('go to an outside AI service'), findsOneWidget);
    expect(r.guide.calls, isEmpty); // nothing starts until both questions are answered
    for (final label in ['Yes, turn it on', 'Not now']) {
      expect(t.getSize(find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))).height, greaterThanOrEqualTo(72));
    }
    await t.tap(find.text('Yes, turn it on'));
    await t.pumpAndSettle();
    expect(r.c.aiHelper, isTrue);
    expect(r.guide.calls.single['aiHelper'], isTrue);
    expect(find.text('Turn off AI helper'), findsOneWidget);
  });

  testWidgets('saying not now still lets the AI helper read a hard answer later, without retyping', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, 'Type instead');
    await t.enterText(find.byType(TextField), 'about five foot eight');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(find.text('Yes, let the AI helper read it'), findsOneWidget);
    await t.tap(find.text('Yes, let the AI helper read it'));
    await t.pumpAndSettle();
    expect(r.guide.calls.last['action'], 'reply');
    expect(r.guide.calls.last['text'], 'about five foot eight');
    expect(r.guide.calls.last['aiHelper'], isTrue);
    expect(find.textContaining('5 feet 8 inches'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
  });
}
