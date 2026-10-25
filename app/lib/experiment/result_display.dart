import '../twin/twin_experiment.dart';
import 'experiment_copy.dart';

/// What a result shows. The rule is the design's (y_gen.py header; README-model.md, "UI rules"):
///
/// - A number appears only when the engine says `available`. Every other status shows words
///   and no number.
/// - Today's survival p (percent): "About round(p) in 100"; p of 99.5 or more reads
///   "More than 99", never "100".
/// - The difference d (percentage points, raw, year 5) rounds half-up to one decimal, d1:
///   - d1 of 1.0 or more: "About round(d) more in 100" (at least 1), with the bear arrays.
///   - 0.1 to 0.9: "Less than 1 more in 100", no arrays; the exact figure is only behind (i).
///   - between -0.1 and 0.1: "About the same", no number.
///   - -0.1 or lower: "About N fewer in 100", in ink, never red.
/// - What-if counts are always today's count plus the rounded gap (never round(alt) on its
///   own), so the arrays, headline, curve labels and table cannot disagree.
/// - The result is one `compare()` of the whole what-if twin. Per-lever numbers are never summed.
enum ResultKind {
  /// Nothing moved yet.
  noChange,

  /// d1 of 1.0 or more.
  big,

  /// d1 from 0.1 to 0.9.
  tiny,

  /// |d1| under 0.1: "About the same".
  same,

  /// d1 of -0.1 or lower.
  lower,

  /// Every moved lever is "Not counted".
  notCounted,

  /// The model has no number for the what-if (`alternative_unavailable`, or a status it
  /// does not know).
  noNumber,

  /// The tried values do not fit in a day.
  invalid,
}

/// One year of the curve and the table, with the same rounding as the headline.
class YearRow {
  const YearRow({
    required this.year,
    required this.today,
    required this.whatIf,
    required this.gap,
    required this.gapIsTiny,
  });
  final int year;
  final int today;
  final int whatIf;
  final int gap;

  /// The gap rounds to 0 but is 0.1 or more: "less than 1 more".
  final bool gapIsTiny;
}

class ResultDisplay {
  const ResultDisplay._(
    this.kind, {
    this.message,
    this.today,
    this.todayMoreThan99 = false,
    this.gap,
    this.whatIf,
    this.d,
    this.d1,
    this.years = 5,
    this.rows = const [],
    this.notCounted = const [],
    this.caveat,
  });

  final ResultKind kind;

  /// The engine's message, for the kinds that show no number (shown behind "Why?").
  final String? message;

  /// People still here in [years] years out of 100 today (whole people).
  final int? today;

  /// Today is 99.5 or more: say "More than 99".
  final bool todayMoreThan99;

  /// The rounded gap (people), and the what-if count: [today] plus [gap].
  final int? gap;
  final int? whatIf;

  /// The raw difference and its one-decimal rounding.
  final double? d;
  final double? d1;
  final int years;

  /// Years 1 to 5 for the curve and the table (available results only).
  final List<YearRow> rows;

  /// Moved levers the model does not count, with their reasons.
  final List<LeverFlag> notCounted;

  /// Age 30-34 or 80-85: the rough-guide caveat, verbatim from the engine.
  final String? caveat;

  /// Whether the card shows any number.
  bool get hasNumber => const {ResultKind.big, ResultKind.tiny, ResultKind.same, ResultKind.lower}.contains(kind);

  /// Whether the 10 by 10 arrays may be drawn.
  bool get showsArrays => kind == ResultKind.big;

  static const title = ExperimentResult.title;

  /// The headline: "About 4 more in 100", "Less than 1 more in 100", "About the same", ...
  String? get headline => switch (kind) {
    ResultKind.big => ExperimentCopy.more(gap!),
    ResultKind.tiny => caveat == null ? ExperimentCopy.tiny : ExperimentCopy.tinyShort,
    ResultKind.same => ExperimentCopy.same,
    ResultKind.lower => ExperimentCopy.fewer(gap!),
    _ => null,
  };

  /// "About 89" or "More than 99" (then " in 100").
  String? get todayText =>
      today == null ? null : (todayMoreThan99 ? ExperimentCopy.moreThan99 : ExperimentCopy.about(today!));

  /// The what-if box of the tiny state: "A tiny bit more".
  String? get whatIfText => switch (kind) {
    ResultKind.tiny => ExperimentCopy.tinyBox,
    ResultKind.big => ExperimentCopy.about(whatIf!),
    _ => null,
  };

  /// Behind (i) in the tiny state: the exact figure per 1,000.
  String? get exactFigure => kind == ResultKind.tiny ? ExperimentCopy.exactTiny(d!) : null;

  static ResultDisplay of(ExperimentResult r) {
    final flags = r.notCounted;
    switch (r.status) {
      case 'no_change':
        return const ResultDisplay._(ResultKind.noChange);
      case 'not_counted':
        return ResultDisplay._(ResultKind.notCounted, notCounted: flags);
      case 'invalid_input':
        return ResultDisplay._(ResultKind.invalid, message: r.message, notCounted: flags);
      case 'available':
        return _available(r, flags);
      default:
        // current_unavailable has its own screens (Y-8, Y-9, Y-10); alternative_unavailable
        // and any status the engine adds later show no number.
        return ResultDisplay._(ResultKind.noNumber, message: r.message, notCounted: flags);
    }
  }

  static ResultDisplay _noNumber(ExperimentResult r, List<LeverFlag> flags) =>
      ResultDisplay._(ResultKind.noNumber, message: r.message, notCounted: flags);

  static ResultDisplay _available(ExperimentResult r, List<LeverFlag> flags) {
    final diffs = r.differenceByYear;
    final years = diffs.containsKey(5) ? 5 : (diffs.keys.isEmpty ? null : (diffs.keys.toList()..sort()).last);
    final d = years == null ? null : diffs[years];
    final p = years == null ? null : r.currentPercentByYear[years];
    if (years == null || d == null || p == null) return _noNumber(r, flags);

    final d1 = ExperimentCopy.roundHalfUp(d, 1).toDouble();
    final more99 = p >= 99.5;
    final today = ExperimentCopy.roundHalfUp(p).toInt();
    final gapRaw = ExperimentCopy.roundHalfUp(d.abs()).toInt();
    final caveat = r.extrapolated ? r.caveat : null;

    final rows = [
      for (final y in (diffs.keys.toList()..sort()))
        if (r.currentPercentByYear[y] != null)
          () {
            final t = ExperimentCopy.roundHalfUp(r.currentPercentByYear[y]!).toInt();
            final g = ExperimentCopy.roundHalfUp(diffs[y]!).toInt();
            final g1 = ExperimentCopy.roundHalfUp(diffs[y]!, 1);
            return YearRow(year: y, today: t, whatIf: t + g, gap: g, gapIsTiny: g == 0 && g1 >= 0.1);
          }(),
    ];

    ResultDisplay make(ResultKind kind, {int? gap}) => ResultDisplay._(
      kind,
      today: today,
      todayMoreThan99: more99,
      gap: gap,
      whatIf: gap == null || kind == ResultKind.lower ? null : today + gap,
      d: d,
      d1: d1,
      years: years,
      rows: rows,
      notCounted: flags,
      caveat: caveat,
    );

    if (d1 >= 1.0) return make(ResultKind.big, gap: gapRaw < 1 ? 1 : gapRaw);
    if (d1 >= 0.1) return make(ResultKind.tiny);
    if (d1 > -0.1) return make(ResultKind.same);
    return make(ResultKind.lower, gap: gapRaw < 1 ? 1 : gapRaw);
  }
}
