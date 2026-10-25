import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'band_data.dart';
import 'band_file.dart';
import 'band_store.dart';

/// The band's Bluetooth layout as observed on the real band, and what its firmware side told us
/// (docs/band-ble-contract.md). The firmware is not in this repo; unconfirmed parts are the constants
/// below, all used through [lifeTwinBandProfile].
const _base = '-7b2a-4f0e-9a51-0d1e2c3b4a50';

/// UNCONFIRMED: what makes the band send its days. Until the firmware side gives the exact bytes the
/// phone writes nothing and only listens (an unknown command is never written to the band).
const String bandSendCharacteristic = '4c540003$_base';
const List<int>? bandSendCommand = null;

/// UNCONFIRMED: the band has no clock, so the phone writes the time and time zone on every connection,
/// before the send command; the band builds no day files until then. Null skips the write.
const String bandClockCharacteristic = '4c540003$_base';
const List<int> Function(DateTime now)? bandClockCommand = null;

/// After the file the band sends these 5 characters as one last notification.
const bandEndMarker = [0x3C, 0x45, 0x4F, 0x46, 0x3E]; // <EOF>

const lifeTwinBandProfile = BandBleProfile(
  service: '4c540001$_base',
  info: '4c540002$_base',
  send: bandSendCharacteristic,
  sendCommand: bandSendCommand,
  clock: bandClockCharacteristic,
  clockCommand: bandClockCommand,
  data: '4c540005$_base',
  live: '4c540007$_base',
);

/// How notifications on [BandBleProfile.data] carry JSON.
enum BandFraming {
  /// UTF-8 JSON split across notifications (or one per notification); a value ends when its braces
  /// balance. Bytes outside a value are skipped.
  jsonStream,

  /// Each JSON value is preceded by its length, [BandBleProfile.lengthBytes] little-endian bytes.
  lengthPrefixed,
}

/// How the phone asks the band for its days.
enum BandTrigger { none, write, read }

class BandBleProfile {
  const BandBleProfile({
    required this.service,
    required this.data,
    this.namePrefix = 'LifeTwin Band',
    this.info,
    this.send,
    this.sendCommand,
    this.readToSend = false,
    this.clock,
    this.clockCommand,
    this.live,
    this.framing = BandFraming.jsonStream,
    this.endMarker = bandEndMarker,
    this.lengthBytes = 4,
    this.mtu = 256,
  });

  final String service, data, namePrefix;

  /// Read once on connect and kept as raw bytes (its layout is not known, so it is not interpreted).
  final String? info;

  /// The characteristic written with [sendCommand] (or read, when [readToSend]) to start a delivery.
  final String? send;
  final List<int>? sendCommand;
  final bool readToSend;

  /// Written with [clockCommand] of the phone's time on every connection, before the send command.
  final String? clock;
  final List<int> Function(DateTime now)? clockCommand;

  /// Optional live counters (notify): raw bytes only until their layout is known.
  final String? live;
  final BandFraming framing;

  /// The notification that ends a delivery; null: a delivery ends when the band goes quiet.
  final List<int>? endMarker;
  final int lengthBytes;
  final int mtu;

  BandTrigger get trigger => send == null
      ? BandTrigger.none
      : readToSend
      ? BandTrigger.read
      : sendCommand == null
      ? BandTrigger.none
      : BandTrigger.write;
}

/// A Bluetooth failure, in words for the person: never values, dates or device identifiers.
class BandTransferFailure implements Exception {
  const BandTransferFailure(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

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
  Future<void> write(String characteristic, List<int> value);

  /// Turns notifications on; a broadcast stream of their values.
  Future<Stream<List<int>>> subscribe(String characteristic);

  /// Completes when the band disconnects (or [disconnect] is called).
  Future<void> get disconnected;
  Future<void> disconnect();
}

// --- Reassembly. ---

const _tooBig = BandTransferFailure('The band sent more than one delivery can hold.');

/// Collects notifications into complete JSON values, per [BandFraming], and notices the end marker.
/// Throws on oversize.
class BandJsonAssembler {
  BandJsonAssembler(this.profile, {this.maxBytes = bandBleMaxBytes});
  final BandBleProfile profile;
  final int maxBytes;
  final _value = <int>[];
  final _pending = <int>[];
  int _total = 0, _depth = 0;
  bool _inString = false, _escape = false;
  int? _need;

  /// The end marker arrived.
  bool ended = false;

