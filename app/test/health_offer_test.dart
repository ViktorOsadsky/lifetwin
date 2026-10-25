// Conversation v2 offers Apple Health after age, sex and smoking (phase `offering`), and a
// yes comes back with `client_action: open_health_import`. The screen must then offer the
// Apple Health import, not only on the first question.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';

/// The server's turns around the offer, as conversation v2 sends them.
class OfferGuide implements ConversationGuide {
  static const known = {'age': 72, 'sex': 'female', 'smoking_status': 'never'};

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
        state: {'phase': 'offering', 'current_field': null, 'confirmed_profile': known, 'pending_profile': {}},
        message: 'Thank you. Shall I fill in your height, weight, sleep and activity from Apple Health?',
        complete: false,
      );
    }
    return const GuideTurn(
      state: {'phase': 'offering', 'current_field': null, 'confirmed_profile': known, 'pending_profile': {}},
      message: 'Lovely. Check each reading in Apple Health, then come back to me.',
      complete: false,
      clientAction: 'open_health_import',
    );
  }
}

/// After a yes, the person talks instead: the server pivots to the next question.
class PivotGuide extends OfferGuide {
  final sent = <String>[];

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
    if (action == 'reply' && text != null && text != 'yes please') {
      sent.add(text);
      return const GuideTurn(
        state: {
          'phase': 'asking',
          'current_field': 'height_cm',
          'health_offered': true,
          'confirmed_profile': OfferGuide.known,
          'pending_profile': {},
        },
        message: "No problem, I'll just ask you. How tall are you?",
        complete: false,
      );
    }
    return super.turn(action: action, state: state, text: text, fromTranscript: fromTranscript);
  }
}

void main() {
  testWidgets('after yes, a typed answer is sent normally and the offer hint goes away', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final guide = PivotGuide();
    final c = VoiceOnboardingController(guide: guide, input: FakeSpeechInput(), output: FakeSpeechOutput());
    await t.pumpWidget(
      MaterialApp(home: VoiceOnboardingScreen(controller: c, onDone: (_) {}, onUseHealth: () {})),
    );
    await t.ensureVisible(find.text("No, I'll type"));
    await t.tap(find.text("No, I'll type"));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 700));
    await t.ensureVisible(find.text('Not now'));
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'yes please');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(c.turn!.clientAction, 'open_health_import');
    expect(c.healthOffer, isTrue);

    await t.enterText(find.byType(TextField), "I'd rather tell you, I'm 5'4");
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(guide.sent, ["I'd rather tell you, I'm 5'4"]);
    expect(c.turn!.phase, 'asking');
    expect(c.healthOffer, isFalse);
    expect(find.textContaining('Tap the button below to fill from Apple Health'), findsNothing);
  });

  testWidgets('the Apple Health offer and the yes to it show the import button', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var opened = 0;
    final c = VoiceOnboardingController(guide: OfferGuide(), input: FakeSpeechInput(), output: FakeSpeechOutput());
    await t.pumpWidget(
      MaterialApp(
        home: VoiceOnboardingScreen(controller: c, onDone: (_) {}, onUseHealth: () => opened++),
      ),
    );
    await t.ensureVisible(find.text("No, I'll type"));
    await t.tap(find.text("No, I'll type"));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 700));
    await t.ensureVisible(find.text('Not now'));
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();

    expect(c.turn!.phase, 'offering');
    expect(c.questionNumber, isNot(1)); // three answers are already confirmed
    expect(c.healthOffer, isTrue);
    expect(find.textContaining('Tap the button below to fill from Apple Health or a document'), findsOneWidget);
    expect(find.text('Use my Apple Health'), findsNothing, reason: 'no extra buttons; the one control is the entry');
    expect(find.text('Fill from Apple Health or a document'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'yes please');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(c.turn!.clientAction, 'open_health_import');
    await t.pump(const Duration(milliseconds: 700));
    await t.tap(find.text('Fill from Apple Health or a document'));
    await t.pumpAndSettle();
    await t.tap(find.text('Use Apple Health'));
    expect(opened, 1);
  });
}
