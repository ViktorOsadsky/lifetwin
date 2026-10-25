import 'package:flutter/foundation.dart';

import 'band_data.dart';
import 'band_file.dart';
import 'band_sitting.dart';

/// Bluetooth as the app can see it.
enum BluetoothState { on, off, notAllowed }

class BandDevice {
  const BandDevice({required this.name, this.strength = 0});

  /// The band's Bluetooth name (firmware, assumed "LifeTwin Band").
  final String name;

  /// Signal strength, higher is closer: strongest first.
  final int strength;
}

/// The wrist band over Bluetooth. STUB: there is no Bluetooth plugin in the app yet, so no real band
/// can be found; [StubBandClient] finds nothing unless given devices, and the recorded demo is the only
/// data. Wording on screen is "Bluetooth", "pair", "band": never "BLE", "GATT", "device ID" or "ESP32".
abstract class BandClient {
  Future<BluetoothState> bluetooth();

  /// Searches for up to [timeout]; empty when nothing is found.
  Future<List<BandDevice>> scan({
    Duration timeout = const Duration(seconds: 20),
  });
  Future<bool> pair(BandDevice device);
  Future<void> unpair();

  /// Minute records, as they arrive (buffered minutes resume from the last unsent one).
  Stream<BandMinute> minuteRecords();
}

/// No Bluetooth plugin yet.
const bandBluetoothAvailable = false;

class StubBandClient implements BandClient {
  StubBandClient({
    this.state = BluetoothState.on,
    this.devices = const [],
    this.pairs = true,
  });

  BluetoothState state;
  List<BandDevice> devices;
  bool pairs;
  int scans = 0;

  @override
  Future<BluetoothState> bluetooth() async => state;

  @override
  Future<List<BandDevice>> scan({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    scans++;
    return [...devices]..sort((a, b) => b.strength.compareTo(a.strength));
  }

  @override
  Future<bool> pair(BandDevice device) async => pairs;

  @override
  Future<void> unpair() async {}

  @override
  Stream<BandMinute> minuteRecords() => const Stream.empty();
}

/// A saved week of minute records for "Try a recorded demo". Every band screen then says "Recorded
/// demo" and nothing from it is offered as a suggestion or a twin reaction, or saved.
List<BandMinute> recordedDemoMinutes(DateTime today) {
  final out = <BandMinute>[];
  for (var back = 6; back >= 0; back--) {
    final day = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: back));
    // Worn 8 AM to 8 PM on most days; a short wear on two days.
    final hours = (back == 2 || back == 5) ? 4 : 12;
    for (var h = 0; h < hours; h++) {
      for (var m = 0; m < 60; m++) {
        final moving = m < 8 && h % 3 == 0;
        out.add(
          BandMinute(
            at: day.add(Duration(hours: 8 + h, minutes: m)),
            steps: moving ? 90 : 4,
            moderate: moving && m < 6,
            // Authored synthetic waking-day labels, not a sensor classifier.
            posture: moving ? BandPosture.moving : BandPosture.sitting,
            wakeState: BandWakeState.awake,
          ),
        );
      }
    }
  }
  return out;
}

enum BandStatus { connected, notConnected, lowPower, notWorn, demo }

