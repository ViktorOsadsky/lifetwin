import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/voice/http_conversation_guide.dart';
import 'package:lifesim/voice/speech.dart';

void main() {
  test('a 4xx answer becomes GuideRejected with the server message', () async {
    final guide = HttpConversationGuide(
      baseUrl: 'http://x',
      client: MockClient((_) async => http.Response(
          jsonEncode({'status': 'error', 'code': 'invalid_request', 'message': 'Please check these answers: height.'}), 422)),
    );
    await expectLater(
      guide.turn(action: 'import', values: {'height_cm': 17300}),
      throwsA(isA<GuideRejected>().having((e) => e.message, 'message', 'Please check these answers: height.')),
    );
  });

  test('import sends values and the AI-helper choice', () async {
    late Map<String, dynamic> sent;
    final guide = HttpConversationGuide(
      baseUrl: 'http://x',
      client: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'state': {'phase': 'asking'}, 'message': 'ok', 'complete': false}), 200);
      }),
    );
    await guide.turn(action: 'import', values: {'weight_kg': 68.0}, aiHelper: true);
    expect(sent['values'], {'weight_kg': 68.0});
    expect(sent['provider_consent'], isTrue);
  });

  test('a 5xx answer is a plain failure (retry may help)', () async {
    final guide = HttpConversationGuide(baseUrl: 'http://x', client: MockClient((_) async => http.Response('', 503)));
    await expectLater(guide.turn(action: 'start'), throwsA(isA<GuideFailure>().having((e) => e is GuideRejected, 'rejected', false)));
  });
}