  /// Bytes of a value have arrived but the value has not ended.
  bool get midValue => _value.isNotEmpty || _need != null;

  List<Uint8List> add(List<int> chunk) {
    _total += chunk.length;
    if (_total > maxBytes) throw _tooBig;
    final marker = profile.endMarker;
    if (marker != null && _equals(chunk, marker)) {
      ended = true;
      return const [];
    }
    final out = profile.framing == BandFraming.jsonStream ? _stream(chunk) : _prefixed(chunk);
    // The marker glued to the end of the last data notification, outside any value.
    if (marker != null && !midValue && chunk.length > marker.length) {
      ended = _equals(chunk.sublist(chunk.length - marker.length), marker);
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

  List<Uint8List> _stream(List<int> chunk) {
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
    return out;
  }

  List<Uint8List> _prefixed(List<int> chunk) {
    final out = <Uint8List>[];
    _pending.addAll(chunk);
    var i = 0;
    while (true) {
      if (_need == null) {
        if (_pending.length - i < profile.lengthBytes) break;
        var n = 0;
        for (var k = profile.lengthBytes - 1; k >= 0; k--) {
          n = (n << 8) | _pending[i + k];
        }
        i += profile.lengthBytes;
        if (n > maxBytes) throw _tooBig;
        _need = n;
      }
      final take = (_need! - _value.length).clamp(0, _pending.length - i).toInt();
      _value.addAll(_pending.sublist(i, i + take));
      i += take;
      if (_value.length < _need!) break;
      out.add(Uint8List.fromList(_value));
      _value.clear();
      _need = null;
    }
    _pending.removeRange(0, i);
    return out;
  }
}

/// More than 14 compact days (~3.9 KB each), far below the 5 MB file limit.
const bandBleMaxBytes = 256 * 1024;

class _Incomplete implements Exception {
  const _Incomplete();
}

/// The activity band over Bluetooth: scan by the service UUID and name, connect, set the band's
/// clock, fetch the band's JSON days from [BandBleProfile.data], then the same `parseBandFile`
/// validation as a band file. Nothing received is stored or sent anywhere; the store imports it into
/// phone memory only.
class BleBandClient implements BandClient {
  BleBandClient(
    this.radio, {
    this.profile = lifeTwinBandProfile,
    DateTime Function()? now,
    this.scanWindow = const Duration(seconds: 8),
    this.connectTimeout = const Duration(seconds: 15),
    this.firstByteTimeout = const Duration(seconds: 10),
    this.gapTimeout = const Duration(seconds: 12),
    this.maxBytes = bandBleMaxBytes,
  }) : _now = now ?? DateTime.now;

  final BleRadio radio;
  final BandBleProfile profile;
  final DateTime Function() _now;

  /// [firstByteTimeout]: from the send command to the first notification. [gapTimeout]: the longest
  /// silence between notifications. There is no total cap: 14 days take ~8–70 s depending on MTU.
  final Duration scanWindow, connectTimeout, firstByteTimeout, gapTimeout;
  final int maxBytes;

  BleLink? _link;
  Stream<List<int>>? _data;

  /// The band's `info` value as read on connect, uninterpreted.
  List<int>? info;

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
      found = await radio.scan(service: profile.service, timeout: timeout < scanWindow ? timeout : scanWindow);
    } catch (_) {
      return const [];
    }
    final service = profile.service.toLowerCase();
    final byId = <String, BandDevice>{};
    for (final a in found) {
      if (!a.services.any((s) => s.toLowerCase() == service)) continue;
      if (a.name.isNotEmpty && !a.name.startsWith(profile.namePrefix)) continue;
      final name = a.name.isEmpty ? profile.namePrefix : a.name;
      byId[a.id] = BandDevice(name: name, strength: a.rssi, id: a.id);
    }
    return byId.values.toList()..sort((a, b) => b.strength.compareTo(a.strength));
  }

  /// Connects, turns on the day notifications and sets the band's clock (every connection). Throws
  /// [BandTransferFailure] when it cannot.
  @override
  Future<bool> pair(BandDevice device) async {
    await _drop();
    try {
      final link = await radio.connect(device.id, timeout: connectTimeout, mtu: profile.mtu);
      _link = link;
      if (profile.info case final c?) info = await link.read(c);
      _data = await link.subscribe(profile.data);
      if ((profile.clock, profile.clockCommand) case (final c?, final command?)) {
        await link.write(c, command(_now()));
      }
      return true;
    } catch (_) {
      await _drop();
      throw const BandTransferFailure('Mochi couldn’t link to the band. Keep it close and try again.');
    }
  }

