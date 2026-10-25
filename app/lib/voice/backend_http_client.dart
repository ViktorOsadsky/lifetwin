import 'package:http/http.dart' as http;

/// Public Supabase legacy anon JWT. Provider keys and service-role credentials
/// must never be supplied in app build defines.
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Optional exact HTTPS function base(s), separated by commas. When absent,
/// matching LifeTwin function URLs are taken from API_BASE_URL.
const supabaseGatewayUrl = String.fromEnvironment('SUPABASE_GATEWAY_URL');
const _configuredApiBases = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

/// Adds public gateway authentication only within a configured function path.
/// Direct/local Python requests and unrelated destinations remain unchanged.
class BackendHttpClient extends http.BaseClient {
  BackendHttpClient({
    http.Client? inner,
    this.anonKey = supabaseAnonKey,
    String gatewayUrls = supabaseGatewayUrl,
    String apiUrls = _configuredApiBases,
  }) : _inner = inner ?? http.Client(),
       _gateways = _gatewayBases(gatewayUrls.isEmpty ? apiUrls : gatewayUrls);

  final http.Client _inner;
  final String anonKey;
  final List<Uri> _gateways;

  static List<Uri> _gatewayBases(String urls) {
    final bases = <Uri>[];
    for (final candidate in urls.split(',')) {
      final uri = Uri.tryParse(candidate.trim());
      if (uri == null || !_safeHttps(uri) || uri.hasQuery || uri.hasFragment) {
        continue;
      }
      final path = uri.path.replaceFirst(RegExp(r'/$'), '');
      if (path != '/functions/v1/lifetwin-api') continue;
      bases.add(uri.replace(path: path));
    }
    return bases;
  }

  static bool _safeHttps(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.path.contains('%') &&
      !uri.path.contains(r'\') &&
      !uri.pathSegments.any((part) => part == '.' || part == '..');

  bool _isGateway(Uri uri) =>
      _safeHttps(uri) &&
      _gateways.any(
        (base) =>
            uri.origin == base.origin &&
            (uri.path == base.path || uri.path.startsWith('${base.path}/')),
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (anonKey.isNotEmpty && _isGateway(request.url)) {
      request.headers['Authorization'] = 'Bearer $anonKey';
      request.headers['apikey'] = anonKey;
      // Never carry authentication (or health request bodies) across redirects.
      request.followRedirects = false;
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
