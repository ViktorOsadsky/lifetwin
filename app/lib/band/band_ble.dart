import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'band_data.dart';
import 'band_file.dart';
import 'band_store.dart';

/// The band's Bluetooth service, exactly as its firmware 0.8 defines it:
/// LifeTwin-band-full-code/arduino/lifetwin_band/ble_service.h and
/// LifeTwin-band-full-code/docs/band-ble-contract.md.
abstract final class BandGatt {
  static const _base = '-7b2a-4f0e-9a51-0d1e2c3b4a50';
  static const service = '4c540001$_base';

  /// Read: 10 bytes, [BandInfo].
  static const info = '4c540002$_base';

  /// Write (with response): [bandClockBytes], on every connection.
  static const clock = '4c540003$_base';

  /// Write (with response): one control code, see the constants below.
  static const control = '4c540004$_base';

  /// Read: a headline JSON of at most 512 bytes. Notify: the file asked for through [control], as
  /// text chunks of at most 180 bytes every 25 ms, then `<EOF>`.
  static const summary = '4c540008$_base';
}

/// Control codes (first byte written to [BandGatt.control]).
const bandSendIndex = 0x0D; // -> {"schema":"lifetwin.band_index.v0","days":[...]} + <EOF>
const bandSendDay = 0x0C; // + "YYYY-MM-DD" -> one lifetwin.band_day.v0 file + <EOF>
const bandSaveStanding = 0x05;
const bandSaveSitting = 0x06;
// 0x0E + date deletes a day on the band; the app never sends it automatically.

/// The five characters the band sends as the last notification of every file.
const bandEndMarker = [0x3C, 0x45, 0x4F, 0x46, 0x3E]; // <EOF>

/// The band keeps at most this many days that the app asks for (the newest).
const bandMaxDays = 14;

/// The band's 10-byte Info value: `fw_major, fw_minor, record_format, record_size, capacity u16,
/// stored_minutes u16, posture_state, step_settings` (u16 little-endian).
class BandInfo {
  BandInfo(List<int> b)
    : assert(b.length >= 10),
      fwMajor = b[0],
      fwMinor = b[1],
      recordFormat = b[2],
      recordSize = b[3],
      capacity = b[4] | b[5] << 8,
      storedMinutes = b[6] | b[7] << 8,
      postureState = b[8],
      stepSettings = b[9];

  final int fwMajor, fwMinor, recordFormat, recordSize, capacity, storedMinutes, postureState, stepSettings;

  /// Day files over Bluetooth need record format 2 and firmware 0.8 or later.
  bool get supported => recordFormat == 2 && (fwMajor > 0 || fwMinor >= 8);

  /// Bit 4 of posture_state: both the standing and the sitting positions are saved and valid.
  bool get positionsSaved => postureState & 4 != 0;
}

/// The clock value: unix seconds u32 LE, then the zone in minutes east of UTC, i16 LE.
List<int> bandClockBytes(DateTime now) {
  final b = ByteData(6)
    ..setUint32(0, now.millisecondsSinceEpoch ~/ 1000, Endian.little)
    ..setInt16(4, now.timeZoneOffset.inMinutes, Endian.little);
  return b.buffer.asUint8List();
}

