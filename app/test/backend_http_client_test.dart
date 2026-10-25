import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/voice/backend_http_client.dart';

const _gateway = 'https://example.supabase.co/functions/v1/lifetwin-api';
const _publicKey = 'public-legacy-anon-test-jwt';

void main() {
  test(
    'authenticates health and POST requests at the configured gateway',
    () async {
      final seen = <http.Request>[];
      final client = BackendHttpClient(
        inner: MockClient((request) async {
          seen.add(request);
          return http.Response('{}', 200);
        }),
        anonKey: _publicKey,
        apiUrls: 'http://localhost:8000,$_gateway/',
      );
      await client.get(Uri.parse('$_gateway/health'));
      await client.post(
        Uri.parse('$_gateway/api/conversation'),
        headers: {'content-type': 'application/json'},
        body: '{"synthetic":true}',
      );
      for (final request in seen) {
        expect(request.headers['authorization'], 'Bearer $_publicKey');
        expect(request.headers['apikey'], _publicKey);
        expect(request.followRedirects, isFalse);
      }
      expect(seen.last.body, '{"synthetic":true}');
      expect(seen.last.headers['content-type'], 'application/json');
      client.close();
    },
  );

  test(
    'explicit gateway configuration takes precedence over API candidates',
    () async {
      final seen = <http.Request>[];
      final client = BackendHttpClient(
        inner: MockClient((request) async {
          seen.add(request);
          return http.Response('', 200);
        }),
        anonKey: _publicKey,
        gatewayUrls: _gateway,
        apiUrls: 'https://different.supabase.co/functions/v1/lifetwin-api',
      );
      await client.get(Uri.parse(_gateway));
      await client.get(
        Uri.parse(
          'https://different.supabase.co/functions/v1/lifetwin-api/health',
        ),
      );
      expect(seen.first.headers['apikey'], _publicKey);
      expect(seen.last.headers.containsKey('apikey'), isFalse);
      client.close();
    },
  );

  for (final target in [
    'http://localhost:8000/api/voice/token',
    'http://example.supabase.co/functions/v1/lifetwin-api/health',
    'https://other.supabase.co/functions/v1/lifetwin-api/health',
    'https://example.supabase.co.evil.test/functions/v1/lifetwin-api/health',
    'https://example.supabase.co:8443/functions/v1/lifetwin-api/health',
    'https://example.supabase.co/functions/v1/lifetwin-api-spoof/health',
    'https://example.supabase.co/functions/v1/another-function',
    'https://example.supabase.co/auth/v1/token',
    'https://user@example.supabase.co/functions/v1/lifetwin-api/health',
    'https://example.supabase.co/functions/v1/lifetwin-api/%2e%2e/another-function',
    'https://example.supabase.co/functions/v1/lifetwin-api/api%2fprivate',
  ]) {
    test('does not send gateway headers to $target', () async {
      final client = BackendHttpClient(
        inner: MockClient((request) async {
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('apikey'), isFalse);
          expect(request.followRedirects, isTrue);
          return http.Response('', 200);
        }),
        anonKey: _publicKey,
        gatewayUrls: _gateway,
      );
      await client.get(Uri.parse(target));
      client.close();
    });
  }

  test('empty public key preserves local and direct API behavior', () async {
    final client = BackendHttpClient(
      inner: MockClient((request) async {
        expect(request.headers['authorization'], 'existing-local-auth');
        expect(request.headers.containsKey('apikey'), isFalse);
        expect(request.followRedirects, isTrue);
        return http.Response('', 200);
      }),
      anonKey: '',
      gatewayUrls: _gateway,
    );
    await client.get(
      Uri.parse('$_gateway/health'),
      headers: {'authorization': 'existing-local-auth'},
    );
    client.close();
  });

  test('invalid configured base cannot broaden authentication scope', () async {
    final client = BackendHttpClient(
      inner: MockClient((request) async {
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('apikey'), isFalse);
        return http.Response('', 200);
      }),
      anonKey: _publicKey,
      gatewayUrls: 'https://example.supabase.co, $_gateway?redirect=other',
    );
    await client.get(Uri.parse('$_gateway/health'));
    client.close();
  });

  test('closing the wrapper closes the underlying client', () {
    final inner = _CloseTrackingClient();
    BackendHttpClient(inner: inner).close();
    expect(inner.closed, isTrue);
  });

  test('all default backend factories use the scoped shared client', () {
    for (final file in [
      'voice/api_base.dart',
      'voice/http_conversation_guide.dart',
      'voice/voice_token.dart',
      'voice/voice_log.dart',
      'documents/document_extract.dart',
      'wellness/coach_client.dart',
      'experiment/recommendations.dart',
      'checkin/change_chat.dart',
      'checkin/consents.dart',
      'checkin/checkin_client.dart',
    ]) {
      final source = File('lib/$file').readAsStringSync();
      expect(source, contains('BackendHttpClient()'), reason: file);
      expect(source, isNot(contains('http.Client()')), reason: file);
    }
  });
}

class _CloseTrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}
