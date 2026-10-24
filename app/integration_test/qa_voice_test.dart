// QA by voice, silently: the microphone is a WAV file (FileRecorder), Pip is muted
// (MutedOutput); Cartesia Ink and the server are real. Also leaving the app mid-answer,
// with the shell watcher pressing Home and coming back.
//   flutter test integration_test/qa_voice_test.dart -d <sim> --dart-define=API_BASE_URL=http://127.0.0.1:8051
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

class VoiceRig {
  VoiceRig() {
    final api = ApiBase();
    final tokens = VoiceTokenProvider(base: api);
    output = MutedOutput(CartesiaSpeechOutput(tokens: tokens));
    controller = VoiceOnboardingController(
      guide: HttpConversationGuide(base: api),
      input: CartesiaSpeechInput(tokens: tokens, recorder: mic),
      output: output,
    );
  }
  final mic = FileRecorder();
  late final MutedOutput output;
  late final VoiceOnboardingController controller;
}

Future<void> startVoice(WidgetTester t, VoiceRig r) async {
  await qaReset();
  await t.pumpWidget(LifeTwinApp(controller: r.controller));
  await tapText(t, 'Talk with Pip');
  await tapText(t, "Yes, I'll talk");
  await readQuestion(t);
  await tapText(t, 'Not now');
  await waitFor(t, find.textContaining('How old are you?'));
  await settled(t);
}

/// Taps Talk, plays [clip] into the microphone, taps Talk again and waits for [want].
Future<void> talkClip(WidgetTester t, VoiceRig r, String clip, String want) async {
  final c = r.controller;
  await waitFor(t, find.byType(TalkButton));
  r.mic.clip = clip;
  await t.ensureVisible(find.byType(TalkButton).first);
  await t.pump();
  await t.tap(find.byType(TalkButton).first, warnIfMissed: false);
  for (var i = 0; i < 100 && c.phase != VoicePhase.listening; i++) {
    await pumpFor(t, const Duration(milliseconds: 100));
  }
  expect(c.phase, VoicePhase.listening, reason: 'mic never opened: ${c.notice}');
  while (r.mic.clipEndedAt == null && c.phase == VoicePhase.listening) {
    await pumpFor(t, const Duration(milliseconds: 100));
  }
  await pumpFor(t, const Duration(milliseconds: 1500)); // Ink sends the last words
  if (c.phase == VoicePhase.listening) await t.tap(find.byType(TalkButton).first, warnIfMissed: false);
  await waitFor(t, find.textContaining(want), seconds: 40);
  await settled(t);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(qaReset);

  testWidgets('voice happy path: file-fed mic and quick answers, spoken forecast, back, room, forecast again', (
    t,
  ) async {
    final r = VoiceRig();
    await startVoice(t, r);
    expect(r.output.spoken.last, contains('How old are you'));
    await talkClip(t, r, 'born', 'right?');
    expect(r.controller.mascotLine, anyOf(contains('74'), contains('73')));
    await yes(t, 'What sex');
    // By voice the quick answers sit with the controls.
    await tapText(t, 'Female');
    await waitFor(t, find.textContaining('female at birth'));
    await settled(t);
    await yes(t, 'How tall');
    for (final (clip, readBack, next) in [
      ('height', '5 feet 4 inches', 'How much do you weigh'),
      ('weight', '145 pounds', 'How many hours'),
      ('sleep', '7 hours', 'minutes do you exercise'),
      ('exercise', '150 minutes', 'Do you smoke'),
    ]) {
      await talkClip(t, r, clip, readBack);
      await yes(t, next);
    }
    await tapText(t, 'I never smoked');
    await waitFor(t, find.textContaining('never smoked'));
    await settled(t);
    await yes(t, 'alcoholic drinks');
    for (var i = 0; i < 6 && find.text('Continue').evaluate().isEmpty; i++) {
      await tapText(t, 'Skip this question');
      await pumpFor(t, const Duration(milliseconds: 600));
      await settled(t);
    }
    await tapText(t, 'Continue');
    await waitFor(t, find.textContaining('were still living 5 years later'));
    await pumpFor(t, const Duration(seconds: 3)); // the reveal, then Pip says it
    expect(r.output.spoken.last, contains('were still living 5 years later'));
    await tapText(t, 'Back');
    await waitFor(t, find.text('Your room'));
    await tapText(t, 'See my forecast');
    await waitFor(t, find.textContaining('were still living 5 years later'));
    await tapText(t, 'Back');
    await waitFor(t, find.text('Your room'));
  });

  testWidgets('pressing Home while listening: nothing is sent, the same question waits, Talk works', (t) async {
    final r = VoiceRig();
    await startVoice(t, r);
    final c = r.controller;
    final sent = (await qaTurnActions()).length;
    r.mic.clip = 'height';
    await t.tap(find.byType(TalkButton).first, warnIfMissed: false);
    for (var i = 0; i < 100 && c.phase != VoicePhase.listening; i++) {
      await pumpFor(t, const Duration(milliseconds: 100));
    }
    expect(c.phase, VoicePhase.listening);
    await pumpFor(t, const Duration(seconds: 1));
    await qaAction(t, 'background', wait: const Duration(seconds: 8));
    // Back in the app (the silence limit, 8 s, has passed too): nothing was sent.
    await pumpFor(t, const Duration(seconds: 10));
    expect(c.phase, VoicePhase.idle);
    expect(await qaTurnActions(), hasLength(sent), reason: 'half-heard words were sent');
    expect(find.textContaining('How old are you?'), findsWidgets);
    await talkClip(t, r, 'born', 'right?');
  });
}
