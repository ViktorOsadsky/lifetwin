import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/band/band_data.dart';
import 'package:lifesim/band/band_file.dart';
import 'package:lifesim/band/band_file_intake.dart';
import 'package:lifesim/band/band_service.dart';
import 'package:lifesim/band/band_store.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';

import '../checkin/daily_checkin_test.dart' show profile;

Map<String, dynamic> sample([String name = 'valid_day']) =>
    jsonDecode(File('test/fixtures/band/$name.json').readAsStringSync())
        as Map<String, dynamic>;
Uint8List bytes(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

class FakeFiles extends BandFilePicker {
  List<Uint8List>? chosen;
  List<Uint8List> inbox = [];
  int clears = 0;
  int subscriptions = 0;
  Completer<bool>? availability;
  Completer<List<Uint8List>?>? pending;
  final events = StreamController<Uint8List>.broadcast();
  @override
  Stream<Uint8List> get incoming {
    subscriptions++;
    return events.stream;
  }

  @override
  Future<bool> available() async => availability?.future ?? true;
  @override
  Future<List<Uint8List>?> pick() async =>
      pending == null ? chosen : pending!.future;
  @override
  Future<List<Uint8List>> recoverInbox() async => inbox;
  @override
  Future<void> clear() async {
    clears++;
    inbox = [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 24, 23, 59);
  group('actual gadget daily schema', () {
    test(
      'retains distinct categories and does not reconstruct minute records',
      () {
        final report = parseBandFile(bytes(sample())).single;
        expect(report.mount, 'thigh_pocket');
        expect(report.offsetMinutes, -420);
        expect(report.validDay, isTrue);
        expect(report.moderateMinutes, 72);
        expect(report.vigorousMinutes, 60);
        expect(report.sittingOrLyingMinutes, 420);
        final day = BandDay.fromReport(report);
        expect(day.minutes, isEmpty);
        expect(day.wornMinutes, 720);
        expect(day.stepsByHour[2], isNull);
        expect(day.stepsByHour[8], 1375);
      },
    );
    test(
      'nonwear and missing position coverage never become zero activity',
      () {
        final report = parseBandFile(bytes(sample('low_wear'))).single;
        expect(report.wearMinutes, 360);
        expect(report.classifiedWearMinutes, 240);
        expect(report.postures['not_worn'], 120);
        expect(report.postures['positions_not_saved'], 120);
        expect(report.validDay, isFalse);
        expect(report.moderateMinutes, isNull);
        expect(report.vigorousMinutes, isNull);
        expect(report.sittingOrLyingMinutes, isNull);
      },
    );
    test(
      'dated bundle preserves local dates across midnight and offset changes',
      () {
        final reports = parseBandFile(bytes(sample('midnight_bundle')));
        expect(reports.map((r) => r.day), ['2026-10-23', '2026-10-24']);
        expect(reports.map((r) => r.offsetMinutes), [-420, 330]);
      },
    );
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'schema': (j) => j['schema'] = 'unsupported',
      'invalid calendar': (j) => j['date'] = '2026-02-30',
      'invalid export calendar': (j) =>
          j['generated_at'] = '2026-02-30T23:59:00Z',
      'invalid export clock': (j) => j['generated_at'] = '2026-10-24T25:00:00Z',
      'invalid export offset': (j) =>
          j['generated_at'] = '2026-10-24T23:59:00+99:99',
      'unknown export offset': (j) =>
          j['generated_at'] = '2026-10-24T23:59:00-00:00',
      'time zone': (j) => j['timezone_offset_minutes'] = 900,
      'fractional minutes': (j) => j['minutes']['walking_moderate'] = 72.5,
      'negative steps': (j) => j['steps'] = -1,
      'string flag': (j) => j['coverage']['valid_day'] = 'true',
      'wrong wear flag': (j) => j['coverage']['valid_day'] = false,
      'daily discrepancy': (j) => j['minutes']['standing'] = 121,
      'MVPA discrepancy': (j) => j['moderate_vigorous_minutes'] = 999,
      'duplicate hour': (j) => j['hourly'][1]['hour'] = 0,
      'missing hour': (j) => j['hourly'].removeLast(),
      'hour overflow': (j) => j['hourly'][8]['standing_min'] = 61,
      'hour steps discrepancy': (j) => j['hourly'][8]['steps'] = 0,
      'coverage clock': (j) => j['coverage']['first_minute'] = '25:00',
      'undated midnight span': (j) => j['coverage']['first_minute'] = '23:00',
      'notes shape': (j) => j['notes'] = {'instructions': 'ignored'},
    };
    for (final entry in mutations.entries) {
      test('rejects ${entry.key} with a safe reason', () {
        final data = sample();
        entry.value(data);
        expect(
          () => parseBandFile(bytes(data)),
          throwsA(isA<BandFileFailure>()),
        );
      });
    }
    test('invalid encoding and oversized files fail before import', () {
      expect(
        () => parseBandFile(Uint8List.fromList([255, 254])),
        throwsA(isA<BandFileFailure>()),
      );
      expect(
        () => parseBandFile(Uint8List(bandFileMaxBytes + 1)),
        throwsA(isA<BandFileFailure>()),
      );
    });
    test('known wear with unknown posture cannot yield a weekly estimate', () {
      final days = <BandDay>[];
      for (var back = 0; back < 4; back++) {
        final data = sample();
        data['date'] = '2026-10-${24 - back}';
        data['minutes']['positions_not_saved'] = 120;
        data['coverage']['wear_minutes'] += 120;
        data['coverage']['minutes_recorded'] += 120;
        days.add(BandDay.fromReport(parseBandFile(bytes(data)).single));
      }
      final week = BandWeek(days);
      expect(week.validCount, 4, reason: 'Known wear is still displayed.');
      expect(
        week.validModerate,
        greaterThan(0),
        reason: 'Observed counts remain.',
      );
      expect(week.hasUnknownActivityCoverage, isTrue);
      expect(week.hasEstimate, isFalse);
      expect(week.estimateMinutesPerWeek, isNull);
    });
  });

  group('phone import and existing band flow', () {
    late BandStore store;
    late FakeFiles picker;
    late BandFileIntake intake;
    setUp(() {
      store = BandStore(StubBandClient(), now: () => now);
      picker = FakeFiles();
      intake = BandFileIntake(store: store, picker: picker);
    });
    tearDown(() async {
      intake.dispose();
      store.dispose();
      await picker.events.close();
    });
    test(
      'fake picker imports atomic aggregates; same file is idempotent',
      () async {
        picker.chosen = [bytes(sample())];
        await intake.importFromFiles();
        expect(store.hasImportedFile, isTrue);
        expect(store.paired, isFalse);
        expect(store.demo, isTrue);
        expect(store.live, isFalse);
        expect(store.sourceLabel, 'Recorded demo');
        expect(store.today.steps, 16500);
        expect(store.minutes, isEmpty);
        expect(intake.outcome!.changed, isTrue);
        await intake.importFromFiles();
        expect(intake.outcome!.changed, isFalse);
        expect(store.fileReports.length, 1);
      },
    );
    test(
      'failed batch preserves previous import and emits no partial update',
      () {
        intake.importBytes([bytes(sample())]);
        final before = store.today.steps;
        final invalid = sample();
        invalid['steps'] = -1;
        expect(
          () => intake.importBytes([bytes(sample('low_wear')), bytes(invalid)]),
          throwsA(isA<BandFileFailure>()),
        );
        expect(store.today.steps, before);
        expect(store.fileReports.length, 1);
      },
    );
    test('cancellation preserves data and no stale picker response survives forgetting', () async {
      intake.importBytes([bytes(sample())]);
      picker.chosen = null;
      await intake.importFromFiles();
      expect(intake.outcome!.cancelled, isTrue);
      expect(store.hasImportedFile, isTrue);
      picker.pending = Completer();
      final request = intake.importFromFiles();
      await intake.forgetImports();
      picker.pending!.complete([bytes(sample())]);
      await request;
      expect(store.fileReports, isEmpty);
      expect(picker.clears, 1);
    });
    test(
      'Open-in inbox and warm events use the same import validation',
      () async {
        picker.inbox = [bytes(sample())];
        await intake.start();
        expect(store.hasImportedFile, isTrue);
        picker.events.add(bytes({'schema': 'bad'}));
        await Future<void>.delayed(Duration.zero);
        expect(intake.outcome!.error, isNotNull);
        expect(store.fileReports.length, 1);
      },
    );
    test('concurrent startup subscribes once', () async {
      picker.availability = Completer<bool>();
      final first = intake.start();
      final second = intake.start();
      picker.availability!.complete(true);
      await Future.wait([first, second]);
      expect(picker.subscriptions, 1);
    });
    test('demo files cannot mix with an active measured minute feed', () {
      store.addMinute(BandMinute(at: now.subtract(const Duration(days: 1))));
      expect(
        () => intake.importBytes([bytes(sample())]),
        throwsA(isA<BandFileFailure>()),
      );
      expect(store.minutes, hasLength(1));
      expect(store.demo, isFalse);
    });
    test(
      'replacement is explicit, duplicates and real/demo mixing are rejected',
      () {
        intake.importBytes([bytes(sample())]);
        final newer = sample('low_wear');
        expect(
          () => intake.importBytes([bytes(newer)]),
          throwsA(isA<BandFileFailure>()),
        );
        intake.importBytes([bytes(newer)], replaceExisting: true);
        expect(store.today.wornMinutes, 360);
        final measured = sample()..remove('synthetic_demo');
        expect(
          () => intake.importBytes([bytes(measured)], replaceExisting: true),
          throwsA(isA<BandFileFailure>()),
        );
        expect(
          () => intake.importBytes([bytes(newer), bytes(newer)]),
          throwsA(isA<BandFileFailure>()),
        );
      },
    );
    test('file feed reaches existing confirmation flow with band provenance only after confirm', () async {
      final repo = TwinRepository(
        model: await TwinModelService.load(),
        store: await TwinStore.open(MemoryBackend()),
      );
      await repo.saveConversationProfile({
        ...profile,
        'moderate_recreation_min_week': 30,
      });
      final service = BandService(repository: repo, now: () => now);
      // Controlled fixtures exercise measured-feed semantics; they are not a
      // claim of four real days of hardware wear or intensity calibration.
      final reports = [
        for (var back = 0; back < 4; back++)
          BandDayReport.fromJson(
            sample()
              ..remove('synthetic_demo')
              ..['date'] = '2026-10-${24 - back}',
          ),
      ];
      store.importReports(reports);
      expect(store.live, isTrue);
      expect(store.week().validCount, 4);
      final candidate = service.suggest(store.week(), live: store.live)!;
      expect(repo.profile['moderate_recreation_min_week'], 30);
      await service.confirm(candidate);
      expect(repo.provenance(bandField)!.source, HistorySource.wristband);
      expect(repo.provenance(bandField)!.estimated, isTrue);
      expect(repo.outsideAiProfile(), isNot(contains(bandField)));
      repo.dispose();
    });
    test('one measured day and extrapolated demo days do not bypass weekly sufficiency', () async {
      final repo = TwinRepository(
        model: await TwinModelService.load(),
        store: await TwinStore.open(MemoryBackend()),
      );
      await repo.saveConversationProfile({
        ...profile,
        'moderate_recreation_min_week': 30,
      });
      final service = BandService(repository: repo, now: () => now);
      store.importReports([
        BandDayReport.fromJson(sample()..remove('synthetic_demo')),
      ]);
      expect(service.suggest(store.week(), live: store.live), isNull);
      await store.unpair();
      store.importReports([BandDayReport.fromJson(sample())]);
      expect(service.suggest(store.week(), live: store.live), isNull);
      expect(repo.profile['moderate_recreation_min_week'], 30);
      repo.dispose();
    });
  });
}
