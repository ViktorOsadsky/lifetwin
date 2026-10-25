import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'twin_model.dart';

/// Lever ids. Each is the package's input name, except [weightKg], which moves `bmi`
/// through the person's own height.
abstract final class LeverId {
  static const sleepHours = 'sleep_hours';
  static const moderate = 'moderate_recreation_min_week';
  static const vigorous = 'vigorous_recreation_min_week';
  static const sitting = 'sedentary_min_day';
  static const smoking = 'smoking_status';
  static const weightKg = 'weight_kg';
}

/// Why a lever is not offered, or a moved lever is "Not counted".
abstract final class LeverReason {
  /// The model input is unknown, so there is nothing to move from (see [ExperimentLever.missingInput]).
  static const missingInput = 'missing_input';

  /// Smoking: only "smokes now → quit" is offered.
  static const notASmoker = 'not_current_smoker';

  /// Sleep: only short sleepers (under 7 h) are offered more sleep.
  static const notShortSleeper = 'not_short_sleeper';

  /// Exercise already at the top of the lever's range.
  static const alreadyHigh = 'already_high';

  /// Sitting already under 90 min a day.
  static const alreadyLow = 'already_low';

  /// Weight is never a favourable lever in this model (docs/model-sensitivity.md: BMI −1
  /// helps 0% of profiles; below BMI 23 lower is fitted as worse; above 27 the slope is near
  /// zero and slightly inverse). Always unsupported.
  static const weightNotALever = 'weight_not_a_lever';

  /// The model's response to this change runs against public-health guidance. Shown as
  /// "Not counted", no number.
  static const counterIntuitive = 'counter_intuitive';
}

const _reasonText = {
  LeverReason.missingInput: 'We need this answer before you can try changing it.',
  LeverReason.notASmoker: 'Only quitting smoking is offered here.',
  LeverReason.notShortSleeper: 'More sleep is only tried for people sleeping under 7 hours.',
  LeverReason.alreadyHigh: 'You are already at the top of this range.',
  LeverReason.alreadyLow: 'Your sitting time is already low.',
  LeverReason.weightNotALever:
      'This model cannot show a benefit from a weight change: below a BMI of 23 it links '
      'lower weight with lower survival (likely illness), and above 27 its weight link is '
      'near zero. So weight is not counted.',
  LeverReason.counterIntuitive:
      'The model’s answer for this change runs against health guidance, so it is not counted.',
};

/// A choice for a lever with fixed values (smoking).
class LeverOption {
  const LeverOption(this.value, this.label);
  final double value;
  final String label;
}

/// One thing the person can try changing. Numbers are in the lever's [unit].
class ExperimentLever {
  ExperimentLever._({
    required this.id,
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    required this.step,
    required this.current,
    this.options,
    this.supported = true,
    this.reason,
    this.caveat,
    this.missingInput,
  }) : value = current;

  final String id;
  final String label;

  /// `h/night`, `min/week`, `min/day`, `kg`, or `choice` (see [options]).
  final String unit;
  final double min;
  final double max;
  final double step;

  /// The person's value now (from the assessment's `profile_used`); null when unknown.
  final double? current;

  /// The tried value; equals [current] until set.
  double? value;

  /// Smoking only: 2 "Smokes now" (current) and 1 "Quit" (former).
  final List<LeverOption>? options;

  /// False when the lever is not offered; [reason] says why (a [LeverReason]).
  final bool supported;
  final String? reason;
  String? get reasonText => _reasonText[reason];

  /// Always-shown note (weight: the model card's BMI caveat).
  final String? caveat;

  /// When [reason] is [LeverReason.missingInput]: the package's input name.
  final String? missingInput;

  bool get changed => supported && value != null && current != null && value != current;

  /// Snaps to the step grid (or back to [current] when close), within [min]..[max].
  double _snap(double v) {
    final c = current!;
    if ((v - c).abs() < step / 2) return c;
    final snapped = (v / step).round() * step;
    return double.parse(snapped.clamp(min, max).toStringAsFixed(4));
  }

  ExperimentLever _copy() => ExperimentLever._(
    id: id,
    label: label,
    unit: unit,
    min: min,
    max: max,
    step: step,
    current: current,
    options: options,
    supported: supported,
    reason: reason,
    caveat: caveat,
    missingInput: missingInput,
  )..value = value;
}

/// How one moved lever was treated in the result.
class LeverFlag {
  const LeverFlag({required this.id, required this.counted, this.reason});
  final String id;
  final bool counted;

  /// A [LeverReason] when not counted.
  final String? reason;
  String? get reasonText => _reasonText[reason];
}

