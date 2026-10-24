import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'twin_history.dart';

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
/// - [profile]: the confirmed answers (app field names).
/// - [checkins]: finished daily and weekly check-ins as confirmed.
/// - [dailyLogs] / [weeklySummaries]: rows in the package's shapes (twin_history.dart).
/// - [habitNotes]: free-form JSON from the conversation.
/// - [twin]: cosmetic customization; never part of the health profile.
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
    return TwinStore._(b, doc);
  }

  Map<String, dynamic> get profile => Map<String, dynamic>.from(_doc['profile'] as Map? ?? const {});
  bool get hasProfile => profile.values.any((v) => v != null);

  List<CheckinRecord> get checkins => [for (final c in _list('checkins')) CheckinRecord.fromJson(c)];
  List<Map<String, dynamic>> get dailyLogs => _list('daily_logs');
  List<Map<String, dynamic>> get weeklySummaries => _list('weekly_summaries');
  List<Map<String, dynamic>> get habitNotes => _list('habit_notes');
  Map<String, dynamic>? get twin => _doc['twin'] == null ? null : Map<String, dynamic>.from(_doc['twin'] as Map);

  List<Map<String, dynamic>> _list(String key) => [
    for (final r in _doc[key] as List? ?? const [])
      if (r is Map) Map<String, dynamic>.from(r),
  ];

  Future<void> saveProfile(Map<String, dynamic> p) => _save('profile', {
    for (final e in p.entries)
      if (e.value != null) e.key: e.value,
  });

  Future<void> addCheckin(CheckinRecord r) => _save('checkins', [..._list('checkins'), r.toJson()]);

  /// Adds or replaces the row for its `date`.
  Future<void> putDailyLog(Map<String, dynamic> row) => _save(
    'daily_logs',
    [
      for (final r in dailyLogs)
        if (r['date'] != row['date']) r,
      row,
    ]..sort((a, b) => '${a['date']}'.compareTo('${b['date']}')),
  );

  /// Adds or replaces the row for its `week_start`.
  Future<void> putWeeklySummary(Map<String, dynamic> row) => _save(
    'weekly_summaries',
    [
      for (final r in weeklySummaries)
        if (r['week_start'] != row['week_start']) r,
      row,
    ]..sort((a, b) => '${a['week_start']}'.compareTo('${b['week_start']}')),
  );

  Future<void> addHabitNote(Map<String, dynamic> note, {DateTime? at}) => _save('habit_notes', [
    ...habitNotes,
    {'at': (at ?? DateTime.now()).toIso8601String(), 'note': note},
  ]);

  Future<void> saveTwin(Map<String, dynamic> look) => _save('twin', look);

  /// "Delete my data": removes the file and everything in memory.
  Future<void> deleteAll() async {
    _doc = {};
    notifyListeners();
    await (_writing = _writing.then((_) => _backend.delete()));
  }

  Future<void> _save(String key, Object value) {
    _doc = {..._doc, 'version': schemaVersion, key: value};
    notifyListeners();
    final text = jsonEncode(_doc);
    // One write at a time, in order.
    return _writing = _writing.then((_) => _backend.write(text));
  }
}