  /// One whole delivery: every JSON value the band sends after the trigger, as one band file.
  /// Incomplete, garbled or rejected data is asked for once more, then fails; a band that stops or
  /// disconnects fails at once. Nothing is returned partially.
  @override
  Future<List<BandDayReport>> fetchDays() async {
    final link = _link, data = _data;
    if (link == null || data == null) {
      throw const BandTransferFailure('The band isn’t linked. Try again.');
    }
    for (var attempt = 0; ; attempt++) {
      try {
        final values = await _receive(link, data);
        if (values.isEmpty) return const [];
        return parseBandFile(_delivery(values));
      } on _Incomplete {
        if (attempt == 1) {
          throw const BandTransferFailure('The band’s data arrived incomplete. Try again.');
        }
      } on BandFileFailure {
        // There is no length or checksum, so a lost notification can still leave balanced JSON that
        // the parser then rejects: ask once more before blaming the data.
        if (attempt == 1) rethrow;
      }
    }
  }

  Future<List<Uint8List>> _receive(BleLink link, Stream<List<int>> data) async {
    final assembler = BandJsonAssembler(profile, maxBytes: maxBytes);
    final values = <Uint8List>[];
    final done = Completer<List<Uint8List>>();
    var seen = false;
    Timer? timer;
    void finish(Object result) {
      timer?.cancel();
      if (done.isCompleted) return;
      result is List<Uint8List> ? done.complete(result) : done.completeError(result);
    }

    void arm(Duration wait) {
      timer?.cancel();
      timer = Timer(wait, () {
        if (!seen) {
          // Nothing asked, nothing sent: no days. Asked and silent: a timeout.
          finish(
            profile.trigger == BandTrigger.none
                ? values
                : const BandTransferFailure('The band didn’t answer. Keep it close and try again.'),
          );
        } else if (profile.endMarker != null) {
          // The band gives up by going quiet: abandon, import nothing.
          finish(const BandTransferFailure('The band stopped sending. Keep it close and try again.'));
        } else {
          finish(assembler.midValue ? const _Incomplete() : values);
        }
      });
    }

    final sub = data.listen((chunk) {
      seen = true;
      try {
        values.addAll(assembler.add(chunk));
      } on BandTransferFailure catch (e) {
        finish(e);
        return;
      }
      if (assembler.ended) {
        finish(assembler.midValue ? const _Incomplete() : values);
      } else {
        arm(gapTimeout);
      }
    });
    unawaited(
      link.disconnected.then(
        (_) => finish(const BandTransferFailure('The band disconnected. Keep it close and try again.')),
      ),
    );
    try {
      arm(firstByteTimeout);
      switch (profile.trigger) {
        case BandTrigger.write:
          await link.write(profile.send!, profile.sendCommand!);
        case BandTrigger.read:
          await link.read(profile.send!);
        case BandTrigger.none:
          break;
      }
    } catch (_) {
      finish(const BandTransferFailure('The band didn’t answer. Keep it close and try again.'));
    }
    try {
      final result = await done.future;
      for (final v in result) {
        try {
          jsonDecode(utf8.decode(v));
        } on FormatException {
          throw const _Incomplete();
        }
      }
      return result;
    } finally {
      timer?.cancel();
      await sub.cancel();
    }
  }

  /// A band_days bundle as-is; otherwise the values wrapped as one, byte for byte.
  static Uint8List _delivery(List<Uint8List> values) {
    if (values.length == 1) {
      final v = jsonDecode(utf8.decode(values.single));
      if (v is Map && v['schema'] == 'lifetwin.band_days.v0') return values.single;
    }
    final out = BytesBuilder(copy: false)..add(utf8.encode('{"schema":"lifetwin.band_days.v0","days":['));
    for (var i = 0; i < values.length; i++) {
      if (i > 0) out.addByte(0x2C);
      out.add(values[i]);
    }
    out.add(utf8.encode(']}'));
    return out.takeBytes();
  }

  /// The optional live counters, raw (their layout is not known yet). Never imported or saved.
  Future<Stream<List<int>>> liveBytes() async {
    final link = _link, c = profile.live;
    if (link == null || c == null) return const Stream.empty();
    return link.subscribe(c);
  }

  Future<void> _drop() async {
    final link = _link;
    _link = null;
    _data = null;
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
