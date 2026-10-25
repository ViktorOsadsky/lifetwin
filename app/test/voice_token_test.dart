import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/voice/voice_token.dart';

String _body(int n) => jsonEncode({
  'token': 'tok$n',
  'expires_in': 300,
  'cartesia_version': '2025-04-16',
  'stt': {'model': 'ink-whisper'},
  'tts': {'model': 'sonic-2', 'voice_id': 'v'},
});

void main() {
  test('prefetch mints once; a Talk right after shares it instead of waiting on a second mint', () {
    fakeAsync((fa) {
      var mints = 0;
      final p = VoiceTokenProvider(
        baseUrl: 'http://x',
        client: MockClient((_) async => http.Response(_body(++mints), 200)),
        now: () => DateTime(2026).add(fa.elapsed),
      );
      p.prefetch().ignore();
      String? got;
      p.get().then((t) => got = t.token); // starts while the prefetch is still in flight
      fa.flushMicrotasks();
      expect(mints, 1);
      expect(got, 'tok1');
      p.get().then((t) => got = t.token);
      fa.flushMicrotasks();
      expect(mints, 1, reason: 'a fresh token is reused');
    });
  });

  test('refreshes in the background with 60 s left while voice is in use, then stops when idle', () {
    fakeAsync((fa) {
      var mints = 0;
      final p = VoiceTokenProvider(
        baseUrl: 'http://x',
        client: MockClient((_) async => http.Response(_body(++mints), 200)),
        now: () => DateTime(2026).add(fa.elapsed),
      );
      p.prefetch().ignore();
      fa.flushMicrotasks();
      expect(mints, 1);
      fa.elapse(const Duration(seconds: 239));
      expect(mints, 1);
      fa.elapse(const Duration(seconds: 1)); // 60 s before expiry
      expect(mints, 2);
      String? got;
      p.get().then((t) => got = t.token); // no wait: the refreshed token is already there
      fa.flushMicrotasks();
      expect(got, 'tok2');
      expect(mints, 2);
      // No more voice use: the refresh after this one lets the token lapse.
      fa.elapse(const Duration(minutes: 20));
      expect(mints, 3);
    });
  });

  test('a 503 is VoiceUnavailableException and the next get tries again', () async {
    var code = 503;
    final p = VoiceTokenProvider(
      baseUrl: 'http://x',
      client: MockClient((_) async => http.Response(code == 200 ? _body(1) : '', code)),
    );
    await expectLater(p.get(), throwsA(isA<VoiceUnavailableException>()));
    code = 200;
    expect((await p.get()).token, 'tok1');
  });
}
