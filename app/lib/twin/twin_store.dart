part of 'twin_repository.dart';

/// Where the store's one JSON document lives.
abstract class StoreBackend {
  Future<String?> read();
  Future<void> write(String text);
  Future<void> delete();
}

/// The phone's own file, written by the iOS runner (AppDelegate.swift) with
/// `NSFileProtectionComplete` and excluded from iCloud/iTunes backup: unreadable while
/// the phone is locked, never synced, never sent anywhere.
class ProtectedFileBackend implements StoreBackend {
  ProtectedFileBackend({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lifetwin/protected_store');

  final MethodChannel _channel;

  /// Set when the platform has no protected store (flutter test, macOS). Data then lives
  /// in memory for the session only; it is never written unprotected.
  String? _memory;
  bool _noPlatform = false;

  Future<T?> _call<T>(String method, [Object? args]) async {
    if (_noPlatform) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      _noPlatform = true;
      debugPrint('No protected store on this platform: keeping LifeTwin data in memory only.');
      return null;
    }
  }

  @override
  Future<String?> read() async {
    final text = await _call<String>('read');
    return _noPlatform ? _memory : text;
  }

  @override
  Future<void> write(String text) async {
    await _call<void>('write', text);
    if (_noPlatform) _memory = text;
  }

  @override
  Future<void> delete() async {
    await _call<void>('delete');
    _memory = null;
  }

  /// The file's protection class (`NSFileProtectionComplete`), for the simulator check.
  Future<String?> protection() => _call<String>('protection');
}

/// For tests.
class MemoryBackend implements StoreBackend {
  String? text;
  int writes = 0;
  @override
  Future<String?> read() async => text;
  @override
  Future<void> write(String t) async {
    text = t;
    writes++;
  }

  @override
  Future<void> delete() async => text = null;
}

/// Everything LifeTwin keeps about the person, on the phone only (owner ruling: "history
/// lives on your phone"). No sync and no network: nothing here is ever sent.
///
/// - [profile]: the confirmed answers (server HealthProfile names; profile_mapping.dart).
/// - [profileMeta]: per profile value, its source and whether it is an estimate.
/// - [checkins]: finished quick, daily and weekly check-ins as confirmed.
/// - [dayLogs]: one row per day in the package's `daily_logs` names, possibly partial;
///   a missing value is unknown (null), never zero.
/// - [historyEntries]: the person's history, appended as things happen (history_log.dart).
/// - [habitNotes]: notes from the conversation, kept only with memory consent.
/// - [twin]: cosmetic customization; never part of the health profile.
/// - [checkinSettings]: reminder time and weekly day; a preference, not health data.
/// - [memoryConsent]: the conversation's `memory_consent`; habit notes are kept only while true.
/// - [outsideAiConsent]: the person's yes to outside-AI wording, for one provider; off by default.
/// - [lifespanRevealSeen]: the one-time lifespan reveal was shown; a UI flag, not health data.
/// - [lastPlan]: the coach's latest daily plan and its local date, the base for the next revision.
///
/// Reads are public. Writes are private to this library, so the only write paths are the
/// [TwinRepository] methods the owner allows (see lib/README-model.md, "Who may write").
class TwinStore extends ChangeNotifier {
  TwinStore._(this._backend, Map<String, dynamic> doc) : _doc = doc;

  static const schemaVersion = 1;

  final StoreBackend _backend;
  Map<String, dynamic> _doc;
  Future<void> _writing = Future.value();