/// The band's state on the phone: paired or not, recorded demo on or off, and the minute records in
/// MEMORY (D1: they stay on this phone, added up here, never stored or sent). Unpairing erases the band
/// days; answers the person confirmed ("From your band") stay.
class BandStore extends ChangeNotifier {
  BandStore(this.client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final BandClient client;
  final DateTime Function() _now;

  bool paired = false;
  String? bandName;
  bool demo = false;
  bool hiddenFromRoom = false;

  /// The band reports power (only some can; a USB power bank usually cannot).
  bool? lowPower;

  /// No minute record for 15+ minutes while the app is open.
  bool connectionLost = false;

  final _minutes = <BandMinute>[];
  final _reports = <String, BandDayReport>{};
  List<BandDayReport> get fileReports => List.unmodifiable(
    _reports.values.toList()..sort((a, b) => a.date.compareTo(b.date)),
  );
  bool get hasImportedFile => _reports.isNotEmpty;
  String get sourceLabel => demo
      ? 'Recorded demo'
      : hasImportedFile
      ? 'Imported band file'
      : 'Bluetooth';
  DateTime? lastSynced;

  List<BandMinute> get minutes => List.unmodifiable(_minutes);

  /// Live data only: false for the recorded demo.
  bool get live => (paired || hasImportedFile) && !demo;

  /// The recorded demo is all there is: no paired band and no imported file (those take priority).
  bool get demoOnly => demo && !paired && !hasImportedFile;

  BandStatus get status {
    if (demo) return BandStatus.demo;
    if (connectionLost || hasImportedFile && !paired) {
      return BandStatus.notConnected;
    }
    if (lowPower == true) return BandStatus.lowPower;
    if (paired && _minutes.isNotEmpty && _notWornNow) return BandStatus.notWorn;
    return BandStatus.connected;
  }

  bool get _notWornNow {
    final last = _minutes.last;
    return !last.worn;
  }

  BandWeek week() {
    final legacy = BandWeek.from(_minutes, _now());
    return BandWeek([
      for (final day in legacy.days)
        if (_reports[_day(day.date)] case final report?)
          BandDay.fromReport(report)
        else
          day,
    ]);
  }

  /// Validates the entire delivery before changing state. Same reports are no-ops;
  /// replacing a date with different data needs an explicit caller decision.
  bool importReports(
    List<BandDayReport> reports, {
    bool replaceExisting = false,
  }) {
    if (reports.isEmpty) return false;
    final incoming = <String, BandDayReport>{};
    final expectedDemo = reports.first.synthetic;
    if (reports.any((r) => r.synthetic != expectedDemo) ||
        _reports.isNotEmpty && demo != expectedDemo ||
        expectedDemo && !demo && (_minutes.isNotEmpty || paired)) {
      throw const BandFileFailure(
        'Keep recorded demo data separate from measured imports.',
      );
    }
    for (final report in reports) {
      if (incoming.containsKey(report.day)) {
        throw const BandFileFailure('The delivery repeats a date.');
      }
      final old = _reports[report.day];
      final liveOverlap = _minutes.any((m) => _day(m.at) == report.day);
      if (!replaceExisting &&
          (old != null && old.contentKey != report.contentKey || liveOverlap)) {
        throw const BandFileFailure(
          'This date already has different data. Choose whether to replace it.',
        );
      }
      incoming[report.day] = report;
    }
    if (incoming.values.every(
      (r) => _reports[r.day]?.contentKey == r.contentKey,
    )) {
      return false;
    }
    if (_reports.isEmpty && demo && !expectedDemo) {
      if (!replaceExisting) {
        throw const BandFileFailure(
          'Leave the recorded demo before importing measured data.',
        );
      }
      _minutes.clear();
    }
    for (final report in reports) {
      _minutes.removeWhere((m) => _day(m.at) == report.day);
    }
    _reports.addAll(incoming);
    demo = expectedDemo;
    lastSynced = reports
        .map((r) => r.generatedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    connectionLost = false;
    notifyListeners();
    return true;
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  BandDay get today => week().days.last;

  /// Explicit waking-day coverage must come from acquisition/confirmed wake
  /// context. Daily v0 files have no such minute labels, so yield no suggestion.
  /// The built-in demo authors a complete synthetic 8 AM–8 PM waking window.
  BandSittingRecording sittingDay({bool completeWakingDay = false}) {
    final day = today;
    return BandSittingRecording.fromMinutes(
      date: day.date,
      minutes: day.minutes,
      completeWakingDay: demoOnly || completeWakingDay,
      demo: demo,
    );
  }

  Future<bool> pair(BandDevice d) async {
    if (!await client.pair(d)) return false;
    paired = true;
    bandName = d.name;
    notifyListeners();
    return true;
  }

  /// A minute record arrived.
  void addMinute(BandMinute m) {
    if (_reports.containsKey(_day(m.at))) {
      return; // A whole-day file already owns this date.
    }
    _minutes.add(m);
    lastSynced = m.at;
    connectionLost = false;
    notifyListeners();
  }

  void setConnectionLost(bool v) {
    connectionLost = v;
    notifyListeners();
  }

  /// "Try a recorded demo": a saved week replaces any live minutes in view; nothing is saved from it.
  void setDemo(bool on) {
    _reports.clear();
    demo = on;
    if (on) {
      _minutes
        ..clear()
        ..addAll(recordedDemoMinutes(_now()));
      lastSynced = _minutes.last.at;
    } else {
      _minutes.clear();
      lastSynced = null;
    }
    notifyListeners();
  }

  /// "Unpair": the band days on this phone are erased. Saved answers stay.
  Future<void> unpair() async {
    await client.unpair();
    paired = false;
    bandName = null;
    demo = false;
    connectionLost = false;
    lowPower = null;
    lastSynced = null;
    _minutes.clear();
    _reports.clear();
    notifyListeners();
  }

  void setHidden(bool v) {
    hiddenFromRoom = v;
    notifyListeners();
  }
}
