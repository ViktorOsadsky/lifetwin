/// The boundary to the health score, which another track defines. Placeholder
/// only: [PendingHealthScore] always answers "not ready".
///
/// Owner ruling: a habit tick never counts toward the score, so the input has
/// no habits in it. Behaviour shows through the twin's measured inputs (sleep
/// hours, activity, sitting, smoking) instead. Health estimates need age 18+.
library;

class HealthScoreInput {
  const HealthScoreInput({required this.profile, required this.asOf});

  /// The confirmed profile, read only.
  final Map<String, Object?> profile;

  /// Phone-local day, YYYY-MM-DD.
  final String asOf;

  int? get age => (profile['age'] as num?)?.toInt();
}

enum HealthScoreStatus { available, notReady, missingInputs, ageNotSupported }

class HealthScoreResult {
  const HealthScoreResult({required this.status, required this.explanation, this.value});
  final HealthScoreStatus status;
  final num? value;
  final String explanation;
}

abstract class HealthScoreSource {
  Future<HealthScoreResult> score(HealthScoreInput input);
}

class PendingHealthScore implements HealthScoreSource {
  const PendingHealthScore();

  @override
  Future<HealthScoreResult> score(HealthScoreInput input) async {
    final age = input.age;
    if (age != null && age < 18) {
      return const HealthScoreResult(
        status: HealthScoreStatus.ageNotSupported,
        explanation: 'Health estimates are for adults.',
      );
    }
    return const HealthScoreResult(
      status: HealthScoreStatus.notReady,
      explanation: 'The health score is not ready yet.',
    );
  }
}