/// The "Modeled difference between profiles" for the moved levers.
class ExperimentResult {
  const ExperimentResult({
    required this.status,
    this.message,
    this.differenceByYear = const {},
    this.currentPercentByYear = const {},
    this.alternativePercentByYear = const {},
    this.levers = const [],
    this.warnings = const [],
    this.missingInputs = const [],
    this.supportIssues = const [],
    this.interpretation,
    this.extrapolated = false,
    this.scoreDelta,
    this.currentScore,
    this.alternativeScore,
  });

  /// The health score change: the changed twin's health index − the current twin's (both
  /// from one compare(); higher is better). 0 under the weight guard. Null unless
  /// [available].
  final double? scoreDelta;
  final double? currentScore;
  final double? alternativeScore;

  /// - `available`: [differenceByYear] and [scoreDelta] hold the numbers.
  /// - `no_change`: nothing moved yet.
  /// - `not_counted`: every moved lever is "Not counted" (see [levers]).
  /// - `current_unavailable`: the person's own result has no number ([message],
  ///   [missingInputs], [supportIssues] say why).
  /// - `alternative_unavailable`: the tried profile is outside the model's support.
  /// - `invalid_input`: the tried values don't fit in a day (sleep + sitting + exercise).
  final String status;
  bool get available => status == 'available';

  /// The package's status message (or the app's, for `invalid_input`), shown with no number.
  final String? message;

  /// Years 1–5 → percentage points (alternative − current), unrounded. Empty unless
  /// [available]. Rounding is the UI's job.
  final Map<int, double> differenceByYear;
  double? get difference5 => differenceByYear[5];

  final Map<int, double> currentPercentByYear;
  final Map<int, double> alternativePercentByYear;

  /// Each moved lever, counted or not.
  final List<LeverFlag> levers;
  List<LeverFlag> get notCounted => [
    for (final l in levers)
      if (!l.counted) l,
  ];

  /// The package's comparison warnings (BMI, sleep and sitting are not intervention effects).
  final List<String> warnings;
  final List<String> missingInputs;
  final List<String> supportIssues;

  /// "Difference between two model profiles, not the benefit of changing a habit."
  final String? interpretation;

  /// The person's age is 30–34 or 80–85: show [extrapolationCaveat] with any number.
  final bool extrapolated;
  String? get caveat => extrapolated ? extrapolationCaveat : null;

  /// Always false: an observational difference, never a causal benefit.
  bool get causalInterpretation => false;

  static const title = TwinAssessment.scenarioTitle;
}

/// "Experiment with your twin": the person's current result, levers to try, and the
/// modeled difference. Bind a ListenableBuilder to it; [set] and [reset] notify.
class TwinExperiment extends ChangeNotifier {
  TwinExperiment({
    required this.model,
    required this.current,
    required Map<String, dynamic> appProfile,
    List<String> order = defaultLeverOrder,
  }) : _base = current.profileUsed,
       _levers = _buildLevers(current, appProfile, order) {
    _result = _compute();
  }

  final TwinModelService model;

  /// The person's own assessment.
  final TwinAssessment current;
  final Map<String, dynamic> _base;
  final List<ExperimentLever> _levers;
  late ExperimentResult _result;

  /// In the order from model-sensitivity.json; unsupported levers last.
  List<ExperimentLever> get levers => [for (final l in _levers) l._copy()];

  ExperimentLever lever(String id) => _levers.firstWhere((l) => l.id == id)._copy();

  ExperimentResult get result => _result;

  /// Sets a lever (snapped to its step and range). Unsupported levers are ignored.
  void set(String id, num value) {
    final l = _levers.firstWhere((l) => l.id == id);
    if (!l.supported || l.current == null) return;
    final next = l.options != null
        ? (l.options!.any((o) => o.value == value) ? value.toDouble() : l.value)
        : l._snap(value.toDouble());
    if (next == l.value) return;
    l.value = next;
    _result = _compute();
    notifyListeners();
  }

  /// Puts one lever, or all, back to the person's own value.
  void reset([String? id]) {
    for (final l in _levers) {
      if (id == null || l.id == id) l.value = l.current;
    }
    _result = _compute();
    notifyListeners();
  }

  Map<String, dynamic> _apply(Iterable<ExperimentLever> moved) {
    final p = Map<String, dynamic>.from(_base);
    for (final l in moved) {
      p[l.id] = l.value;
    }
    return p;
  }

