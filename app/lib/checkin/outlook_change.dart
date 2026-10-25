import '../experiment/experiment_copy.dart';
import '../twin/profile_mapping.dart';
import '../twin/twin_model.dart';

/// How the outlook moved between two real assessments (last week and this week; Z-17, Z-33, Z-34).
enum OutlookChangeKind {
  /// 1 in 100 or more: "About 6 more in 100", with the bear arrays.
  moreBig,

  /// 0.1 to 0.9: "Up a little".
  up,

  /// Under 0.1 either way: "About the same".
  same,

  /// -0.1 to -0.9: "Down a little". Kind words, never red.
  down,

  /// -1 or lower: "About N fewer in 100".
  fewerBig,

  /// Either assessment has no number: the dashed "No number yet" tile.
  unavailable,
}

/// The change from [before] (the outlook before the check-in) to [after].
///
/// Rounding (real updates anchor on the current value, unlike what-ifs, which anchor on today):
/// this week = round(current), the difference = round(raw difference), last week = this week
/// minus the difference. The one-decimal figures sit behind "Exact numbers". Shown only when both
/// assessments are `available`; otherwise there is no number and [missingLabels] says what is
/// still needed. Never a date, life expectancy or years gained.
class OutlookChange {
  OutlookChange._(
    this.kind, {
    this.thisWeek,
    this.lastWeek,
    this.gap,
    this.exact,
    this.missingLabels = const [],
    this.message,
    this.caveat,
  });

  final OutlookChangeKind kind;
  final int? thisWeek;
  final int? lastWeek;
  final int? gap;

  /// "Last week 96.9 in 100, this week 97.8 in 100: 0.9 more".
  final String? exact;
  final List<String> missingLabels;
  final String? message;

  /// Age 30-34 or 80-85: the engine's caveat, shown behind the "Rough guide" badge.
  final String? caveat;

  bool get hasNumber => kind != OutlookChangeKind.unavailable;
  bool get showsArrays => kind == OutlookChangeKind.moreBig;

  String get headline => switch (kind) {
    OutlookChangeKind.moreBig => ExperimentCopy.more(gap!),
    OutlookChangeKind.up => 'Up a little',
    OutlookChangeKind.same => ExperimentCopy.same,
    OutlookChangeKind.down => 'Down a little',
    OutlookChangeKind.fewerBig => ExperimentCopy.fewer(gap!),
    OutlookChangeKind.unavailable => 'No number yet',
  };

  String? get subline => switch (kind) {
    OutlookChangeKind.moreBig => 'Still alive at 5 years',
    OutlookChangeKind.up => 'Less than 1 more in 100 still alive, at 5 years',
    OutlookChangeKind.same => 'Still alive at 5 years',
    OutlookChangeKind.down => 'Less than 1 fewer in 100 still alive, at 5 years',
    OutlookChangeKind.fewerBig => 'Still alive at 5 years',
    OutlookChangeKind.unavailable => missingLabels.isEmpty ? message : 'Still needed: ${missingLabels.join(', ')}',
  };

  /// "Weeks go up and down." under a lower number.
  bool get weeksVary => kind == OutlookChangeKind.down || kind == OutlookChangeKind.fewerBig;

  static const year = 5;

  static OutlookChange between(TwinAssessment? before, TwinAssessment? after) {
    if (before == null || after == null || !before.available || !after.available) {
      final missing = [for (final m in (after?.missingInputs ?? const <String>[])) modelInputLabels[m] ?? m];
      return OutlookChange._(OutlookChangeKind.unavailable, missingLabels: missing, message: after?.message);
    }
    final p0 = before.percentByYear[year], p1 = after.percentByYear[year];
    if (p0 == null || p1 == null) return OutlookChange._(OutlookChangeKind.unavailable, message: after.message);
    final d = p1 - p0;
    final d1 = ExperimentCopy.roundHalfUp(d, 1).toDouble();
    final now = ExperimentCopy.roundHalfUp(p1).toInt();
    final gap = ExperimentCopy.roundHalfUp(d.abs()).toInt();
    final caveat = after.extrapolated ? extrapolationCaveat : null;
    final exact =
        'Last week ${ExperimentCopy.roundHalfUp(p0, 1).toStringAsFixed(1)} in 100, '
        'this week ${ExperimentCopy.roundHalfUp(p1, 1).toStringAsFixed(1)} in 100';

    OutlookChange make(OutlookChangeKind k, {int? g, String? word}) => OutlookChange._(
      k,
      thisWeek: now,
      lastWeek: g == null ? null : (k == OutlookChangeKind.moreBig ? now - g : now + g),
      gap: g,
      exact: word == null ? '$exact: about the same' : '$exact: ${d1.abs().toStringAsFixed(1)} $word',
      caveat: caveat,
    );

    if (d1 >= 1.0) return make(OutlookChangeKind.moreBig, g: gap < 1 ? 1 : gap, word: 'more');
    if (d1 >= 0.1) return make(OutlookChangeKind.up, word: 'more');
    if (d1 > -0.1) return make(OutlookChangeKind.same);
    if (d1 > -1.0) return make(OutlookChangeKind.down, word: 'fewer');
    return make(OutlookChangeKind.fewerBig, g: gap < 1 ? 1 : gap, word: 'fewer');
  }
}
