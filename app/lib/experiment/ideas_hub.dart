import 'package:flutter/widgets.dart';

import '../twin/twin_repository.dart';
import 'recommendations.dart';

/// Today's ideas, in one place for every way in (Home, Mochi's bubble, the check-in, the Experiment
/// result, the score, onboarding, voice) and the Ideas list.
///
/// It holds the last good `/api/recommendations` answer for the calendar day, kept on the phone so
/// Home can show today's idea without a second call and the list still opens offline. It also holds
/// the ideas hidden today ("Not for me"), which are sent as `excluded_ids` and are hidden here
/// whether or not the server honours them.
///
/// The age rule is the caller's: under 18 nothing here is ever asked for.
class IdeasHub extends ChangeNotifier {
  IdeasHub({
    required this.source,
    this.repo,
    DateTime Function()? now,
    this.allowed = _always,
  }) : _now = now ?? DateTime.now {
    _restore();
  }

  final RecommendationsSource source;

  /// Where the day's cache and the hidden ideas persist; null keeps them in memory only.
  final TwinRepository? repo;
  final DateTime Function() _now;

  /// False under 18 (or no age): no call, no cache, no entry point.
  final bool Function() allowed;
  static bool _always() => true;

  IdeasResponse? _response;
  String? _responseDay;
  String _hiddenDay = '';
  final List<String> _hidden = [];
  String? _bubbleDay;
  bool _loading = false;
  Object? _error;
  Future<void>? _inflight;

  String get today => dayKey(_now());

  /// True while the first answer of the day is on its way and nothing is cached.
  bool get loading => _loading;

  /// The last failure, kept while a cached answer is still shown (offline).
  RecommendationsFailure? get failure => _error is RecommendationsFailure
      ? _error as RecommendationsFailure
      : null;
  bool get hasFailure => _error != null;

  /// The cached answer, if it is today's.
  IdeasResponse? get response => allowed() && _responseDay == today ? _response : null;

  /// Ideas hidden today.
  List<String> get hidden =>
      _hiddenDay == today ? List.unmodifiable(_hidden) : const [];

  bool _visible(Recommendation r) => !hidden.contains(r.id);

  /// The cards "Another idea" steps through: the featured idea, then its alternatives, minus what
  /// is hidden. With the featured idea hidden (or none featured) the next recommendation leads.
  /// Empty when there is no featured idea at all (the list is then set I).
  List<Recommendation> get deck {
    final res = response;
    if (res == null || res.featuredId == null) return const [];
    final recs = res.recommendations;
    final lead = recs.where((r) => r.id == res.featuredId).firstOrNull;
    final order = [?lead, ...recs.where((r) => r != lead)];
    for (final r in order) {
      final cards = [r, ...r.alternatives].where(_visible).toList();
      if (cards.isNotEmpty) return cards;
    }
    return const [];
  }

  /// The recommendations that are not in the deck's group, minus what is hidden.
  List<Recommendation> get more {
    final res = response;
    if (res == null) return const [];
    final cards = deck;
    final parent = cards.isEmpty
        ? null
        : res.recommendations
              .where(
                (r) => r == cards.first || r.alternatives.contains(cards.first),
              )
              .firstOrNull;
    return [
      for (final r in res.recommendations)
        if (r != parent && _visible(r)) r,
    ];
  }

  /// Today's idea, for the entry points; null hides every one of them. Entry points never show
  /// an idea that has no featured id from the server.
  Recommendation? get featured => allowed() ? deck.firstOrNull : null;

  /// Every visible recommendation, for the list without a featured idea and for filters.
  List<Recommendation> get visibleRecommendations => [
    for (final r in response?.recommendations ?? const <Recommendation>[])
      if (_visible(r)) r,
  ];

  /// Keeps ideas that arrived with the end of onboarding (the first is the featured one) until the
  /// first real answer of the day replaces them. Only when nothing for today is cached.
  Future<void> seed(List<Recommendation> recs) async {
    await Future<void>.value();
    if (recs.isEmpty || (response?.recommendations.isNotEmpty ?? false)) return;
    _response = IdeasResponse(recommendations: recs, featuredId: recs.first.id, raw: null);
    _responseDay = today;
    notifyListeners();
  }

  /// Loads today's answer when nothing for today is cached. Never throws.
  Future<void> ensureToday() async {
    if (!allowed() || (response?.recommendations.isNotEmpty ?? false)) return;
    await refresh().catchError((Object _) {});
  }

