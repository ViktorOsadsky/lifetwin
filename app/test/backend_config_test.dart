import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/backend_config.dart';
import 'package:lifesim/voice/backend_http_client.dart';

const _gateway = 'https://example.supabase.co/functions/v1/lifetwin-api';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'plain launch loads the public asset for API routing and scoped auth',
    () async {
      final previous = BackendConfig.current;
      addTearDown(() => BackendConfig.current = previous);
      BackendConfig.current = await BackendConfig.load(
        bundle: _Bundle(
          jsonEncode({
            'API_BASE_URL': _gateway,
            'SUPABASE_ANON_KEY': 'public-test-key',
          }),
        ),
        explicitApi: false,
      );
      expect(await ApiBase().url(), _gateway);
      final client = BackendHttpClient(
        inner: MockClient((r) async {
          if (r.url.host == 'example.supabase.co') {
            expect(r.headers['authorization'], 'Bearer public-test-key');
            expect(r.headers['apikey'], 'public-test-key');
            expect(r.followRedirects, isFalse);
          } else {
            expect(r.headers.containsKey('authorization'), isFalse);
            expect(r.headers.containsKey('apikey'), isFalse);
          }
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await client.get(Uri.parse('$_gateway/health'));
      await client.get(Uri.parse('http://localhost:8000/health'));
    },
  );

  test(
    'explicit API build configuration wins without loading the local asset',
    () async {
      const local = BackendConfig(apiUrl: 'http://localhost:8123');
      final result = await BackendConfig.load(
        bundle: _Bundle('invalid JSON'),
        build: local,
        explicitApi: true,
      );
      expect(identical(result, local), isTrue);
      expect(result.anonKey, isEmpty);
    },
  );

  test('missing optional asset preserves local-server defaults', () async {
    final result = await BackendConfig.load(
      bundle: _Bundle(null),
      explicitApi: false,
    );
    expect(result.apiUrl, 'http://localhost:8000');
    expect(result.anonKey, isEmpty);
  });

  test(
    'optional gateway scope is loaded with the public API settings',
    () async {
      final result = await BackendConfig.load(
        bundle: _Bundle(
          jsonEncode({
            'API_BASE_URL': 'http://localhost:8000,$_gateway',
            'SUPABASE_ANON_KEY': 'public-test-key',
            'SUPABASE_GATEWAY_URL': _gateway,
          }),
        ),
        explicitApi: false,
      );
      expect(result.gatewayUrl, _gateway);
    },
  );
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.source);
  final String? source;

  @override
  Future<ByteData> load(String key) async {
    expect(key, 'assets/config/backend.json');
    if (source == null) throw FlutterError('Asset absent');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source!)));
  }
}
