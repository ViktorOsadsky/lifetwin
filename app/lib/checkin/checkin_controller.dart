import 'package:flutter/foundation.dart';

import '../twin/twin_model.dart';
import '../twin/twin_repository.dart';
import 'checkin_client.dart';
import 'outlook_change.dart';

/// One answer in the end-of-check-in read-back ("Sleep: 7 hours").
class ReadbackItem {
  const ReadbackItem(this.field, this.label, this.value);
  final String field;
  final String label;

  /// The answer in words, or null when it was skipped.
  final String? value;
}

/// Decides when the whole check-in is ready for its ONE read-back, and what it lists. This is the
/// seam for the server contract that is coming from the peer: today the read-back is built from the
/// finished reply's confirmed answers; swap this adapter when the server sends its own read-back.
abstract class ReadbackAdapter {
  bool isReady(CheckInKind kind, CheckInResponse r);
  List<ReadbackItem> items(CheckInKind kind, CheckInResponse r);
}

/// Today's contract: the reply is `complete` with its answers in `state.confirmed`; fields the
/// person skipped have no value.
class CompleteReplyReadback implements ReadbackAdapter {
  const CompleteReplyReadback();

  static const labels = {
    'wellbeing': 'Feeling',
    'sleep_hours_last_night': 'Sleep',
    'exercise_minutes_today': 'Moving today',
    'alcohol_drinks_yesterday': 'Drinks yesterday',
    'sleep_hours': 'Sleep',
    'exercise_minutes_weekly': 'Exercise this week',
    'alcohol_drinks_weekly': 'Drinks this week',
    'smoking_status': 'Smoking',
    'weight_kg': 'Weight',
    'systolic_bp': 'Blood pressure',
  };

  static String? words(String field, Object? v) {
    String n(num x) => x == x.roundToDouble() ? '${x.round()}' : x.toStringAsFixed(1);
    if (v == null) return null;
    return switch (field) {
      'wellbeing' => switch ('$v') {
        'good' => 'Good',
        'okay' => 'Okay',
        'not_great' => 'Not great',
        final s => s,
      },
      'sleep_hours_last_night' || 'sleep_hours' when v is num => '${n(v)} hours',
      'exercise_minutes_today' || 'exercise_minutes_weekly' when v is num => '${n(v)} minutes',
      'alcohol_drinks_yesterday' || 'alcohol_drinks_weekly' when v is num => '${n(v)} ${v == 1 ? 'drink' : 'drinks'}',
      'weight_kg' when v is num => '${n(v)} kg',
      'systolic_bp' when v is num => 'top number ${n(v)}',
      _ => '$v',
    };
  }

  @override
  bool isReady(CheckInKind kind, CheckInResponse r) => r.complete;

  @override
  List<ReadbackItem> items(CheckInKind kind, CheckInResponse r) => [
    for (final q in r.questions) ReadbackItem(q, labels[q] ?? q, words(q, r.confirmed[q])),
  ];
}

/// Runs one check-in conversation (`/api/checkin/*`) against the phone's repository. Created and
/// owned by `openCheckIn`.
///
/// There is no "Looks right?" after each answer: a tapped or spoken answer is accepted as it is (the
/// server's per-answer confirm turn is sent for the person), and the whole check-in is read back
/// ONCE at the end ([readback]), with "Looks right" ([accept]) and "Change with Mochi" ([redo]).
/// Nothing is recorded until [accept]: the finished reply is held, then handed to
/// `TwinRepository.applyCheckin`, which records the check-in (so the scheduler sees it as done),
/// feeds the twin's mood, and, for a weekly one, applies the update and recomputes the outlook.
/// An emergency reply saves nothing and asks no next question; [resume] picks up where Mochi was.
class CheckinController extends ChangeNotifier {
  CheckinController({
    required this.client,
    required this.repository,
    required this.kind,
    DateTime Function()? clock,
    this.adapter = const CompleteReplyReadback(),
  }) : _clock = clock ?? DateTime.now;

  final CheckInClient client;
  final TwinRepository repository;
  final CheckInKind kind;
  final ReadbackAdapter adapter;
  final DateTime Function() _clock;

  /// The outlook when the check-in began ("last week").
  TwinAssessment? _before;

  CheckInResponse? response;
  CheckInResponse? _held;
  bool busy = false;
  String? error;
  bool emergency = false;

  /// What Mochi was saying when the emergency pause came ("Picks up at: ...").
  String? pausedAt;

  /// The one read-back of the whole check-in; null until every question is answered or skipped.
  List<ReadbackItem>? readback;

  /// Recorded: the person said "Looks right".
  bool done = false;

  /// The outlook change after a finished weekly check-in.
  OutlookChange? change;

  bool get started => response != null;

  /// Every question is answered or skipped, and the read-back is showing (or already accepted).
  bool get complete => done || readback != null;

  /// 1-based position of the current question, and how many there are.
  int get position {
    final r = response;
    if (r == null || r.currentField == null) return r?.questions.length ?? 0;
    final i = r.questions.indexOf(r.currentField!);
    return i < 0 ? 1 : i + 1;
  }

  int get total => response?.questions.length ?? 0;

  Future<void> start() async {
    _before = repository.current;
    await _run(() => client.start(kind, localDate: isoDate(_clock()), previous: _previous()));
  }

  /// A typed or spoken answer, or a quick reply's text.
  Future<void> reply(String text, {bool transcript = false}) => _turn('reply', text: text, transcript: transcript);

  Future<void> skip() => _turn('skip');

  /// "Continue" after an emergency pause (or the pinned close): the same question again.
  Future<void> resume() async {
    await _turn('resume');
    repository.clearEmergency();
  }

  /// Weekly only: the server's per-answer read-back, "Yes".
  Future<void> confirm() => _turn('confirm');

  /// "Looks right": records the check-in.
  Future<void> accept() async {
    final r = _held;
    if (r == null || done || busy) return;
    busy = true;
    notifyListeners();
    try {
      await repository.applyCheckin(r.raw);
      done = true;
      if (kind == CheckInKind.weekly) change = OutlookChange.between(_before, repository.current);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// "Change with Mochi": nothing was recorded, so the check-in starts over.
  Future<void> redo() async {
    if (done) return;
    _held = null;
    readback = null;
    response = null;
    await start();
  }

  Map<String, dynamic> _previous() {
    for (final c in repository.store.checkins.reversed) {
      if (c.kind == kind.name) return Map<String, dynamic>.from(c.answers);
    }
    return const {};
  }

  Future<void> _turn(String action, {String? text, bool transcript = false}) async {
    final r = response;
    if (r == null || busy) return;
    await _run(() async {
      var next = await client.turn(action: action, state: r.state, text: text, fromTranscript: transcript);
      // No per-answer "Looks right?" in a daily check-in: the tap or the words are the answer.
      if (kind == CheckInKind.daily && next.phase == 'confirming' && !next.emergency && !next.complete) {
        next = await client.turn(action: 'confirm', state: next.state);
      }
      return next;
    });
  }

  Future<void> _run(Future<CheckInResponse> Function() call) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final previous = response;
      final r = await call();
      if (r.emergency && !(previous?.emergency ?? false)) pausedAt = previous?.message;
      emergency = r.emergency;
      response = r;
      if (!r.emergency && adapter.isReady(kind, r)) {
        // Hold it: the whole check-in is read back once before anything is recorded.
        _held = r;
        readback = adapter.items(kind, r);
      } else {
        await repository.applyCheckin(r.raw);
      }
    } on CheckInFailure catch (e) {
      error = e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