  /// Asks the server again. A failure keeps the cached answer (the list says "Check your
  /// connection" above it); with no cache it is thrown for the screen to show.
  Future<void> refresh() =>
      _inflight ??= _refresh().whenComplete(() => _inflight = null);

  Future<void> _refresh() async {
    // Never notify in the middle of a build (this is often asked for from an initState).
    await Future<void>.value();
    if (!allowed()) return;
    final cached = response != null;
    _loading = !cached;
    _error = null;
    notifyListeners();
    final day = today;
    try {
      final s = source;
      final res = s is FullIdeasSource
          ? await (s as FullIdeasSource).fetch(excludedIds: hidden)
          : IdeasResponse(recommendations: await s.load());
      // An empty answer (not enough information) never wipes the day's ideas.
      if (res.recommendations.isNotEmpty || !cached) {
        _response = res;
        _responseDay = day;
        await _persist();
      }
    } on Object catch (e) {
      _error = e is RecommendationsFailure
          ? e
          : const RecommendationsFailure(null);
      if (!cached) {
        _loading = false;
        notifyListeners();
        throw _error!;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// "Not for me": hidden for today, on the phone.
  Future<void> hide(String id) async {
    if (hidden.contains(id)) return;
    _roll();
    _hidden.add(id);
    notifyListeners();
    await _persist();
  }

  /// Undo.
  Future<void> unhide(String id) async {
    _roll();
    if (!_hidden.remove(id)) return;
    notifyListeners();
    await _persist();
  }

  void _roll() {
    if (_hiddenDay != today) {
      _hiddenDay = today;
      _hidden.clear();
    }
  }

  /// Mochi's bubble shows once a day by itself.
  bool get bubbleDue => _bubbleDay != today;

  Future<void> markBubbleShown() async {
    if (!bubbleDue) return;
    _bubbleDay = today;
    await _persist();
  }

  /// "Delete my data": forget everything held in memory.
  void clear() {
    _response = null;
    _responseDay = null;
    _hidden.clear();
    _hiddenDay = '';
    _bubbleDay = null;
    _error = null;
    notifyListeners();
  }

  Future<void> _persist() async {
    final r = repo;
    if (r == null) return;
    try {
      await r.saveIdeasState({
        if (_responseDay != null && _response?.raw != null)
          'date': _responseDay,
        if (_responseDay != null && _response?.raw != null)
          'response': _response!.raw,
        'hidden_date': _hiddenDay,
        'hidden_ids': _hidden,
        'bubble_date': ?_bubbleDay,
      });
    } catch (e) {
      debugPrint('Ideas could not be saved on this phone: $e');
    }
  }

  void _restore() {
    final r = repo;
    if (r == null) return;
    final s = r.ideasState;
    try {
      if (s['response'] is Map && s['date'] is String) {
        _response = IdeasResponse.fromJson(
          Map<String, dynamic>.from(s['response'] as Map),
        );
        _responseDay = s['date'] as String;
      }
    } catch (_) {
      _response = null;
      _responseDay = null;
    }
    _hiddenDay = s['hidden_date'] as String? ?? '';
    _hidden
      ..clear()
      ..addAll([
        for (final id in (s['hidden_ids'] as List? ?? const [])) '$id',
      ]);
    _bubbleDay = s['bubble_date'] as String?;
  }
}

/// What a screen needs to offer today's ideas without knowing about routes: the hub (for the idea
/// itself) and the two places it can send the person. Null wherever Ideas are hidden (under 18).
class IdeasAccess {
  const IdeasAccess({required this.hub, required this.openIdea, required this.openList});
  final IdeasHub hub;

  /// The idea's detail, with Back returning to the caller.
  final void Function(BuildContext context, Recommendation idea) openIdea;

  /// "Ideas for you"; [levers] limits it to ideas for those Experiment levers ("More ideas like this").
  final void Function(BuildContext context, {required String origin, Set<String>? levers}) openList;
}

/// Makes [IdeasAccess] reachable from screens that sit far from the app shell (the score sheet).
/// Null access (under 18, no profile): every way in below it is hidden.
class IdeasScope extends InheritedWidget {
  const IdeasScope({super.key, required this.access, required super.child});
  final IdeasAccess? access;

  static IdeasAccess? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<IdeasScope>()?.access;

  @override
  bool updateShouldNotify(IdeasScope old) => access != old.access;
}
