import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/band/band_ble.dart';
import 'package:lifesim/band/band_file.dart';
import 'package:lifesim/band/band_store.dart';

// Firmware 0.8 Info: fw 0.8, record format 2, 12-byte records, capacity 1440, 47 stored minutes,
// no positions saved, step settings 0x0b.
const _info08 = [0x00, 0x08, 0x02, 0x0c, 0xa0, 0x05, 0x2f, 0x00, 0x00, 0x0b];
const _info07 = [0x00, 0x07, 0x02, 0x0c, 0xa0, 0x05, 0x2f, 0x00, 0x07, 0x0b]; // the band probed on 2026-10-25
final _now = DateTime(2026, 10, 25, 12);
const _eof = [0x3C, 0x45, 0x4F, 0x46, 0x3E];
const _device = BandDevice(name: 'LifeTwin Band', id: 'band-1');

/// A measured day in the band_day.v0 shape (the synthetic fixture, re-dated, demo flag removed).
Map<String, dynamic> _day(String date) {
  final d = jsonDecode(File('test/fixtures/band/valid_day.json').readAsStringSync()) as Map<String, dynamic>;
  return d
    ..remove('synthetic_demo')
    ..['date'] = date
    ..['generated_at'] = '${date}T23:59:00-07:00';
}

Map<String, Map<String, dynamic>> _days(List<String> dates) => {for (final d in dates) d: _day(d)};
final _three = ['2026-10-22', '2026-10-23', '2026-10-24'];

/// A fake band running firmware 0.8: Info on 0002, clock on 0003, control on 0004, and every file
/// as chunks of ≤ 180 bytes on 0008 followed by `<EOF>`.
class FakeBand implements BleLink {
  FakeBand({
    Map<String, Map<String, dynamic>>? days,
    this.info = _info08,
    this.tamper,
    this.dropAfter,
    this.extraIndex = const [],
  }) : days = days ?? _days(_three);

  Map<String, Map<String, dynamic>> days;
  List<int> info;

  /// Dates the index lists that have no file (the band answers no_file_for_that_date).
  List<String> extraIndex;

  /// Changes the frames of a file ('index' or a date) on a given attempt; null: silence.
  List<List<int>>? Function(String file, int attempt, List<List<int>> frames)? tamper;

  /// Disconnects after sending this many frames in total.
  int? dropAfter;
  Duration frameDelay = Duration.zero;
  final writes = <(String, List<int>)>[];
  final _attempts = <String, int>{};
  final _summary = StreamController<List<int>>.broadcast();
  final _gone = Completer<void>();
  bool get connected => !_gone.isCompleted;
  int _sent = 0;

  List<int> get commands => [
    for (final (c, v) in writes)
      if (c == BandGatt.control) v.first,
  ];
  int asked(String file) => _attempts[file] ?? 0;

  @override
  Future<List<int>> read(String c) async => c == BandGatt.info ? info : const [];

  @override
  Future<void> write(String c, List<int> value) async {
    writes.add((c, value));
    if (c != BandGatt.control) return;
    final (String file, Object body) = switch (value.first) {
      bandSendIndex => (
        'index',
        {
          'schema': 'lifetwin.band_index.v0',
          'firmware': '0.8',
          'timezone_offset_minutes': -420,
          'days': [...days.keys, ...extraIndex],
        },
      ),
      bandSendDay => (
        ascii.decode(value.sublist(1)),
        days[ascii.decode(value.sublist(1))] ?? {'error': 'no_file_for_that_date'},
      ),
      _ => ('', const {}),
    };
    if (file.isEmpty) return;
    final attempt = _attempts[file] ?? 0;
    _attempts[file] = attempt + 1;
    final bytes = utf8.encode(jsonEncode(body));
    final frames = <List<int>>[
      for (var i = 0; i < bytes.length; i += 180) bytes.sublist(i, i + 180 > bytes.length ? bytes.length : i + 180),
      _eof,
    ];
    final send = tamper == null ? frames : tamper!(file, attempt, frames);
    if (send == null) return;
    unawaited(() async {
      for (final f in send) {
        await Future<void>.delayed(frameDelay);
        if (!connected) return;
        _summary.add(f);
        if (++_sent == dropAfter) {
          _gone.complete();
          return;
        }
      }
    }());
  }

