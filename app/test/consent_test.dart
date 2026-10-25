import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/http_conversation_guide.dart';

void main() {
  test('provider_consent defaults to false', () async {
    final sent = <Map<String, dynamic>>[];
    final guide = HttpConversationGuide(
      baseUrl: 'http://x',
      client: MockClient((req) async {
        sent.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'state': <String, dynamic>{}, 'message': 'ok', 'complete': false}), 200);
      }),
    );
    await guide.turn(action: 'start');
    await guide.turn(action: 'reply', text: '45');
    expect(sent.map((b) => b['provider_consent']), [false, false]);
  });

  test('nothing reaches the server before the consent answer', () async {
    final guide = FakeConversationGuide();
    final c = VoiceOnboardingController(guide: guide, input: FakeSpeechInput(), output: FakeSpeechOutput());
    addTearDown(c.dispose);
    expect(c.phase, VoicePhase.consent);
    // Apple Health values checked before the talk wait on the phone.
    expect(await c.importHealth({'height_cm': 170}), isTrue);
    expect(guide.calls, isEmpty);
    await c.answerConsent(false);
    expect(guide.calls, isNotEmpty);
    expect(guide.calls.first['action'], 'start');
    expect(guide.calls.every((call) => call['aiHelper'] == false), isTrue);
  });
}