  static Future<TwinStore> open([StoreBackend? backend]) async {
    final b = backend ?? ProtectedFileBackend();
    Map<String, dynamic> doc = {};
    final text = await b.read();
    if (text != null && text.isNotEmpty) {
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map && parsed['version'] == schemaVersion) doc = Map<String, dynamic>.from(parsed);
      } on FormatException {
        // An unreadable file is not guessed at; it is replaced on the next save.
      }
    }
    return TwinStore._(b, doc).._dropUnreadable();
  }

  /// A file that parses but has a part of the wrong shape (a broken or older write) must not
  /// stop LifeTwin opening. Each part that cannot be read is dropped (a list keeps its
  /// readable entries); the rest is kept, and the file is replaced on the next save.
  void _dropUnreadable() {
    final reads = <String, void Function()>{
      'profile': () => profile,
      'profile_meta': () => profileMeta,
      'twin': () => twin,
      'ideas': () => ideasState,
      'outside_ai_consent': () => [outsideAiConsent, outsideAiProvider],
      'checkin_settings': () => checkinSettings,
      'first_joined': () {
        final day = firstJoined;
        if (day != null) shiftDay(day, 0);
      },
    };
    for (final e in reads.entries) {
      try {
        e.value();
      } catch (_) {
        _doc.remove(e.key);
      }
    }
    final rows = <String, void Function(Map<String, dynamic>)>{
      'checkins': (j) => shiftDay(CheckinEntry.fromJson(j).date, 0),
      'daily_logs': (j) => shiftDay(DayLog.fromJson(j).date, 0),
      'history': HistoryEntry.fromJson,
      'health_score': HealthScorePoint.fromJson,
      'habit_notes': (_) {},
    };
    for (final e in rows.entries) {
      final raw = _doc[e.key];
      if (raw == null) continue;
      if (raw is! List) {
        _doc.remove(e.key);
        continue;
      }
      _doc[e.key] = [
        for (final r in raw)
          if (r is Map && _reads(() => e.value(Map<String, dynamic>.from(r)))) r,
      ];
    }
  }

  static bool _reads(void Function() read) {
    try {
      read();
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> get profile => Map<String, dynamic>.from(_doc['profile'] as Map? ?? const {});

  /// Per profile field: where its value came from, and whether it is an estimate.
  Map<String, FieldProvenance> get profileMeta => {
    for (final e in (_doc['profile_meta'] as Map? ?? const {}).entries)
      if (e.value is Map) '${e.key}': FieldProvenance.fromJson(Map<String, dynamic>.from(e.value as Map)),
  };
  bool get hasProfile => profile.values.any((v) => v != null);

  List<CheckinEntry> get checkins => [for (final c in _list('checkins')) CheckinEntry.fromJson(c)];
  List<DayLog> get dayLogs => [for (final r in _list('daily_logs')) DayLog.fromJson(r)];
  List<HistoryEntry> get historyEntries => [for (final e in _list('history')) HistoryEntry.fromJson(e)];
  List<HealthScorePoint> get healthScorePoints => [for (final p in _list('health_score')) HealthScorePoint.fromJson(p)];
  List<Map<String, dynamic>> get habitNotes => _list('habit_notes');
  Map<String, dynamic>? get twin => _doc['twin'] == null ? null : Map<String, dynamic>.from(_doc['twin'] as Map);
  bool get memoryConsent => _doc['memory_consent'] == true;
  bool get lifespanRevealSeen => _doc['lifespan_reveal_seen'] == true;

  /// Ideas for you, kept for the day on the phone: the last good answer (`date`, `response`), the ideas
  /// hidden today (`hidden_date`, `hidden_ids`) and the day Mochi's bubble last showed (`bubble_date`).
  Map<String, dynamic> get ideasState => Map<String, dynamic>.from(_doc['ideas'] as Map? ?? const {});

  /// The local date (`YYYY-MM-DD`) onboarding was first completed; set once. The weekly
  /// check-in opens 7 days after it. A date, not health data.
  /// When the pending "Remind me later" notification fires (local wall time, ISO), if any.
  String? get remindLater {
    final v = _doc['remind_later'];
    return v is String && v.isNotEmpty ? v : null;
  }

  String? get firstJoined => _doc['first_joined'] as String?;

  /// The coach's latest daily plan (`{date, plan}`, the local date it was given on), if any.
  Map<String, dynamic>? get lastPlan =>
      _doc['last_plan'] is Map ? Map<String, dynamic>.from(_doc['last_plan'] as Map) : null;

  /// The person's yes to outside-AI wording, and the provider it was given for
  /// (`{provider, on}`); off when absent.
  bool get outsideAiConsent => (_doc['outside_ai_consent'] as Map?)?['on'] == true;
  String? get outsideAiProvider => (_doc['outside_ai_consent'] as Map?)?['provider'] as String?;
  CheckinSettings get checkinSettings => _doc['checkin_settings'] is Map
      ? CheckinSettings.fromJson(Map<String, dynamic>.from(_doc['checkin_settings'] as Map))
      : const CheckinSettings();

  List<Map<String, dynamic>> _list(String key) => [
    for (final r in _doc[key] as List? ?? const [])
      if (r is Map) Map<String, dynamic>.from(r),
  ];

  /// The profile and, for the values just confirmed, where each came from. One write.
  Future<void> _saveProfile(Map<String, dynamic> p, [Map<String, FieldProvenance> provenance = const {}]) => _saveAll({
    'profile': {
      for (final e in p.entries)
        if (e.value != null) e.key: e.value,
    },
    if (provenance.isNotEmpty)
      'profile_meta': {
        for (final e in profileMeta.entries) e.key: e.value.toJson(),
        for (final e in provenance.entries) e.key: e.value.toJson(),
      },
  });

  Future<void> _addCheckin(CheckinEntry r) => _save('checkins', [..._list('checkins'), r.toJson()]);

  /// Replaces the stored day rows (already merged by [mergeDayLogs]); only known values
  /// are written, so a missing value stays missing.
  Future<void> _putDayLogs(List<DayLog> rows) => _save('daily_logs', [for (final r in rows) r.toJson()]);

  /// Appends one history entry. Entries are never edited or removed (except by Delete my data).
  Future<void> _addHistory(HistoryEntry e) => _save('history', [..._list('history'), e.toJson()]);

  /// Appends one health score point. Points are never edited or removed (except by Delete my data).
  Future<void> _addHealthScore(HealthScorePoint p) => _save('health_score', [..._list('health_score'), p.toJson()]);

  Future<void> _saveCheckinSettings(CheckinSettings s) => _save('checkin_settings', s.toJson());

  Future<void> _saveOutsideAiConsent(bool on, String provider) =>
      _save('outside_ai_consent', {'provider': provider, 'on': on});

  Future<void> _addHabitNote(Map<String, dynamic> note, {DateTime? at}) => _save('habit_notes', [
    ...habitNotes,
    {'at': (at ?? DateTime.now()).toIso8601String(), 'note': note},
  ]);

  Future<void> _saveTwin(Map<String, dynamic> look) => _save('twin', look);

  Future<void> _saveIdeasState(Map<String, dynamic> state) => _save('ideas', state);

  Future<void> _setRemindLater(String? at) async {
    if (at != null || remindLater != null) await _save('remind_later', at ?? '');
  }

  Future<void> _setFirstJoined(String day) => _save('first_joined', day);

  Future<void> _setLifespanRevealSeen() => _save('lifespan_reveal_seen', true);

  Future<void> _setLastPlan(String date, Map<String, dynamic> plan) =>
      _save('last_plan', {'date': date, 'plan': plan});

  /// Turning memory off deletes the stored habit notes.
  Future<void> _setMemoryConsent(bool consent) async {
    if (!consent) await _save('habit_notes', const <Object>[]);
    await _save('memory_consent', consent);
  }

  /// "Delete my data": removes the file and everything in memory.
  Future<void> _deleteAll() async {
    _doc = {};
    notifyListeners();
    final delete = _writing.catchError((Object _) {}).then((_) => _backend.delete());
    _writing = delete.catchError((Object _) {});
    await delete;
  }

  Future<void> _save(String key, Object value) => _saveAll({key: value});

  /// Set while a [_transaction] runs: its writes are collected and written once.
  Map<String, Object>? _staged;

  /// Runs [body] as one write: everything it saves reaches the file together, or (if the
  /// write fails) nothing does and memory is put back, so a retry never duplicates a
  /// check-in or a history entry. A transaction inside a transaction joins the outer one.
  Future<T> _transaction<T>(Future<T> Function() body) async {
    if (_staged != null) return body();
    final previous = _doc;
    _staged = {};
    final T result;
    try {
      result = await body();
    } catch (_) {
      _staged = null;
      _doc = previous;
      notifyListeners();
      rethrow;
    }
    final staged = _staged!;
    _staged = null;
    if (staged.isNotEmpty) {
      notifyListeners();
      await _write(previous, _doc);
    }
    return result;
  }

  Future<void> _saveAll(Map<String, Object> values) {
    final previous = _doc;
    _doc = {..._doc, 'version': schemaVersion, ...values};
    if (_staged != null) {
      _staged!.addAll(values);
      return Future.value();
    }
    notifyListeners();
    return _write(previous, _doc);
  }

  /// One write at a time, in order. A failed write doesn't block the later ones, and puts
  /// memory back to [previous] unless something newer was saved since (that write carries
  /// the whole document anyway).
  Future<void> _write(Map<String, dynamic> previous, Map<String, dynamic> next) {
    final text = jsonEncode(next);
    final write = _writing.catchError((Object _) {}).then((_) => _backend.write(text));
    _writing = write.catchError((Object _) {});
    return write.catchError((Object e) {
      if (identical(_doc, next)) {
        _doc = previous;
        notifyListeners();
      }
      throw e;
    });
  }
}