  ExperimentResult _compute() {
    final x = current.extrapolated;
    if (!current.available) {
      return ExperimentResult(
        extrapolated: x,
        status: 'current_unavailable',
        message: current.message,
        missingInputs: current.missingInputs,
        supportIssues: current.supportIssues,
      );
    }
    final moved = [
      for (final l in _levers)
        if (l.changed) l,
    ];
    if (moved.isEmpty) return ExperimentResult(status: 'no_change', extrapolated: x);
    try {
      final flags = [for (final l in moved) _flag(l)];
      final counted = [
        for (var i = 0; i < moved.length; i++)
          if (flags[i].counted) moved[i],
      ];
      if (counted.isEmpty) return ExperimentResult(status: 'not_counted', levers: flags, extrapolated: x);
      final c = model.compare({'current_profile': _base, 'alternative_profile': _apply(counted)});
      final alt = TwinAssessment({'survival': c['alternative']});
      final cur = TwinAssessment({'survival': c['current']});
      final warnings = [for (final w in c['warnings'] as List? ?? const []) '$w'];
      if (!alt.available) {
        return ExperimentResult(
          extrapolated: x,
          status: 'alternative_unavailable',
          message: alt.message,
          missingInputs: alt.missingInputs,
          supportIssues: alt.supportIssues,
          levers: flags,
          warnings: warnings,
        );
      }
      return ExperimentResult(
        extrapolated: x,
        status: 'available',
        differenceByYear: TwinAssessment.yearMap(c['modeled_difference_percentage_points']),
        scoreDelta: (c['health_index_delta'] as num?)?.toDouble(),
        currentScore: (c['health_index_current'] as num?)?.toDouble(),
        alternativeScore: (c['health_index_alternative'] as num?)?.toDouble(),
        currentPercentByYear: cur.percentByYear,
        alternativePercentByYear: alt.percentByYear,
        levers: flags,
        warnings: warnings,
        interpretation: c['interpretation'] as String?,
      );
    } on FormatException {
      return ExperimentResult(
        extrapolated: x,
        status: 'invalid_input',
        message: 'Sleep, sitting and exercise together come to more than 24 hours a day. Try smaller changes.',
      );
    }
  }

  /// Whether a moved lever is counted. Its own contrast is checked only for direction;
  /// the result always comes from one compare() of the full alternative profile.
  LeverFlag _flag(ExperimentLever l) {
    LeverFlag no(String reason) => LeverFlag(id: l.id, counted: false, reason: reason);
    final c = model.compare({
      'current_profile': _base,
      'alternative_profile': _apply([l]),
    });
    final d = (c['modeled_difference_percentage_points'] as Map?)?['5'];
    // Every offered move points the way guidance does, so a lower modeled survival is
    // counter-intuitive.
    if (d is num && d < -1e-9) return no(LeverReason.counterIntuitive);
    return LeverFlag(id: l.id, counted: true);
  }
}

/// The order of docs/model-sensitivity.json (`recommendable_levers_ranked`, the same for
/// every age band and sex), with weight last. Used when the file can't be read.
const defaultLeverOrder = [
  LeverId.smoking,
  LeverId.vigorous,
  LeverId.moderate,
  LeverId.sleepHours,
  LeverId.sitting,
  LeverId.weightKg,
];

