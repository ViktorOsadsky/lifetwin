import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';

/// Public app routing only. Provider/service-role keys never belong here.
class BackendConfig {
  const BackendConfig({
    this.apiUrl = 'http://localhost:8000',
    this.anonKey = '',
    this.gatewayUrl = '',
  });

  final String apiUrl;
  final String anonKey;
  final String gatewayUrl;

  static const _build = BackendConfig(
    apiUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8000',
    ),
    anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    gatewayUrl: String.fromEnvironment('SUPABASE_GATEWAY_URL'),
  );
  static BackendConfig current = _build;

  /// Plain `flutter run` bundles the optional, gitignored public config asset.
  /// An explicit API build define selects build configuration instead.
  static Future<BackendConfig> load({
    AssetBundle? bundle,
    BackendConfig build = _build,
    bool explicitApi = const bool.hasEnvironment('API_BASE_URL'),
  }) async {
    if (explicitApi) return build;
    final String source;
    try {
      source = await (bundle ?? rootBundle).loadString(
        'assets/config/backend.json',
      );
    } on FlutterError {
      return build; // Fresh checkout/local-server development without the asset.
    }
    final json = jsonDecode(source) as Map<String, dynamic>;
    return BackendConfig(
      apiUrl: json['API_BASE_URL'] as String,
      anonKey: const bool.hasEnvironment('SUPABASE_ANON_KEY')
          ? build.anonKey
          : json['SUPABASE_ANON_KEY'] as String? ?? '',
      gatewayUrl: const bool.hasEnvironment('SUPABASE_GATEWAY_URL')
          ? build.gatewayUrl
          : json['SUPABASE_GATEWAY_URL'] as String? ?? '',
    );
  }
}
