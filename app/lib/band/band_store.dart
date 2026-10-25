import 'package:flutter/foundation.dart';

import 'band_ble.dart';
import 'band_data.dart';
import 'band_demo_data.dart';
import 'band_file.dart';
import 'band_sitting.dart';

/// Bluetooth as the app can see it.
enum BluetoothState { on, off, notAllowed }

class BandDevice {
  const BandDevice({required this.name, this.strength = 0, this.id = ''});

  /// The phone's handle for this band (never shown on screen).
  final String id;

  /// The band's Bluetooth name (firmware, assumed "LifeTwin Band").
  final String name;

  /// Signal strength, higher is closer: strongest first.
  final int strength;
}

/// The activity band over Bluetooth: [BleBandClient] (band_ble.dart) in the app, [StubBandClient] in
/// tests. Wording on screen is "Bluetooth", "pair", "band": never "BLE", "GATT", "device ID" or "ESP32".
abstract class BandClient {
  Future<BluetoothState> bluetooth();

  /// Searches for up to [timeout]; empty when nothing is found.
  Future<List<BandDevice>> scan({
    Duration timeout = const Duration(seconds: 20),
  });
  /// Links to the band; false or a [BandTransferFailure] when it cannot.
  Future<bool> pair(BandDevice device);

  /// The whole days the linked band sends, validated as one delivery by `parseBandFile`. Throws
  /// [BandTransferFailure] or [BandFileFailure]; empty when it has nothing to send.
  Future<List<BandDayReport>> fetchDays();
  Future<void> unpair();

  /// Minute records, as they arrive (buffered minutes resume from the last unsent one).
  Stream<BandMinute> minuteRecords();
}

/// The app pairs over Bluetooth (flutter_blue_plus, band_ble_fbp.dart).
const bandBluetoothAvailable = true;

class StubBandClient implements BandClient {
  StubBandClient({
    this.state = BluetoothState.on,
    this.devices = const [],
    this.pairs = true,
    this.days = const [],
  });

  BluetoothState state;
  List<BandDevice> devices;
  bool pairs;
  List<BandDayReport> days;
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
  Future<List<BandDayReport>> fetchDays() async => days;

  @override
  Future<void> unpair() async {}

  @override
  Stream<BandMinute> minuteRecords() => const Stream.empty();
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

  /// The built-in recorded demo (14 synthetic days kept as reports), as opposed to an imported demo file.
  bool _builtInDemo = false;
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
      : paired
      ? 'Bluetooth'
      : hasImportedFile
      ? 'Imported band file'
      : 'Bluetooth';
  DateTime? lastSynced;

  List<BandMinute> get minutes => List.unmodifiable(_minutes);

  /// Live data only: false for the recorded demo.
  bool get live => (paired || hasImportedFile) && !demo;

  /// The recorded demo is all there is: no paired band and no imported file (those take priority).
  bool get demoOnly => demo && !paired && (_builtInDemo || !hasImportedFile);

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
    // The built-in demo's last day is yesterday, so its week ends there (not on an empty today).
    final end = _builtInDemo
        ? DateTime(_now().year, _now().month, _now().day - 1)
        : _now();
    final legacy = BandWeek.from(_minutes, end);
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
    final today = _day(_now().toLocal());
    if (reports.any((r) => r.day.compareTo(today) > 0)) {
      throw const BandFileFailure(
        'A band report is dated after today. Check the date on the band.',
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
      minutes: _builtInDemo ? _minutes : day.minutes,
      completeWakingDay: demoOnly || completeWakingDay,
      demo: demo,
    );
  }

  /// Why the last pairing failed, in plain words; null when it worked or no reason is known.
  String? pairProblem;

  /// Links to the band and imports the days it sends, as one whole delivery like a file: any failure
  /// (link, transfer, a day the parser rejects) disconnects and imports nothing. Nothing is saved to
  /// the profile here; only the person's "Yes" does that.
  Future<bool> pair(BandDevice d) async {
    pairProblem = null;
    final wasDemo = _builtInDemo;
    try {
      if (!await client.pair(d)) return false;
      final days = await client.fetchDays();
      if (days.isNotEmpty) {
        if (wasDemo) setDemo(false); // real band days replace the built-in recorded demo
        importReports(days);
      }
    } on Exception catch (e) {
      if (wasDemo && !demo) setDemo(true);
      pairProblem = e is BandFileFailure
          ? 'The band’s data didn’t check out, so nothing was added. ${e.reason}'
          : e is BandTransferFailure
          ? e.reason
          : 'Mochi couldn’t link to the band. Try again.';
      await client.unpair();
      notifyListeners();
      return false;
    }
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
    _minutes.clear();
    demo = on;
    _builtInDemo = on;
    lastSynced = null;
    if (on) {
      final reports = bandDemoReports(_now());
      for (final r in reports) {
        _reports[r.day] = r;
      }
      _minutes.addAll(bandDemoMinutes(reports.last));
      lastSynced = reports.last.generatedAt;
    }
    notifyListeners();
  }

  /// "Unpair": the band days on this phone are erased. Saved answers stay.
  Future<void> unpair() async {
    await client.unpair();
    paired = false;
    bandName = null;
    demo = false;
    _builtInDemo = false;
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