List<ExperimentLever> _buildLevers(TwinAssessment a, Map<String, dynamic> app, List<String> order) {
  final used = a.profileUsed;
  double? num_(Object? v) => v is num ? v.toDouble() : null;
  ExperimentLever off(String id, String label, String unit, double? c, String reason, {String? caveat}) =>
      ExperimentLever._(
        id: id,
        label: label,
        unit: unit,
        min: c ?? 0,
        max: c ?? 0,
        step: 0,
        current: c,
        supported: false,
        reason: reason,
        caveat: caveat,
        missingInput: reason == LeverReason.missingInput ? (id == LeverId.weightKg ? 'bmi' : id) : null,
      );
  ExperimentLever on(String id, String label, String unit, double c, double lo, double hi, double step) =>
      ExperimentLever._(id: id, label: label, unit: unit, min: lo, max: hi, step: step, current: c);

  ExperimentLever sleep() {
    const id = LeverId.sleepHours, label = 'Sleep', unit = 'h/night';
    final c = num_(used[id]);
    if (c == null) return off(id, label, unit, c, LeverReason.missingInput);
    if (c >= 7) return off(id, label, unit, c, LeverReason.notShortSleeper);
    // Up to 8 h: above it the model lowers the estimate (long-sleep term), which is not advice.
    return on(id, label, unit, c, c, 8, 0.5);
  }

  ExperimentLever more(String id, String label, double cap) {
    final c = num_(used[id]);
    if (c == null) return off(id, label, 'min/week', c, LeverReason.missingInput);
    if (c >= cap) return off(id, label, 'min/week', c, LeverReason.alreadyHigh);
    return on(id, label, 'min/week', c, c, cap, 15);
  }

  ExperimentLever sitting() {
    const id = LeverId.sitting, label = 'Sitting', unit = 'min/day';
    final c = num_(used[id]);
    if (c == null) return off(id, label, unit, c, LeverReason.missingInput);
    if (c < 90) return off(id, label, unit, c, LeverReason.alreadyLow);
    return on(id, label, unit, c, 60, c, 30);
  }

  final smoking = num_(used['smoking_status']);
  final weight = num_(app['weight_kg']);
  final levers = <String, ExperimentLever>{
    LeverId.smoking: smoking == 2
        ? ExperimentLever._(
            id: LeverId.smoking,
            label: 'Smoking',
            unit: 'choice',
            min: 1,
            max: 2,
            step: 1,
            current: smoking,
            options: const [LeverOption(2, 'Smokes now'), LeverOption(1, 'Quit')],
          )
        : off(
            LeverId.smoking,
            'Smoking',
            'choice',
            smoking,
            smoking == null ? LeverReason.missingInput : LeverReason.notASmoker,
          ),
    LeverId.vigorous: more(LeverId.vigorous, 'Hard exercise', 300),
    LeverId.moderate: more(LeverId.moderate, 'Moderate exercise', 600),
    LeverId.sleepHours: sleep(),
    LeverId.sitting: sitting(),
    LeverId.weightKg: off(
      LeverId.weightKg,
      'Weight',
      'kg',
      weight,
      weight == null || used['bmi'] == null ? LeverReason.missingInput : LeverReason.weightNotALever,
      caveat: _weightCaveat,
    ),
  };
  final ids = [
    for (final id in order)
      if (levers.containsKey(id)) id,
    for (final id in defaultLeverOrder)
      if (!order.contains(id)) id,
  ];
  final all = [for (final id in ids) levers[id]!];
  return [...all.where((l) => l.supported), ...all.where((l) => !l.supported)];
}

const _weightCaveat =
    'BMI above 27 has a near-zero, slightly inverse link in this model. It is not evidence that gaining weight helps.';

/// Lever order from docs/model-sensitivity.json (codex/d-model-sensitivity, copied to
/// assets/model/): `groups["<age band>|<sex>"].recommendable_levers_ranked`, falling back
/// to the age band, the sex, then `all`.
class LeverRanking {
  const LeverRanking(this.groups);

  factory LeverRanking.fromJson(Object? json) {
    final groups = <String, List<String>>{};
    final g = json is Map ? json['groups'] : null;
    if (g is Map) {
      for (final e in g.entries) {
        final ranked = e.value is Map ? (e.value as Map)['recommendable_levers_ranked'] : null;
        if (ranked is! List) continue;
        groups['${e.key}'] = [for (final r in ranked) ?_sensitivityLevers[r is Map ? r['lever'] : r]];
      }
    }
    return LeverRanking(groups);
  }

  /// Sensitivity lever names → lever ids.
  static const _sensitivityLevers = {
    'quit_smoking': LeverId.smoking,
    'vigorous_plus_60': LeverId.vigorous,
    'moderate_plus_90': LeverId.moderate,
    'short_sleep_plus_1h': LeverId.sleepHours,
    'sitting_minus_60_realistic': LeverId.sitting,
  };

  final Map<String, List<String>> groups;

  /// [sexNhanes] 1 male, 2 female.
  List<String> orderFor({num? age, num? sexNhanes}) {
    final band = age == null
        ? null
        : age < 35
        ? null
        : age < 50
        ? '35-49'
        : age < 65
        ? '50-64'
        : age < 80
        ? '65-79'
        : null;
    final sex = switch (sexNhanes) {
      1 => 'male',
      2 => 'female',
      _ => null,
    };
    for (final key in [
      if (band != null && sex != null) '$band|$sex',
      if (band != null) 'age:$band',
      if (sex != null) 'sex:$sex',
      'all',
    ]) {
      final order = groups[key];
      if (order != null && order.isNotEmpty) return order;
    }
    return defaultLeverOrder;
  }
}

const leverRankingAsset = 'assets/model/model-sensitivity.json';

Future<LeverRanking> loadLeverRanking({AssetBundle? bundle}) async {
  try {
    return LeverRanking.fromJson(jsonDecode(await (bundle ?? rootBundle).loadString(leverRankingAsset)));
  } catch (_) {
    return const LeverRanking({});
  }
}
