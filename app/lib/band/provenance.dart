import 'package:flutter/foundation.dart';

/// Where a saved answer came from: you_said | apple_health | document | mochi_change | wristband, plus
/// `estimated: true` for sensor or proxy estimates (engine, "Answer provenance"). Labels: "You said",
/// "From Apple Health", "From your document", "Changed with Mochi", "From your band", "≈ Sensor estimate".
@immutable
class Provenance {
  const Provenance(this.source, {this.estimated = false, this.estimateDays, this.confirmedAt});

  final String source;
  final bool estimated;

  /// Wristband: how many valid days the estimate came from.
  final int? estimateDays;
  final DateTime? confirmedAt;

  static const youSaid = Provenance('you_said');

  bool get isBand => source == 'wristband';

  String get label => switch (source) {
    'apple_health' => 'From Apple Health',
    'document' => 'From your document',
    'mochi_change' => 'Changed with Mochi',
    'wristband' => 'From your band',
    _ => 'You said',
  };

  /// "Sensor estimate" beside an estimated value.
  String? get estimateLabel => estimated ? 'Sensor estimate' : null;
}

/// Provenance of the answers on this phone. STUB: held in memory until the engine stores `source` and
/// `estimated` next to each answer (lib/twin is theirs). Changing an answer through Mochi later
/// makes it "Changed with Mochi", so the band label goes away.
class AnswerProvenance extends ChangeNotifier {
  final _by = <String, Provenance>{};

  Provenance of(String field) => _by[field] ?? Provenance.youSaid;

  void set(String field, Provenance p) {
    _by[field] = p;
    notifyListeners();
  }

  void clear() {
    _by.clear();
    notifyListeners();
  }

  /// The profile as it may go to an outside AI provider: wristband answers and any other sensor
  /// estimate are removed. (Whether band summaries may ever go there is an open owner question; the
  /// answer today is no.) Only call this after the person's consent for that provider.
  Map<String, dynamic> outsideAiProfile(Map<String, dynamic> profile) => {
    for (final e in profile.entries)
      if (!(_by[e.key]?.isBand ?? false) && !(_by[e.key]?.estimated ?? false)) e.key: e.value,
  };
}
