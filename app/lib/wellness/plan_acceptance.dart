import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where today's accepted plan items are kept on the phone (one string).
abstract class PlanStore {
  Future<String?> read();
  Future<void> write(String? value);
}

class MemoryPlanStore implements PlanStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? v) async => value = v;
}

class PrefsPlanStore implements PlanStore {
  static const key = 'plan_acceptance_v1';
  @override
  Future<String?> read() async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String? value) async {
    try {
      final p = await SharedPreferences.getInstance();
      value == null ? await p.remove(key) : await p.setString(key, value);
    } catch (_) {
      // No local storage: the choice still shows for this visit.
    }
  }
}

/// The plan items the person said yes to, for one local date. Only item ids and the date are kept (no
/// health data). [unsynced] means the coach has not yet heard the "accepted" feedback; it is retried quietly.
class PlanAcceptance extends ChangeNotifier {
  PlanAcceptance([PlanStore? store]) : _store = store ?? PrefsPlanStore();
  final PlanStore _store;
  String? _date;
  Set<String> _ids = {};
  bool _unsynced = false;

  /// Reads the saved state; call once after creating.
  Future<void> load() async {
    try {
      final text = await _store.read();
      if (text == null) return;
      final m = jsonDecode(text) as Map;
      _date = m['date'] as String?;
      _ids = {for (final i in m['ids'] as List) '$i'};
      _unsynced = m['unsynced'] == true;
      notifyListeners();
    } catch (_) {}
  }

  Set<String> idsFor(String? date) => date != null && date == _date ? Set.of(_ids) : <String>{};
  bool unsyncedFor(String? date) => date != null && date == _date && _unsynced;

  Future<void> save(String? date, Set<String> ids, {required bool unsynced}) async {
    if (date == null) return;
    _date = date;
    _ids = Set.of(ids);
    _unsynced = unsynced && ids.isNotEmpty;
    notifyListeners();
    await _store.write(jsonEncode({'date': _date, 'ids': _ids.toList(), 'unsynced': _unsynced}));
  }

  Future<void> clear() async {
    _date = null;
    _ids = {};
    _unsynced = false;
    notifyListeners();
    await _store.write(null);
  }
}
