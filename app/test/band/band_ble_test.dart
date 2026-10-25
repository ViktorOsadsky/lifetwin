import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/band/band_ble.dart';
import 'package:lifesim/band/band_file.dart';
import 'package:lifesim/band/band_store.dart';

// The real band's layout (4c5400XX…), with a send command set, since the real one is not known yet.
final _real = lifeTwinBandProfile;
final _profile = BandBleProfile(
  service: _real.service,
  info: _real.info,
  send: _real.send,
  sendCommand: utf8.encode('send'),
  data: _real.data,
  live: _real.live,
);
const _infoBytes = [0x00, 0x07, 0x02, 0x0c, 0xa0, 0x05, 0x0e, 0x00, 0x07, 0x0b];
final _now = DateTime(2026, 10, 25, 12);

/// A measured day in the band_day.v0 shape (the synthetic fixture, re-dated, demo flag removed).
Map<String, dynamic> _day(String date) {
  final d = jsonDecode(File('test/fixtures/band/valid_day.json').readAsStringSync()) as Map<String, dynamic>;
  return d
    ..remove('synthetic_demo')
    ..['date'] = date
    ..['generated_at'] = '${date}T23:59:00-07:00';
}

final _threeDays = [
  for (final d in ['2026-10-22', '2026-10-23', '2026-10-24']) _day(d),
];

/// One JSON value per day, back to back, cut into notifications of MTU − 3 bytes.
List<List<int>> _frames(List<Map<String, dynamic>> days, {int size = 253}) {
  final bytes = utf8.encode(days.map(jsonEncode).join());
  return [
    for (var i = 0; i < bytes.length; i += size) bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size),
  ];
}

/// A fake band: answers the send command with [answer]'s frames for that attempt (null: silence).
class FakeBand implements BleLink {
  FakeBand({this.answer, this.dropAfter});
  List<List<int>>? Function(int attempt)? answer;

  /// Disconnects after sending this many frames.
  int? dropAfter;
  final writes = <(String, List<int>)>[];
  final reads = <String>[];
  final _data = StreamController<List<int>>.broadcast();
  final _gone = Completer<void>();
  bool get connected => !_gone.isCompleted;
  int _attempt = 0;

  @override
  Future<List<int>> read(String c) async {
    reads.add(c);
    if (c == _real.info) return _infoBytes;
    return List.filled(20, 0);
  }

  @override
  Future<void> write(String c, List<int> value) async {
    writes.add((c, value));
    final frames = answer?.call(_attempt++);
    if (frames == null) return;
    unawaited(() async {
      var sent = 0;
      for (final f in frames) {
        await Future<void>.delayed(Duration.zero);
        if (!connected) return;
        _data.add(f);
        if (++sent == dropAfter) {
          _gone.complete();
          return;
        }
      }
    }());
  }

  @override
  Future<Stream<List<int>>> subscribe(String c) async => c == _real.data ? _data.stream : const Stream.empty();

  @override
  Future<void> get disconnected => _gone.future;

  @override
  Future<void> disconnect() async {
    if (connected) _gone.complete();
  }
}

class FakeRadio implements BleRadio {
  FakeRadio(this.band, {this.state = BleAdapterState.on, List<BleAdvert>? adverts})
    : adverts =
          adverts ??
          [
            BleAdvert(id: 'band-1', name: 'LifeTwin Band', rssi: -50, services: [_real.service.toUpperCase()]),
            const BleAdvert(id: 'speaker', name: 'Kitchen speaker', rssi: -40, services: ['180d']),
            BleAdvert(id: 'other', name: 'Someone else', rssi: -30, services: [_real.service]),
          ];
  final FakeBand band;
  BleAdapterState state;
  List<BleAdvert> adverts;
  String? scannedFor, connectedTo;
  bool failConnect = false;

  @override
  Future<BleAdapterState> adapterState() async => state;

  @override
  Future<List<BleAdvert>> scan({required String service, required Duration timeout}) async {
    scannedFor = service;
    return adverts;
  }

  @override
  Future<BleLink> connect(String id, {required Duration timeout, required int mtu}) async {
    if (failConnect) throw StateError('no');
    connectedTo = id;
    return band;
  }
}

BleBandClient _client(FakeRadio radio, {BandBleProfile? profile, int maxBytes = bandBleMaxBytes}) => BleBandClient(
  radio,
  profile: profile ?? _profile,
  firstByteTimeout: const Duration(milliseconds: 200),
  idleGap: const Duration(milliseconds: 60),
  maxBytes: maxBytes,
);

