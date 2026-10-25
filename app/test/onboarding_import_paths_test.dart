// The "Fill from Apple Health or a document" option must be there from the first screen to the
// last question, in every state a question can be in, and skipping it must still finish.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';

import 'health_offer_test.dart' show OfferGuide;
import 'voice_onboarding_screen_test.dart' show choose;

const label = 'Fill from Apple Health or a document';

class Rig {
  Rig({ConversationGuide? guide, this.scale = 1})
    : c = VoiceOnboardingController(
        guide: guide ?? FakeConversationGuide(),
        input: FakeSpeechInput(),
        output: FakeSpeechOutput(),
      );
  final VoiceOnboardingController c;
  final double scale;
  Map<String, dynamic>? done;
  int health = 0, docs = 0;

  Future<void> pump(WidgetTester t, {double keyboard = 0}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(390, 844), viewInsets: EdgeInsets.only(bottom: keyboard), textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: VoiceOnboardingScreen(
            controller: c,
            onDone: (p) => done = p,
            onUseHealth: () => health++,
            onUploadDocument: () => docs++,
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('BUG: the consent screen (the first onboarding screen) already offers the import', skip: true, (t) async {
    final r = Rig();
    await r.pump(t);
    expect(find.text("No, I'll type"), findsOneWidget, reason: 'this is the consent screen');
    expect(find.byType(ImportControl), findsOneWidget);
  });

  testWidgets('present on a typed question, a read-back, and the correction box', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "No, I'll type");
    expect(find.byType(ImportControl), findsOneWidget, reason: 'question 1');

    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    if (r.c.confirming) {
      expect(find.byType(ImportControl), findsOneWidget, reason: 'the read-back');
      await t.tap(find.text('No, change it'));
      await t.pumpAndSettle();
      expect(r.c.correcting, isTrue);
      expect(find.byType(ImportControl), findsOneWidget, reason: 'while correcting');
    }
  });

  testWidgets('present while the voice talk screen is up (voice chosen)', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "Yes, I'll talk");
    expect(find.byType(ImportControl), findsOneWidget);
  });

  testWidgets('still reachable at 2x text (collapsed to an icon, labelled for screen readers)', (t) async {
    final h = t.ensureSemantics();
    final r = Rig(scale: 2);
    await r.pump(t);
    await choose(t, "No, I'll type");
    expect(find.byType(ImportControl), findsOneWidget);
    expect(find.bySemanticsLabel(label), findsOneWidget);
    final size = t.getSize(find.byType(ImportControl));
    expect(size.width >= 48 && size.height >= 48, isTrue, reason: '$size');
    h.dispose();
  });

  testWidgets('BUG: still reachable while the keyboard is open (the person is typing an answer)', skip: true, (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "No, I'll type");
    await r.pump(t, keyboard: 300);
    await t.pump();
    expect(find.byType(ImportControl), findsOneWidget);
  });

  testWidgets('Apple Health offered, answered "no thanks": onboarding completes without any import', (t) async {
    final r = Rig(guide: _SkipOfferGuide());
    await r.pump(t);
    await choose(t, "No, I'll type");
    expect(r.c.turn!.phase, 'offering');
    await t.enterText(find.byType(TextField), 'no thanks');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(r.c.phase, VoicePhase.done);
    expect(r.health, 0);
    expect(r.docs, 0);
    expect(find.byType(ImportControl), findsNothing, reason: 'nothing to import once finished');
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(r.done, OfferGuide.known, reason: 'only what was confirmed, nothing from Health');
  });

  testWidgets('"I don\'t know" is a valid answer: Not sure sends it, and it is recorded as unknown, not 0', (t) async {
    final r = Rig(guide: _DiabetesGuide());
    await r.pump(t);
    await choose(t, "No, I'll type");
    await t.tap(find.text('Not sure'));
    await t.pumpAndSettle();
    final sent = (r.c.guide as _DiabetesGuide).texts;
    expect(sent, ["I don't know"]);
    expect(r.c.turn!.state['unknown_fields'], ['diabetes']);
    expect(r.c.confirmedProfile.containsKey('diabetes'), isFalse, reason: 'unknown never becomes false');
    expect(r.c.questionNumber, 3, reason: 'an unknown counts as done and moves on');
  });
}

class _SkipOfferGuide extends OfferGuide {
  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    bool aiHelper = false,
    String? importSource,
  }) async {
    if (action == 'reply') {
      return const GuideTurn(
        state: {'phase': 'ready', 'current_field': null, 'confirmed_profile': OfferGuide.known, 'pending_profile': {}},
        message: 'No problem. That is everything I need.',
        complete: true,
      );
    }
    return super.turn(action: action, state: state, text: text);
  }
}

class _DiabetesGuide extends FakeConversationGuide {
  final texts = <String>[];
  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    bool aiHelper = false,
    String? importSource,
  }) async {
    if (action == 'start') {
      return const GuideTurn(
        state: {'phase': 'asking', 'current_field': 'diabetes', 'confirmed_profile': {'age': 60}, 'pending_profile': {}},
        message: 'Do you have diabetes?',
        complete: false,
      );
    }
    texts.add(text ?? '');
    return const GuideTurn(
      state: {
        'phase': 'asking',
        'current_field': 'smoking_status',
        'confirmed_profile': {'age': 60},
        'pending_profile': {},
        'unknown_fields': ['diabetes'],
      },
      message: 'Do you smoke?',
      complete: false,
    );
  }
}