  @override
  Future<Stream<List<int>>> subscribe(String c) async => c == BandGatt.summary ? _summary.stream : const Stream.empty();

  @override
  Future<void> get disconnected => _gone.future;

  @override
  Future<void> disconnect() async {
    if (connected) _gone.complete();
  }
}

class FakeRadio implements BleRadio {
  FakeRadio(this.band, {this.state = BleAdapterState.on});
  final FakeBand band;
  BleAdapterState state;
  final adverts = [
    const BleAdvert(id: 'band-1', name: 'LifeTwin Band', rssi: -50, services: ['4C540001-7B2A-4F0E-9A51-0D1E2C3B4A50']),
    const BleAdvert(id: 'speaker', name: 'Kitchen speaker', rssi: -40, services: ['180d']),
    const BleAdvert(id: 'other', name: 'Someone else', rssi: -30, services: [BandGatt.service]),
  ];
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

BleBandClient _client(FakeRadio radio, {int maxFileBytes = bandBleMaxFileBytes}) => BleBandClient(
  radio,
  now: () => _now,
  clockSettle: Duration.zero,
  firstByteTimeout: const Duration(milliseconds: 200),
  gapTimeout: const Duration(milliseconds: 100),
  maxFileBytes: maxFileBytes,
);

BandStore _store(FakeBand band, {int maxFileBytes = bandBleMaxFileBytes}) =>
    BandStore(_client(FakeRadio(band), maxFileBytes: maxFileBytes), now: () => _now);

List<List<int>> _drop(List<List<int>> frames, int i) => [...frames]..removeAt(i);

void main() {
  group('BleBandClient against a firmware 0.8 fake band', () {
    test('scan -> connect -> Info -> clock -> index -> 3 days -> import', () async {
      final band = FakeBand();
      final radio = FakeRadio(band);
      final store = BandStore(_client(radio), now: () => _now);

      expect(await store.client.bluetooth(), BluetoothState.on);
      final found = await store.client.scan();
      expect(radio.scannedFor, BandGatt.service);
      expect(found.map((d) => d.name), ['LifeTwin Band'], reason: 'service UUID and name prefix both filter');

      expect(await store.pair(found.single), isTrue, reason: '${store.pairProblem}');
      expect(radio.connectedTo, 'band-1');
      final info = (store.client as BleBandClient).info!;
      expect((info.fwMajor, info.fwMinor, info.recordFormat, info.capacity, info.storedMinutes), (0, 8, 2, 1440, 47));
      expect(info.positionsSaved, isFalse);
      expect(band.writes.first.$1, BandGatt.clock, reason: 'the clock first, every connection');
      expect(band.writes.first.$2, bandClockBytes(_now));
      expect(band.commands, [bandSendIndex, bandSendDay, bandSendDay, bandSendDay]);
      expect([
        for (final (c, v) in band.writes)
          if (c == BandGatt.control && v.first == bandSendDay) ascii.decode(v.sublist(1)),
      ], _three);
      expect(band.commands, isNot(contains(0x0E)), reason: 'never deletes days on the band');
      expect(store.paired, isTrue);
      expect(store.fileReports.map((r) => r.day), _three);
      expect(store.sourceLabel, 'Bluetooth');

      await store.unpair();
      expect(band.connected, isFalse);
      expect(store.fileReports, isEmpty);
    });

    test('clock bytes: unix seconds u32 LE, then minutes east of UTC i16 LE', () {
      final t = DateTime.utc(2026, 10, 25, 19, 0, 0);
      final secs = t.millisecondsSinceEpoch ~/ 1000;
      expect(bandClockBytes(t), [secs & 0xff, secs >> 8 & 0xff, secs >> 16 & 0xff, secs >> 24 & 0xff, 0, 0]);
      final local = DateTime(2026, 10, 25, 12);
      final zone = ByteData.sublistView(Uint8List.fromList(bandClockBytes(local))).getInt16(4, Endian.little);
      expect(zone, local.timeZoneOffset.inMinutes);
    });

    test('only the newest 14 days are asked for; a listed day with no file is skipped', () async {
      final dates = [for (var d = 8; d <= 24; d++) '2026-10-${d.toString().padLeft(2, '0')}']; // 17 days
      final band = FakeBand(days: _days(dates.where((d) => d != '2026-10-20').toList()), extraIndex: ['2026-10-20']);
      final store = _store(band);
      expect(await store.pair(_device), isTrue, reason: '${store.pairProblem}');
      expect(band.commands.where((c) => c == bandSendDay), hasLength(14));
      expect(store.fileReports.first.day, '2026-10-11');
      expect(store.fileReports, hasLength(13));
      expect(store.fileReports.map((r) => r.day), isNot(contains('2026-10-20')));
    });

    for (final (name, info) in [
      ('firmware 0.7 (the probed band)', _info07),
      ('record format 3', [0x00, 0x08, 0x03, 0x0c, 0xa0, 0x05, 0, 0, 0, 0]),
      ('a short Info', [0x00, 0x08]),
    ]) {
      test('$name: a plain firmware update message, nothing written', () async {
        final band = FakeBand(info: info);
        final store = _store(band);
        expect(await store.pair(_device), isFalse);
        expect(store.pairProblem, contains('needs a firmware update'));
        expect(store.pairProblem, contains('0.8'));
        expect(band.writes, isEmpty);
        expect(band.connected, isFalse);
      });
    }

    test('each sync re-sends the newest days: identical days are no-ops, a grown today replaces', () async {
      final today = _day('2026-10-25');
      final early = jsonDecode(jsonEncode(today)) as Map<String, dynamic>;
      _truncate(early, 8);
      early['generated_at'] = '2026-10-25T09:00:00-07:00';
      final band = FakeBand(days: {..._days(_three), '2026-10-25': early});
      final store = _store(band);
      expect(await store.pair(_device), isTrue, reason: '${store.pairProblem}');
      final first = store.fileReports.last;
      expect(await store.sync(), isFalse, reason: 'identical re-import is a no-op');
      band.days['2026-10-25'] = today..['generated_at'] = '2026-10-25T23:59:00-07:00';
      expect(await store.sync(), isTrue, reason: 'today grew');
      expect(store.fileReports, hasLength(4));
      expect(store.fileReports.last.recordedMinutes, greaterThan(first.recordedMinutes));
    });

    test('a day that changed without growing refuses the whole delivery and keeps what was there', () async {
      final band = FakeBand(
        days: {..._days(_three), '2026-10-23': _day('2026-10-23')..['generated_at'] = '2026-10-24T08:00:00-07:00'},
      );
      final store = _store(band);
      expect(await store.pair(_device), isTrue);
      final before = store.fileReports.map((r) => r.contentKey).toList();
      final changed = _day('2026-10-23'); // same minutes, a few more steps in one hour, exported earlier
      changed['steps'] = (changed['steps'] as int) + 5;
      final hour = (changed['hourly'] as List).cast<Map<String, dynamic>>().firstWhere((h) => (h['steps'] as int) > 0);
      hour['steps'] = (hour['steps'] as int) + 5;
      band.days['2026-10-23'] = changed;
      await expectLater(store.sync(), throwsA(isA<BandFileFailure>()));
      expect(store.fileReports.map((r) => r.contentKey), before);
    });

    test('minutes with no saved positions still import, with their steps (posture unknown)', () async {
      final band = FakeBand(days: {for (final d in _three) d: _unsaved(_day(d))});
      final store = _store(band);
      expect(await store.pair(_device), isTrue, reason: '${store.pairProblem}');
      final report = store.fileReports.first;
      expect(report.steps, greaterThan(0));
      expect(store.week().days.firstWhere((d) => d.date == DateTime(2026, 10, 22)).steps, report.steps);
      expect(store.week().hasUnknownActivityCoverage, isTrue);
    });

    test('pairing replaces the built-in recorded demo only once the band data checks out', () async {
      final store = _store(FakeBand())..setDemo(true);
      expect(await store.pair(_device), isTrue);
      expect(store.demo, isFalse);
      expect(store.fileReports, hasLength(3));

      final failing = _store(FakeBand(tamper: (_, _, _) => null))..setDemo(true);
      expect(await failing.pair(_device), isFalse);
      expect(failing.demo, isTrue, reason: 'a failed pairing leaves the demo as it was');
    });

    test('a lost frame in one day: that day is asked for once more, then succeeds', () async {
      final band = FakeBand(tamper: (file, attempt, f) => file == '2026-10-23' && attempt == 0 ? _drop(f, 3) : f);
      final store = _store(band);
      expect(await store.pair(_device), isTrue, reason: '${store.pairProblem}');
      expect(band.asked('2026-10-23'), 2);
      expect(band.asked('2026-10-22'), 1);
      expect(store.fileReports, hasLength(3));
    });

    test('lost and out-of-order frames twice: an error, nothing imported', () async {
      final band = FakeBand(
        tamper: (file, attempt, f) =>
            file != '2026-10-23' ? f : (attempt == 0 ? _drop(f, 5) : [f[0], f[2], f[1], ...f.skip(3)]),
      );
      final store = _store(band);
      expect(await store.pair(_device), isFalse);
      expect(band.asked('2026-10-23'), 2, reason: 'retried exactly once');
      expect(store.pairProblem, isNotNull);
      expect(store.fileReports, isEmpty, reason: 'the good days are not imported either');
      expect(band.connected, isFalse);
    });

    test('Bluetooth off, not allowed, or unsupported', () async {
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
      expect(await store.pair(_device), isFalse);
      expect(store.pairProblem, contains('couldn’t link'));
      expect(store.pairProblem, isNot(contains('band-1')));
    });

    test('timeout: the band never answers', () async {
      final band = FakeBand(tamper: (_, _, _) => null);
      final store = _store(band);
      expect(await store.pair(_device), isFalse);
      expect(store.pairProblem, contains('didn’t answer'));
      expect(store.fileReports, isEmpty);
      expect(band.connected, isFalse);
    });

    test('the band stops without <EOF>: abandoned after the gap, nothing imported, not asked again', () async {
      final band = FakeBand(tamper: (file, _, f) => file == '2026-10-23' ? f.sublist(0, f.length - 1) : f);
      final store = _store(band);
      expect(await store.pair(_device), isFalse);
      expect(store.pairProblem, contains('stopped sending'));
      expect(band.asked('2026-10-23'), 1);
      expect(store.fileReports, isEmpty);
    });

    test('a slow transfer is fine: only the gap between notifications is limited', () async {
      final band = FakeBand()..frameDelay = const Duration(milliseconds: 30); // ~22 frames a day: ~0.7 s each
      final store = _store(band);
      expect(await store.pair(_device), isTrue, reason: '${store.pairProblem}');
      expect(store.fileReports, hasLength(3));
    });

    test('disconnect mid-transfer: nothing imported', () async {
      final band = FakeBand(dropAfter: 30);
      final store = _store(band);
      expect(await store.pair(_device), isFalse);
      expect(store.pairProblem, contains('disconnected'));
      expect(store.fileReports, isEmpty);
      expect(store.paired, isFalse);
    });

    test('an oversize file is rejected without asking again', () async {
      final band = FakeBand();
      final store = _store(band, maxFileBytes: 1000);
      expect(await store.pair(_device), isFalse);
      expect(band.asked('2026-10-22'), 1);
      expect(store.pairProblem, contains('more than one delivery'));
      expect(store.fileReports, isEmpty);
    });

    test('one day the parser rejects rejects the whole delivery', () async {
      final bad = _day('2026-10-23');
      bad['steps'] = (bad['steps'] as int) + 1; // totals no longer match
      final band = FakeBand(days: {..._days(_three), '2026-10-23': bad});
      final store = _store(band);
      expect(await store.pair(_device), isFalse);
      expect(store.pairProblem, contains('nothing was added'));
      expect(band.asked('2026-10-23'), 2, reason: 'asked once more in case a notification was lost');
      expect(store.fileReports, isEmpty, reason: 'the two good days are not imported either');
      expect(band.connected, isFalse);
    });

    test('an empty index: paired, no days', () async {
      final store = _store(FakeBand(days: {}));
      expect(await store.pair(_device), isTrue);
      expect(store.fileReports, isEmpty);
    });

    test('save standing and sitting positions: control 05 and 06', () async {
      final band = FakeBand(days: {});
      final client = _client(FakeRadio(band));
      expect(await client.savePosition(standing: true), isFalse, reason: 'not linked yet');
      await client.pair(_device);
      expect(await client.savePosition(standing: true), isTrue);
      expect(await client.savePosition(standing: false), isTrue);
      expect(band.commands, [bandSaveStanding, bandSaveSitting]);
      expect(BandInfo(const [0, 8, 2, 12, 0xa0, 5, 0, 0, 7, 0]).positionsSaved, isTrue);
    });
  });

  group('BandJsonAssembler', () {
    final a = utf8.encode('{"a":"}{\\"<EOF>","b":[1,{"c":2}]}');

    test('values split anywhere; <EOF> in a string does not end it; <EOF> as a notification does', () {
      final asm = BandJsonAssembler();
      final out = <Uint8List>[];
      for (var i = 0; i < a.length; i += 3) {
        out.addAll(asm.add(a.sublist(i, i + 3 > a.length ? a.length : i + 3)));
        expect(asm.ended, isFalse);
      }
      expect(out.map(utf8.decode), [utf8.decode(a)]);
      asm.add(_eof);
      expect(asm.ended, isTrue);
    });

    test('<EOF> glued to the end of the last chunk', () {
      final asm = BandJsonAssembler();
      expect(asm.add([...a, ..._eof]).map(utf8.decode), [utf8.decode(a)]);
      expect(asm.ended, isTrue);
    });

    test('oversize', () {
      expect(() => BandJsonAssembler(maxBytes: 10).add(a), throwsA(isA<BandTransferFailure>()));
    });
  });
}

/// The day with every worn minute's posture unknown (no saved positions): steps kept.
Map<String, dynamic> _unsaved(Map<String, dynamic> d) {
  final m = d['minutes'] as Map<String, dynamic>;
  final wear = (d['coverage'] as Map<String, dynamic>)['wear_minutes'] as int;
  for (final k in [
    'sitting_or_lying',
    'standing',
    'walking_light',
    'walking_moderate',
    'running_vigorous',
    'other_posture',
  ]) {
    m[k] = 0;
  }
  m['positions_not_saved'] = wear;
  d['moderate_vigorous_minutes'] = 0;
  d['longest_sitting_minutes'] = 0; // no known sitting, so no sitting interval
  d['sit_to_stand_transitions'] = 0;
  for (final h in (d['hourly'] as List).cast<Map<String, dynamic>>()) {
    for (final k in ['sitting_lying_min', 'standing_min', 'walking_min', 'running_min', 'other_min']) {
      h[k] = 0;
    }
  }
  return d;
}

/// Keeps hours 0..[lastHour] of [day] (the rest zero) and makes its totals and coverage agree.
void _truncate(Map<String, dynamic> day, int lastHour) {
  final hourly = (day['hourly'] as List).cast<Map<String, dynamic>>();
  for (final h in hourly) {
    if ((h['hour'] as int) > lastHour) h.updateAll((k, v) => k == 'hour' ? v : 0);
  }
  int sum(String k) => hourly.fold(0, (a, h) => a + (h[k] as int));
  final sit = sum('sitting_lying_min'), stand = sum('standing_min'), walk = sum('walking_min');
  final run = sum('running_min'), other = sum('other_min'), off = sum('not_worn_min');
  final recorded = sit + stand + walk + run + other + off;
  day['minutes'] = {
    'sitting_or_lying': sit,
    'standing': stand,
    'walking_light': walk,
    'walking_moderate': 0,
    'running_vigorous': run,
    'other_posture': other,
    'not_worn': off,
    'positions_not_saved': 0,
  };
  day['moderate_vigorous_minutes'] = run;
  day['steps'] = sum('steps');
  day['coverage'] = {
    'minutes_recorded': recorded,
    'wear_minutes': recorded - off,
    'valid_day': recorded - off >= 600,
    'first_minute': '00:00',
    'last_minute': '${lastHour.toString().padLeft(2, '0')}:59',
  };
  day['longest_sitting_minutes'] = (day['longest_sitting_minutes'] as int).clamp(0, sit);
  day['sit_to_stand_transitions'] = (day['sit_to_stand_transitions'] as int).clamp(0, recorded);
}