void main() {
  group('BleBandClient with a fake band', () {
    test('scan -> connect -> info -> fetch 3 days -> import', () async {
      final band = FakeBand(answer: (_) => _frames(_threeDays));
      final radio = FakeRadio(band);
      final store = BandStore(_client(radio), now: () => _now);

      expect(await store.client.bluetooth(), BluetoothState.on);
      final found = await store.client.scan();
      expect(radio.scannedFor, _real.service);
      expect(found.map((d) => d.name), ['LifeTwin Band'], reason: 'service UUID and name prefix both filter');

      expect(await store.pair(found.single), isTrue);
      expect(radio.connectedTo, 'band-1');
      expect((store.client as BleBandClient).info, _infoBytes);
      expect(band.writes.single.$1, _real.send);
      expect(store.paired, isTrue);
      expect(store.pairProblem, isNull);
      expect(store.fileReports.map((r) => r.day), ['2026-10-22', '2026-10-23', '2026-10-24']);
      expect(store.demo, isFalse);
      expect(store.live, isTrue);
      expect(store.sourceLabel, 'Bluetooth');

      await store.unpair();
      expect(band.connected, isFalse);
      expect(store.fileReports, isEmpty);
    });

    test('one band_days bundle in a single value is accepted as-is', () async {
      final bundle = utf8.encode(jsonEncode({'schema': 'lifetwin.band_days.v0', 'days': _threeDays}));
      final band = FakeBand(answer: (_) => [bundle]);
      final store = BandStore(_client(FakeRadio(band)), now: () => _now);
      expect(await store.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1')), isTrue);
      expect(store.fileReports, hasLength(3));
    });

    test('pairing replaces the built-in recorded demo only once the band data checks out', () async {
      final band = FakeBand(answer: (_) => _frames(_threeDays));
      final store = BandStore(_client(FakeRadio(band)), now: () => _now)..setDemo(true);
      expect(await store.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1')), isTrue);
      expect(store.demo, isFalse);
      expect(store.fileReports, hasLength(3));
    });

    test('a lost frame is asked for again once, then succeeds', () async {
      final frames = _frames(_threeDays);
      final band = FakeBand(answer: (attempt) => attempt == 0 ? ([...frames]..removeAt(3)) : frames);
      final store = BandStore(_client(FakeRadio(band)), now: () => _now);
      expect(
        await store.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1')),
        isTrue,
        reason: '${store.pairProblem}',
      );
      expect(band.writes, hasLength(2));
      expect(store.fileReports, hasLength(3));
    });

    test('lost and out-of-order frames twice: an error, nothing imported', () async {
      final frames = _frames(_threeDays);
      final band = FakeBand(
        answer: (attempt) =>
            attempt == 0 ? ([...frames]..removeAt(5)) : [frames[0], frames[2], frames[1], ...frames.skip(3)],
      );
      final store = BandStore(_client(FakeRadio(band)), now: () => _now);
      expect(await store.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1')), isFalse);
      expect(band.writes, hasLength(2), reason: 'retried exactly once');
      expect(store.pairProblem, contains('incomplete'));
      expect(store.paired, isFalse);
      expect(store.fileReports, isEmpty);
      expect(band.connected, isFalse);
    });

    test('Bluetooth off, not allowed, or the plugin failing', () async {
      final radio = FakeRadio(FakeBand(), state: BleAdapterState.off);
      final client = _client(radio);
      expect(await client.bluetooth(), BluetoothState.off);
      radio.state = BleAdapterState.unsupported;
      expect(await client.bluetooth(), BluetoothState.off);
      radio.state = BleAdapterState.unauthorized;
      expect(await client.bluetooth(), BluetoothState.notAllowed, reason: 'permission denied -> Open Settings');
    });

    test('a band that cannot be linked: a plain reason, not paired', () async {
      final radio = FakeRadio(FakeBand())..failConnect = true;
      final store = BandStore(_client(radio), now: () => _now);
      expect(await store.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1')), isFalse);
      expect(store.pairProblem, contains('couldn’t link'));
      expect(store.pairProblem, isNot(contains('band-1')));
    });

    test('timeout: the band never answers the send command', () async {
      final band = FakeBand(answer: (_) => null);
      final store = BandStore(_client(FakeRadio(band)), now: () => _now);
      expect(await store.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1')), isFalse);
      expect(store.pairProblem, contains('didn’t answer'));
      expect(store.fileReports, isEmpty);
      expect(band.connected, isFalse);
    });

    test('disconnect mid-transfer: nothing imported', () async {
      final band = FakeBand(answer: (_) => _frames(_threeDays), dropAfter: 10);
      final store = BandStore(_client(FakeRadio(band)), now: () => _now);
      expect(await store.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1')), isFalse);
      expect(store.pairProblem, contains('disconnected'));
      expect(store.fileReports, isEmpty);
      expect(store.paired, isFalse);
    });

    test('an oversize payload is rejected without asking again', () async {
      final band = FakeBand(answer: (_) => _frames(_threeDays));
      final store = BandStore(_client(FakeRadio(band), maxBytes: 4000), now: () => _now);
      expect(await store.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1')), isFalse);
      expect(band.writes, hasLength(1));
      expect(store.pairProblem, contains('more than one delivery'));
      expect(store.fileReports, isEmpty);
    });

    test('one day the parser rejects rejects the whole delivery', () async {
      final days = [..._threeDays];
      days[1] = {...days[1], 'steps': (days[1]['steps'] as int) + 1}; // totals no longer match
      final band = FakeBand(answer: (_) => _frames(days));
      final store = BandStore(_client(FakeRadio(band)), now: () => _now);
      expect(await store.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1')), isFalse);
      expect(store.pairProblem, contains('nothing was added'));
      expect(band.writes, hasLength(2), reason: 'asked once more in case a notification was lost');
      expect(store.fileReports, isEmpty, reason: 'the two good days are not imported either');
      expect(band.connected, isFalse);
    });

    test('with no send command known (the default), nothing is written and silence means no days', () async {
      expect(lifeTwinBandProfile.trigger, BandTrigger.none);
      final band = FakeBand();
      final store = BandStore(_client(FakeRadio(band), profile: lifeTwinBandProfile), now: () => _now);
      expect(await store.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1')), isTrue);
      expect(band.writes, isEmpty, reason: 'no blind commands to the real band');
      expect(store.fileReports, isEmpty);
    });

    test('live counters are passed through raw', () async {
      final band = FakeBand(answer: (_) => _frames(_threeDays));
      final client = _client(FakeRadio(band));
      await client.pair(const BandDevice(name: 'LifeTwin Band', id: 'band-1'));
      expect(await client.liveBytes(), isA<Stream<List<int>>>());
    });
  });

  group('BandJsonAssembler framings', () {
    final a = utf8.encode('{"a":"}{\\"","b":[1,{"c":2}]}');
    final b = utf8.encode('{"d":1}');

    test('JSON stream: values split anywhere, junk between them skipped', () {
      final asm = BandJsonAssembler(_profile);
      final out = <Uint8List>[];
      final all = [...a, 0x0A, 0x00, ...b];
      for (var i = 0; i < all.length; i += 3) {
        out.addAll(asm.add(all.sublist(i, i + 3 > all.length ? all.length : i + 3)));
      }
      expect(out.map(utf8.decode), [utf8.decode(a), utf8.decode(b)]);
      expect(asm.midValue, isFalse);
      asm.add(b.sublist(0, 3));
      expect(asm.midValue, isTrue);
    });

    test('terminated', () {
      final asm = BandJsonAssembler(BandBleProfile(service: 's', data: 'd', framing: BandFraming.terminated));
      final out = [
        ...asm.add([...a, 0x0A, ...b.sublist(0, 2)]),
        ...asm.add([...b.sublist(2), 0x0A]),
      ];
      expect(out.map(utf8.decode), [utf8.decode(a), utf8.decode(b)]);
    });

    test('length-prefixed', () {
      final asm = BandJsonAssembler(
        BandBleProfile(service: 's', data: 'd', framing: BandFraming.lengthPrefixed, lengthBytes: 2),
        maxBytes: 1000,
      );
      List<int> le(int n) => [n & 0xff, n >> 8];
      final all = [...le(a.length), ...a, ...le(b.length), ...b];
      final out = [...asm.add(all.sublist(0, 1)), ...asm.add(all.sublist(1, 9)), ...asm.add(all.sublist(9))];
      expect(out.map(utf8.decode), [utf8.decode(a), utf8.decode(b)]);
      expect(() => asm.add(le(60000)), throwsA(isA<BandTransferFailure>()), reason: 'declared size over the cap');
    });
  });

  test('parseBandFile is still the only validation', () {
    expect(() => parseBandFile(Uint8List.fromList(utf8.encode('{"schema":"x"}'))), throwsA(isA<BandFileFailure>()));
  });
}
