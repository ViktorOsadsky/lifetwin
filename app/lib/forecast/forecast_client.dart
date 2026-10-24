import '../twin/profile_mapping.dart';
import '../twin/twin_model.dart';
import '../twin/twin_repository.dart';

/// One on-device forecast, read for the forecast screens from a [TwinAssessment].
/// Survival values are 0 to 1. A number exists only when [supported]
/// (`survival.status == 'available'`).
class Forecast {
  const Forecast({
    required this.supported,
    required this.survival,
    required this.maxHorizonYears,
    required this.modelVersion,
    this.status = 'available',
    this.reason,
    this.missingInputs = const [],
    this.limitations = const [],
    this.curve = const [],
    this.assessment,
  });

  factory Forecast.fromAssessment(TwinAssessment a) {
    final survival = a.available ? a.survivalByYear : const <int, double>{};
    final max = survival.isEmpty ? 5 : survival.keys.reduce((x, y) => x > y ? x : y);
    return Forecast(
      supported: a.available,
      status: a.status,
      survival: survival,
      maxHorizonYears: max,
      modelVersion: a.modelVersion,
      reason: a.available ? null : a.message,
      missingInputs: a.missingInputs,
      limitations: [?a.interpretation],
      // Year 0 is everyone; then the five yearly points the model returns.
      curve: survival.isEmpty
          ? const []
          : [
              (years: 0.0, survival: 1.0),
              for (final y in (survival.keys.toList()..sort())) (years: y.toDouble(), survival: survival[y]!),
            ],
      assessment: a,
    );
  }

  final bool supported;

  /// `available`, `missing_inputs`, `unsupported_age`, `unsupported_profile`, `invalid_input`.
  final String status;

  /// Years (1–5) to the share of similar people still living then.
  final Map<int, double> survival;
  final int maxHorizonYears;
  final String modelVersion;

  /// The package's status message when not [supported].
  final String? reason;

  /// Package input names still needed (status `missing_inputs`).
  final List<String> missingInputs;

  /// Plain words for [missingInputs].
  List<String> get missingLabels => [for (final m in missingInputs) modelInputLabels[m] ?? m];
  final List<String> limitations;

  /// The yearly curve: (0, 1.0), then years 1–5.
  final List<({double years, double survival})> curve;

  /// The full result (wellness cards, avatar, `profile_used`, `input_provenance`).
  final TwinAssessment? assessment;

  /// "about 93": out of 100 people, at a supported horizon.
  int outOf100(int years) => (100 * (survival[years] ?? 0)).round();
}

abstract class ForecastClient {
  /// Throws [ForecastFailure] when there is no usable answer.
  Future<Forecast> predict(Map<String, dynamic> confirmedProfile);
}

class ForecastFailure implements Exception {
  const ForecastFailure(this.message, {this.plain, this.modelMissing = false});
  final String message;

  /// The model could not be loaded: "still learning".
  final bool modelMissing;

  /// A message that is safe and useful to show.
  final String? plain;
  @override
  String toString() => 'ForecastFailure($message)';
}

/// The forecast on the phone: `LifeTwinEngine.assess()` with the phone's history. No
/// network. (POST /api/predict is no longer called; the server route stays for now.)
class OnDeviceForecastClient implements ForecastClient {
  OnDeviceForecastClient(this.repository);

  final Future<TwinRepository> repository;

  @override
  Future<Forecast> predict(Map<String, dynamic> confirmedProfile) async {
    final TwinRepository repo;
    try {
      repo = await repository;
    } catch (e) {
      throw ForecastFailure('model failed to load: $e', modelMissing: true);
    }
    return Forecast.fromAssessment(repo.assess(confirmedProfile));
  }
}
