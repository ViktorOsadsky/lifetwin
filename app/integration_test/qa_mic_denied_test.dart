// QA: the microphone is not allowed. Run after
//   xcrun simctl privacy <sim> revoke microphone com.danielqi.lifesim
// The real recorder is used (Pip is muted). Expect the plain message, Open Settings
// (which really opens the Settings app; the shell watcher comes back), and typing.
//   flutter test integration_test/qa_mic_denied_test.dart -d <sim> --dart-define=API_BASE_URL=http://127.0.0.1:8051
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/cartesia_speech.dart';
import 'package:lifesim/voice/http_conversation_guide.dart';
import 'package:lifesim/voice/voice_token.dart';

import 'support/qa_support.dart';
import 'support/sim_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mic denied: message, Open Settings, typing works; Talk again says the same', (t) async {
    final api = ApiBase();
    final tokens = VoiceTokenProvider(base: api);
    final output = MutedOutput(CartesiaSpeechOutput(tokens: tokens));
    final c = VoiceOnboardingController(
      guide: HttpConversationGuide(base: api),
      input: CartesiaSpeechInput(tokens: tokens),
      output: output,
    );
    await qaReset();
    await t.pumpWidget(LifeTwinApp(controller: c));
    await tapText(t, 'Talk');
    await tapText(t, "Yes, I'll talk");
    await readQuestion(t);
    await tapText(t, 'Not now');
    // The memory question is spoken first; the microphone is tried on it.
    await waitFor(t, find.textContaining(memoryQuestion));
    await settled(t);
    await t.tap(find.byType(TalkButton).first, warnIfMissed: false);
    await waitFor(t, find.text(micDeniedNotice));
    await pumpFor(t, const Duration(seconds: 1));
    expect(c.phase, isNot(VoicePhase.listening));
    expect(c.typing, isTrue);
    expect(find.text('Open Settings'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await qaAction(t, 'shot', name: 'mic-denied', wait: const Duration(seconds: 1));
    await say(t, 'No thanks', ageQuestion);
    await say(t, '71', 'you are 71');
    await yes(t, sexQuestion);
    // Talk again: same plain message, never stuck listening.
    await hideKeyboard(t);
    await tapText(t, 'Talk instead');
    await pumpFor(t, const Duration(seconds: 1));
    if (find.byType(TalkButton).evaluate().isNotEmpty) {
      await t.tap(find.byType(TalkButton).first, warnIfMissed: false);
    }
    await waitFor(t, find.text(micDeniedNotice));
    expect(c.typing, isTrue);
    // Open Settings really leaves for the Settings app; the watcher brings LifeTwin back.
    await tapText(t, 'Open Settings');
    await qaAction(t, 'settings', wait: const Duration(seconds: 8));
    expect(c.confirmedProfile['age'], 71);
    await say(t, 'female', 'female at birth');
  });
}
