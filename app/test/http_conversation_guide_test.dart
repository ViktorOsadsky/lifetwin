import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/voice/http_conversation_guide.dart';
import 'package:lifesim/voice/speech.dart';

void main() {
  test('a 4xx answer becomes GuideRejected with the server message', () async {
    final guide = HttpConversationGuide(
      baseUrl: 'http://x',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'status': 'error', 'code': 'invalid_request', 'message': 'Please check these answers: height.'}),
          422,
        ),
      ),
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
        return http.Response(
          jsonEncode({
            'state': {'phase': 'asking'},
            'message': 'ok',
            'complete': false,
          }),
          200,
        );
      }),
    );
    await guide.turn(action: 'import', values: {'weight_kg': 68.0}, aiHelper: true);
    expect(sent['values'], {'weight_kg': 68.0});
    expect(sent['provider_consent'], isTrue);
  });

  test('a 5xx answer is a plain failure (retry may help)', () async {
    final guide = HttpConversationGuide(baseUrl: 'http://x', client: MockClient((_) async => http.Response('', 503)));
    await expectLater(
      guide.turn(action: 'start'),
      throwsA(isA<GuideFailure>().having((e) => e is GuideRejected, 'rejected', false)),
    );
  });

  test('with several addresses, uses the first one that answers and skips one that hangs', () async {
    final hang = Completer<http.Response>();
    final seen = <String>[];
    final client = MockClient((req) {
      seen.add('${req.method} ${req.url}');
      if (req.url.host == 'wifi') return hang.future; // never answers
      if (req.url.path == '/health') return Future.value(http.Response('{"status":"ok"}', 200));
      return Future.value(http.Response(jsonEncode({'state': {}, 'message': 'How old are you?'}), 200));
    });
    final guide = HttpConversationGuide(baseUrl: 'http://wifi:8000, http://usb:8000', client: client);
    final t = await guide.turn(action: 'start');
    expect(t.message, 'How old are you?');
    expect(seen.last, 'POST http://usb:8000/api/onboarding/turn');
    await guide.turn(action: 'start');
    expect(seen.where((s) => s.endsWith('/health')), hasLength(2)); // checked once, then remembered
  });

  test('when no address answers it fails, and tries again next time', () async {
    var up = false;
    final client = MockClient((req) async {
      if (!up) throw const SocketException('unreachable');
      if (req.url.path == '/health') return http.Response('ok', 200);
      return http.Response(jsonEncode({'state': {}, 'message': 'Hi'}), 200);
    });
    final guide = HttpConversationGuide(baseUrl: 'http://a,http://b', client: client);
    await expectLater(guide.turn(action: 'start'), throwsA(isA<GuideFailure>()));
    up = true;
    expect((await guide.turn(action: 'start')).message, 'Hi');
  });
}
