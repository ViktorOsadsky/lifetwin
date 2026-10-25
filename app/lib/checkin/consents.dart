import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../twin/twin_repository.dart';
import '../voice/api_base.dart';

/// The outside AI provider, from `GET /api/capabilities` -> `personalize`. The name is never
/// hard-coded in the app: the screens say [displayName], so changing provider changes no copy.
@immutable
class AiProvider {
  const AiProvider({
    required this.id,
    required this.displayName,
    required this.configured,
    this.company,
    this.mayTrainOnContent = false,
  });

  final String id;
  final String displayName;

  /// False: personal suggestions are not offered and no consent is asked.
  final bool configured;

  /// The company behind the provider, from `personalize.company`; null when the server does not say.
  final String? company;

  /// `personalize.may_train_on_content`: the provider may use what is shared to improve its AI.
  /// False when missing: nothing is claimed.
  final bool mayTrainOnContent;

  /// Shown beside every outside-AI Yes button when [mayTrainOnContent] is true and the company is known.
  String? get trainingLine =>
      mayTrainOnContent && company != null ? '$company may use what you share to improve its AI.' : null;

  static AiProvider? fromCapabilities(Object? json) {
    final p = json is Map ? json['personalize'] : null;
    if (p is! Map) return null;
    final id = p['provider'], name = p['display_name'];
    if (id is! String || name is! String || id.isEmpty || name.isEmpty) return null;
    final company = p['company'];
    return AiProvider(
      id: id,
      displayName: name,
      configured: p['configured'] == true,
      company: company is String && company.isNotEmpty ? company : null,
      mayTrainOnContent: p['may_train_on_content'] == true,
    );
  }
}

abstract class CapabilitiesClient {
  /// Null when the server has no (usable) `personalize` block or cannot be reached: nothing is
  /// offered and nothing is sent.
  Future<AiProvider?> personalize();
}

class HttpCapabilitiesClient implements CapabilitiesClient {
  HttpCapabilitiesClient({http.Client? client, ApiBase? base})
    : _client = client ?? http.Client(),
      base = base ?? ApiBase();
  final http.Client _client;
  final ApiBase base;

  @override
  Future<AiProvider?> personalize() async {
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

/// The AI consents, kept apart (never bundled with each other, with Apple Health or with
/// notifications; nothing is pre-selected):
///
/// 1. Per-document yes: a per-request flag on document extraction (not held here).
/// 2. AI helper ([aiHelper]): held in memory for the conversation, sent as `provider_consent`.
/// 3. Personal suggestions: the phone's persisted consent on [TwinRepository]
///    (`outsideAiConsent`, `outsideAiProvider`, `setOutsideAiConsent`), off by default and after Delete
///    my data. It covers only the provider it was given for, so a new provider asks again.
///
/// Memory (`memory_consent`) is a fourth, separate choice and lives in `TwinRepository`. Nothing here
/// promises anything about a provider's own retention.
class ConsentStore extends ChangeNotifier {
  ConsentStore(this.repository) {
    repository.addListener(notifyListeners);
  }

  final TwinRepository repository;
  bool _aiHelper = false;

  @override
  void dispose() {
    repository.removeListener(notifyListeners);
    super.dispose();
  }

  /// The AI helper for this conversation only.
  bool get aiHelper => _aiHelper;

  void setAiHelper(bool on) {
    _aiHelper = on;
    notifyListeners();
  }

  /// True or false when this provider has been asked, null when it has not.
  bool? outsideAiFor(String providerId) =>
      repository.outsideAiProvider == providerId ? repository.outsideAiConsent : null;

  /// Personal suggestions may use outside AI only with a yes for this very provider.
  bool mayShare(AiProvider? p) => p != null && p.configured && repository.outsideAiConsentFor(p.id).isNotEmpty;

  /// Ask (or ask again) when the provider is set up and this provider id has no answer.
  bool needsAnswer(AiProvider? p) => p != null && p.configured && repository.outsideAiProvider != p.id;

  Future<void> setOutsideAi(String providerId, bool on) => repository.setOutsideAiConsent(on, provider: providerId);
}
