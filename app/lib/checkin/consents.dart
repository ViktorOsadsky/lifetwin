import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../voice/api_base.dart';

/// The outside AI provider, from `GET /api/capabilities` -> `personalize`. The name is never
/// hard-coded in the app: the screens say [displayName], so changing provider changes no copy.
@immutable
class AiProvider {
  const AiProvider({required this.id, required this.displayName, required this.configured});

  final String id;
  final String displayName;

  /// False: personal suggestions are not offered and no consent is asked.
  final bool configured;

  static AiProvider? fromCapabilities(Object? json) {
    final p = json is Map ? json['personalize'] : null;
    if (p is! Map) return null;
    final id = p['provider'], name = p['display_name'];
    if (id is! String || name is! String || id.isEmpty || name.isEmpty) return null;
    return AiProvider(id: id, displayName: name, configured: p['configured'] == true);
  }
}

abstract class CapabilitiesClient {
  /// Null when the server has no (usable) `personalize` block or cannot be reached: nothing is
  /// offered and nothing is sent.
  Future<AiProvider?> personalize();
}

/// STUB-FLAG: `/api/capabilities` is not on main yet (it is in the integration branch). Until it
/// lands the app falls back to "no provider": the consent is not shown and nothing goes out.
const useServerCapabilities = true;

class HttpCapabilitiesClient implements CapabilitiesClient {
  HttpCapabilitiesClient({http.Client? client, ApiBase? base})
    : _client = client ?? http.Client(),
      base = base ?? ApiBase();
  final http.Client _client;
  final ApiBase base;

  @override
  Future<AiProvider?> personalize() async {
    if (!useServerCapabilities) return null;
    try {
      final url = await base.url();
      final r = await _client.get(Uri.parse('$url/api/capabilities')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      return AiProvider.fromCapabilities(jsonDecode(utf8.decode(r.bodyBytes)));
    } catch (_) {
      return null;
    }
  }
}

/// Where the persisted consent lives. STUB: in memory until the engine session adds a key for
/// `outside_ai_consent` to the protected phone store (lib/twin is theirs). It is never sent to the
/// server as a setting; it only gates what the app sends.
abstract class ConsentBackend {
  Future<String?> read();
  Future<void> write(String text);
  Future<void> delete();
}

class MemoryConsentBackend implements ConsentBackend {
  String? text;
  @override
  Future<String?> read() async => text;
  @override
  Future<void> write(String t) async => text = t;
  @override
  Future<void> delete() async => text = null;
}

/// The three separate AI consents (never bundled with each other, with Apple Health or with
/// notifications; nothing is pre-selected):
///
/// 1. Per-document yes: a per-request flag on document extraction (not held here).
/// 2. AI helper ([aiHelper]): held in memory for the conversation, sent as `provider_consent`.
/// 3. Personal suggestions ([outsideAi]): a persisted toggle on the phone, keyed by provider id
///    (`{"muse": true}`), sent with each request. A new provider id has no entry, so it asks again.
///
/// Memory (`memory_consent`) is a fourth, separate choice and lives in `TwinRepository`.
/// Nothing here promises anything about a provider's own retention.
class ConsentStore extends ChangeNotifier {
  ConsentStore([ConsentBackend? backend]) : _backend = backend ?? MemoryConsentBackend();

  final ConsentBackend _backend;
  Map<String, bool> _outsideAi = {};
  bool _aiHelper = false;

  static Future<ConsentStore> open([ConsentBackend? backend]) async {
    final s = ConsentStore(backend);
    final text = await s._backend.read();
    if (text != null) {
      try {
        final j = jsonDecode(text);
        if (j is Map) {
          s._outsideAi = {
            for (final e in (j['outside_ai_consent'] as Map? ?? const {}).entries)
              if (e.value is bool) '${e.key}': e.value as bool,
          };
        }
      } on FormatException {
        // An unreadable file is not guessed at: everything stays off.
      }
    }
    return s;
  }

  /// The AI helper for this conversation only.
  bool get aiHelper => _aiHelper;

  void setAiHelper(bool on) {
    _aiHelper = on;
    notifyListeners();
  }

  /// True, false, or null when this provider has never been asked.
  bool? outsideAiFor(String providerId) => _outsideAi[providerId];

  /// Personal suggestions may use outside AI only with a yes for this very provider.
  bool mayShare(AiProvider? p) => p != null && p.configured && _outsideAi[p.id] == true;

  /// Ask (or ask again) when the provider is set up and this provider id has no answer.
  bool needsAnswer(AiProvider? p) => p != null && p.configured && !_outsideAi.containsKey(p.id);

  Future<void> setOutsideAi(String providerId, bool on) async {
    _outsideAi = {..._outsideAi, providerId: on};
    notifyListeners();
    await _backend.write(jsonEncode({'outside_ai_consent': _outsideAi}));
  }

  /// "Delete my data": every consent goes, so the app asks again.
  Future<void> clear() async {
    _outsideAi = {};
    _aiHelper = false;
    notifyListeners();
    await _backend.delete();
  }
}
