import 'package:flutter/services.dart' show AssetBundle;
import 'package:lifetwin_on_device/lifetwin_on_device.dart';

import 'profile_mapping.dart';

/// Typed reading of one `LifeTwinEngine.assess()` result. The raw map is kept as it
/// came, so `profile_used` and `input_provenance` are preserved for the UI.
class TwinAssessment {
  TwinAssessment(this.raw)
    : survival = Map<String, dynamic>.from(raw['survival'] as Map? ?? const {}),
      invalidInput = null;

  /// A profile value the package refused (`FormatException`): ask the person to correct
  /// it. Never shown as a number.
  TwinAssessment.invalid(String message, {this.invalidInput})
    : raw = const {},
      survival = {'status': 'invalid_input', 'message': message};

  final Map<String, dynamic> raw;
  final Map<String, dynamic> survival;

  /// The model input the package refused, by its package name, when it could be told.
  final String? invalidInput;

  /// `available`, `missing_inputs`, `unsupported_age`, `unsupported_profile`, or the
  /// app's own `invalid_input`.
  String get status => survival['status'] as String? ?? 'invalid_input';
  bool get available => status == 'available';

  /// The package's status message, shown instead of a number when not [available].
  String? get message => survival['message'] as String?;

  /// Package input names (e.g. `sedentary_min_day`, `bmi`) still needed.
  List<String> get missingInputs => [for (final m in survival['missing_inputs'] as List? ?? const []) '$m'];
  List<String> get supportIssues => [for (final m in survival['support_issues'] as List? ?? const []) '$m'];

  String get modelVersion => survival['model_version'] as String? ?? '';
  String? get interpretation => survival['interpretation'] as String?;

  /// Cumulative survival 0..1 through years 1–5; empty unless [available].
  Map<int, double> get survivalByYear => yearMap(survival['survival_probabilities']);

  /// The same in percent, as the package gives it; empty unless [available].
  Map<int, double> get percentByYear => yearMap(survival['survival_percent_by_year']);

  Map<String, dynamic> get profileUsed => Map<String, dynamic>.from(raw['profile_used'] as Map? ?? const {});
  Map<String, dynamic> get inputProvenance => Map<String, dynamic>.from(raw['input_provenance'] as Map? ?? const {});

  /// `profile_snapshot`, `daily_logs` or `weekly_summaries`.
  String get source => inputProvenance['source'] as String? ?? 'profile_snapshot';

  Map<String, dynamic> get avatar => Map<String, dynamic>.from(raw['avatar'] as Map? ?? const {});
  List<String> get strengths => [for (final s in avatar['strengths'] as List? ?? const []) '$s'];
  List<String> get opportunities => [for (final s in avatar['opportunities'] as List? ?? const []) '$s'];

  /// `steady`, `explore_changes` or `needs_input`.
  String get wellnessState => avatar['wellness_state'] as String? ?? 'needs_input';

  List<WellnessCard> get wellnessCards => [
    for (final c in raw['wellness_cards'] as List? ?? const [])
      if (c is Map) WellnessCard.fromJson(Map<String, dynamic>.from(c)),
  ];

  /// "Modeled survival of similar people" (the package's display rule).
  static const survivalTitle = 'Modeled survival of similar people';

  /// "Modeled difference between profiles".
  static const scenarioTitle = 'Modeled difference between profiles';

  /// `{'1': x, …}` → `{1: x, …}`.
  static Map<int, double> yearMap(Object? m) => {
    if (m is Map)
      for (final e in m.entries)
        if (int.tryParse('${e.key}') != null && e.value is num) int.parse('${e.key}'): (e.value as num).toDouble(),
  };
}

/// A public-health guidance card from the package, shown beside the twin with its
/// source link. Not derived from the survival model.
class WellnessCard {
  const WellnessCard({
    required this.id,
    required this.level,
    required this.title,
    required this.message,
    required this.sourceUrl,
  });

  factory WellnessCard.fromJson(Map<String, dynamic> j) => WellnessCard(
    id: '${j['id']}',
    level: '${j['level']}',
    title: '${j['title']}',
    message: '${j['message']}',
    sourceUrl: '${j['source_url']}',
  );

  /// `smoking`, `activity`, `sleep`, `sitting`, `sitting_trend`, `bmi`, `adult_guidance_scope`.
  final String id;

  /// `strength`, `opportunity` or `info`.
  final String level;
  final String title;
  final String message;
  final String sourceUrl;
}

/// The model, loaded once at startup, and the one place the app calls it.
class TwinModelService {
  TwinModelService(this.engine);

  final LifeTwinEngine engine;

  static Future<TwinModelService> load({AssetBundle? bundle}) async =>
      TwinModelService(LifeTwinEngine(await loadLifeTwinModel(bundle: bundle)));

  String get modelVersion => engine.model.spec['model_version'] as String;

  /// Assesses the confirmed app profile. [window] is `{'daily_logs': [...]}` or
  /// `{'weekly_summaries': [...]}` (see twin_history.dart), or empty for a snapshot.
  TwinAssessment assess(Map<String, dynamic> appProfile, {Map<String, dynamic> window = const {}, DateTime? asOf}) =>
      assessModel(toModelProfile(appProfile), window: window, asOf: asOf);

  /// Assesses an already mapped model profile.
  TwinAssessment assessModel(
    Map<String, dynamic> modelProfile, {
    Map<String, dynamic> window = const {},
    DateTime? asOf,
  }) {
    final request = <String, dynamic>{'profile': modelProfile, ...window};
    if (asOf != null) request['as_of_date'] = isoDate(asOf);
    try {
      return TwinAssessment(engine.assess(request));
    } on FormatException catch (e) {
      return invalidAssessment(e);
    }
  }
}

/// A plain "please check this answer" for a value the package refused.
TwinAssessment invalidAssessment(FormatException e) {
  final text = e.message;
  final key = modelInputs.followedBy(['height_cm', 'weight_kg']).where(text.contains).firstOrNull;
  final label = switch (key) {
    null => null,
    'height_cm' || 'weight_kg' => 'height and weight',
    _ => modelInputLabels[key],
  };
  return TwinAssessment.invalid(
    label == null
        ? 'One of your answers is outside what the model can read. Please check your answers.'
        : 'Your answer for $label is outside what the model can read. Please check it.',
    invalidInput: key == 'height_cm' || key == 'weight_kg' ? 'bmi' : key,
  );
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The calendar day of [d], as a UTC midnight (the package's date arithmetic).
DateTime dayOf(DateTime d) => DateTime.utc(d.year, d.month, d.day);