/// A Bluetooth failure, in words for the person: never values, dates or device identifiers.
class BandTransferFailure implements Exception {
  const BandTransferFailure(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

const bandFirmwareUpdateNeeded = BandTransferFailure(
  'Your band needs a firmware update before it can send its days. Ask the person who built it to '
  'install firmware 0.8 or later, then try again. You can still import a band file.',
);

// --- The Bluetooth plugin, behind the smallest interface the client needs (tests pass a fake). ---

enum BleAdapterState { on, off, unauthorized, unsupported }

class BleAdvert {
  const BleAdvert({required this.id, this.name = '', this.rssi = 0, this.services = const []});
  final String id, name;
  final int rssi;
  final List<String> services;
}

abstract class BleRadio {
  Future<BleAdapterState> adapterState();

  /// Bands advertising [service], found within [timeout].
  Future<List<BleAdvert>> scan({required String service, required Duration timeout});
  Future<BleLink> connect(String id, {required Duration timeout, required int mtu});
}

abstract class BleLink {
  Future<List<int>> read(String characteristic);

  /// A write with response (the band's clock and control characteristics are WRITE).
  Future<void> write(String characteristic, List<int> value);

  /// Turns notifications on; a broadcast stream of their values.
  Future<Stream<List<int>>> subscribe(String characteristic);

  /// Completes when the band disconnects (or [disconnect] is called).
  Future<void> get disconnected;
  Future<void> disconnect();
}

// --- Reassembly. ---

const _tooBig = BandTransferFailure('The band sent more than one delivery can hold.');

/// Collects one file's text chunks into complete JSON values (braces balanced, strings and escapes
/// respected; bytes outside a value skipped) and notices `<EOF>`. Throws on oversize.
class BandJsonAssembler {
  BandJsonAssembler({this.maxBytes = bandBleMaxFileBytes});
  final int maxBytes;
  final _value = <int>[];
  int _total = 0, _depth = 0;
  bool _inString = false, _escape = false;

  /// `<EOF>` arrived (as its own notification, or glued to the end of the last one, outside a value).
  bool ended = false;

  /// Bytes of a value have arrived but the value has not ended.
  bool get midValue => _value.isNotEmpty;

  List<Uint8List> add(List<int> chunk) {
    _total += chunk.length;
    if (_total > maxBytes) throw _tooBig;
    if (_equals(chunk, bandEndMarker)) {
      ended = true;
      return const [];
    }
    final out = <Uint8List>[];
    for (final b in chunk) {
      if (_value.isEmpty) {
        if (b != 0x7B && b != 0x5B) continue; // outside a value: skip until { or [
        _depth = 0;
        _inString = _escape = false;
      }
      _value.add(b);
      if (_inString) {
        if (_escape) {
          _escape = false;
        } else if (b == 0x5C) {
          _escape = true;
        } else if (b == 0x22) {
          _inString = false;
        }
      } else if (b == 0x22) {
        _inString = true;
      } else if (b == 0x7B || b == 0x5B) {
        _depth++;
      } else if (b == 0x7D || b == 0x5D) {
        if (--_depth == 0) {
          out.add(Uint8List.fromList(_value));
          _value.clear();
        }
      }
    }
    if (!midValue && chunk.length > bandEndMarker.length) {
      ended = _equals(chunk.sublist(chunk.length - bandEndMarker.length), bandEndMarker);
    }
    return out;
  }

  static bool _equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One file: a day is about 3.9 KB.
const bandBleMaxFileBytes = 64 * 1024;

class _Incomplete implements Exception {
  const _Incomplete();
}

/// The activity band over Bluetooth (firmware 0.8): scan by the service UUID, connect, read Info,
/// set the clock, then ask for the index (`0D`) and each of the newest 14 days (`0C` + date) as
/// `<EOF>`-ended JSON files on the summary characteristic. Every day goes through `parseBandFile`,
/// like a band file. Nothing received is stored or sent anywhere; the store keeps it in phone memory.
/// The app never deletes days on the band (`0E`).
class BleBandClient implements BandClient {
  BleBandClient(
    this.radio, {
    DateTime Function()? now,
    this.namePrefix = 'LifeTwin Band',
    this.scanWindow = const Duration(seconds: 8),
    this.connectTimeout = const Duration(seconds: 15),
    this.clockSettle = const Duration(milliseconds: 400),
    this.firstByteTimeout = const Duration(seconds: 10),
    this.gapTimeout = const Duration(seconds: 12),
    this.maxFileBytes = bandBleMaxFileBytes,
  }) : _now = now ?? DateTime.now;

  final BleRadio radio;
  final DateTime Function() _now;
  final String namePrefix;

  /// [clockSettle]: the band applies the clock in its main loop. [firstByteTimeout]: from a command
  /// to its first notification. [gapTimeout]: the longest silence within a file. There is no total
  /// cap: 14 days take ~8–70 s depending on the link.
  final Duration scanWindow, connectTimeout, clockSettle, firstByteTimeout, gapTimeout;
  final int maxFileBytes;

  BleLink? _link;
  Stream<List<int>>? _summary;

  /// The band's Info as read on connect.
  BandInfo? info;

  @override
  Future<BluetoothState> bluetooth() async {
    try {
      return switch (await radio.adapterState()) {
        BleAdapterState.on => BluetoothState.on,
        BleAdapterState.unauthorized => BluetoothState.notAllowed,
        _ => BluetoothState.off,
      };
    } catch (_) {
      return BluetoothState.off;
    }
  }

  @override
  Future<List<BandDevice>> scan({Duration timeout = const Duration(seconds: 20)}) async {
    final List<BleAdvert> found;
    try {
      found = await radio.scan(service: BandGatt.service, timeout: timeout < scanWindow ? timeout : scanWindow);
    } catch (_) {
      return const [];
    }
    final byId = <String, BandDevice>{};
    for (final a in found) {
      if (!a.services.any((s) => s.toLowerCase() == BandGatt.service)) continue;
      if (a.name.isNotEmpty && !a.name.startsWith(namePrefix)) continue;
      byId[a.id] = BandDevice(name: a.name.isEmpty ? namePrefix : a.name, strength: a.rssi, id: a.id);
    }
    return byId.values.toList()..sort((a, b) => b.strength.compareTo(a.strength));
  }

  /// Connects, reads Info (firmware 0.8 and record format 2 or a [bandFirmwareUpdateNeeded]
  /// failure), turns on the summary notifications and sets the band's clock.
  @override
  Future<bool> pair(BandDevice device) async {
    await _drop();
    final BandInfo band;
    try {
      final link = await radio.connect(device.id, timeout: connectTimeout, mtu: 256);
      _link = link;
      final raw = await link.read(BandGatt.info);
      if (raw.length < 10) {
        await _drop();
        throw bandFirmwareUpdateNeeded;
      }
      band = BandInfo(raw);
      if (!band.supported) {
        await _drop();
        throw bandFirmwareUpdateNeeded;
      }
      _summary = await link.subscribe(BandGatt.summary);
      await link.write(BandGatt.clock, bandClockBytes(_now()));
      await Future<void>.delayed(clockSettle);
    } on BandTransferFailure {
      rethrow;
    } catch (_) {
      await _drop();
      throw const BandTransferFailure('Mochi couldn’t link to the band. Keep it close and try again.');
    }
    info = band;
    return true;
  }

  /// The newest 14 days on the band as one delivery. Each file that arrives incomplete, garbled or
  /// rejected by the parser is asked for once more, then the whole delivery fails; a band that stops
  /// or disconnects fails at once. Nothing is returned partially.
  @override
  Future<List<BandDayReport>> fetchDays() async {
    final link = _link, summary = _summary;
    if (link == null || summary == null) {
      throw const BandTransferFailure('The band isn’t linked. Try again.');
    }
    final index = await _twice(() async => _indexDays(await _file(link, summary, const [bandSendIndex])));
    if (index.isEmpty) return const [];
    final files = <Uint8List>[];
    for (final date in index) {
      final file = await _twice(() async {
        final bytes = await _file(link, summary, [bandSendDay, ...ascii.encode(date)]);
        final value = jsonDecode(utf8.decode(bytes));
        if (value is Map && value.containsKey('error')) {
          if (value['error'] == 'no_file_for_that_date') return null;
          throw const BandTransferFailure('The band couldn’t send one of its days. Try again.');
        }
        parseBandFile(bytes); // this day alone, so a failure asks for it again
        return bytes;
      });
      if (file != null) files.add(file);
    }
    if (files.isEmpty) return const [];
    return parseBandFile(_bundle(files));
  }

  static Future<T> _twice<T>(Future<T> Function() fetch) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await fetch();
      } on _Incomplete {
        if (attempt == 1) throw const BandTransferFailure('The band’s data arrived incomplete. Try again.');
      } on BandFileFailure {
        if (attempt == 1) rethrow;
      }
    }
  }

  /// The index's dates, newest [bandMaxDays], oldest first.
  static List<String> _indexDays(Uint8List bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    final days = value is Map && value['schema'] == 'lifetwin.band_index.v0' ? value['days'] : null;
    if (days is! List || days.any((d) => d is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d))) {
      throw const BandTransferFailure('The band sent a list of days Mochi can’t read.');
    }
    final sorted = days.cast<String>().toSet().toList()..sort();
    return sorted.sublist(sorted.length > bandMaxDays ? sorted.length - bandMaxDays : 0);
  }

  /// Writes [command] to Control and returns the one JSON value that arrives before `<EOF>`.
  Future<Uint8List> _file(BleLink link, Stream<List<int>> summary, List<int> command) async {
    final assembler = BandJsonAssembler(maxBytes: maxFileBytes);
    final values = <Uint8List>[];
    final done = Completer<Uint8List>();
    var seen = false;
    Timer? timer;
    void fail(Object error) {
      timer?.cancel();
      if (!done.isCompleted) done.completeError(error);
    }

    void arm(Duration wait) {
      timer?.cancel();
      timer = Timer(
        wait,
        () => fail(
          seen
              ? const BandTransferFailure('The band stopped sending. Keep it close and try again.')
              : const BandTransferFailure('The band didn’t answer. Keep it close and try again.'),
        ),
      );
    }

    final sub = summary.listen((chunk) {
      seen = true;
      try {
        values.addAll(assembler.add(chunk));
      } on BandTransferFailure catch (e) {
        fail(e);
        return;
      }
      if (!assembler.ended) {
        arm(gapTimeout);
        return;
      }
      timer?.cancel();
      if (done.isCompleted) return;
      if (assembler.midValue || values.length != 1) {
        done.completeError(const _Incomplete());
      } else {
        done.complete(values.single);
      }
    });
    unawaited(
      link.disconnected.then(
        (_) => fail(const BandTransferFailure('The band disconnected. Keep it close and try again.')),
      ),
    );
    try {
      arm(firstByteTimeout);
      await link.write(BandGatt.control, command);
    } catch (_) {
      fail(const BandTransferFailure('The band didn’t answer. Keep it close and try again.'));
    }
    try {
      final value = await done.future;
      try {
        jsonDecode(utf8.decode(value));
      } on FormatException {
        throw const _Incomplete();
      }
      return value;
    } finally {
      timer?.cancel();
      await sub.cancel();
    }
  }

  static Uint8List _bundle(List<Uint8List> days) {
    final out = BytesBuilder(copy: false)..add(utf8.encode('{"schema":"lifetwin.band_days.v0","days":['));
    for (var i = 0; i < days.length; i++) {
      if (i > 0) out.addByte(0x2C);
      out.add(days[i]);
    }
    out.add(utf8.encode(']}'));
    return out.takeBytes();
  }

  /// Saves the standing or sitting position on the band (`05`/`06`): it waits ~5 s, then needs the
  /// person to hold still ~3 s. False when no band is linked.
  @override
  Future<bool> savePosition({required bool standing}) async {
    final link = _link;
    if (link == null) return false;
    try {
      await link.write(BandGatt.control, [standing ? bandSaveStanding : bandSaveSitting]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _drop() async {
    final link = _link;
    _link = null;
    _summary = null;
    info = null;
    if (link != null) {
      try {
        await link.disconnect();
      } catch (_) {}
    }
  }

  @override
  Future<void> unpair() => _drop();

  @override
  Stream<BandMinute> minuteRecords() => const Stream.empty();
}
