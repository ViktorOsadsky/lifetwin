// A malformed band file must show a plain error, never crash, never leave a half import.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/band/band_file.dart';
import 'package:lifesim/band/band_file_intake.dart';
import 'package:lifesim/band/band_file_session.dart';
import 'package:lifesim/band/band_store.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';

import '../checkin/daily_checkin_test.dart' show profile;
import '../checkin/readback_flow_test.dart' show ContractGuide;
import '../checkin/routes_wiring_test.dart' show FakeCapabilities;
import '../support/app_fonts.dart';
import '../support/fake_change_client.dart';
import 'band_file_test.dart' show FakeFiles, bytes, sample;

Uint8List raw(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });
  tearDown(BandFileSession.disposeIfCreated);

  Map<String, dynamic> valid() => sample();

  final bad = <String, Uint8List>{
    'empty file': Uint8List(0),
    'blank': raw('   '),
    'not json': raw('{bad'),
    'json null': raw('null'),
    'json number': raw('42'),
    'json string': raw('"hello"'),
    'empty list': raw('[]'),
    'list of numbers': raw('[1,2,3]'),
    'empty object': raw('{}'),
    'schema only': raw('{"schema":"lifetwin.band_day.v0"}'),
    'html': raw('<html><body>hi</body></html>'),
    'minutes is a string': bytes(valid()..['minutes'] = 'lots'),
    'minutes is null': bytes(valid()..['minutes'] = null),
    'minutes is a list': bytes(valid()..['minutes'] = [1, 2]),
    'coverage is a list': bytes(valid()..['coverage'] = []),
    'coverage is null': bytes(valid()..['coverage'] = null),
    'hourly is a string': bytes(valid()..['hourly'] = 'x'),
    'hourly holds numbers': bytes(valid()..['hourly'] = List<int>.filled(24, 1)),
    'hourly is null': bytes(valid()..['hourly'] = null),
    'device is a number': bytes(valid()..['device'] = 5),
    'date is a number': bytes(valid()..['date'] = 20261024),
    'date is null': bytes(valid()..['date'] = null),
    'steps is a string': bytes(valid()..['steps'] = '16500'),
    'steps is huge': bytes(valid()..['steps'] = 1e30),
    'offset is a string': bytes(valid()..['timezone_offset_minutes'] = '-420'),
    'bundle of nulls': bytes({'schema': 'lifetwin.band_day.v0', 'days': [null, 1]}),
    'invalid utf-8': Uint8List.fromList([0xff, 0xfe, 0x7b, 0x7d]),
  };

  group('parser: only a plain BandFileFailure ever comes out', () {
    for (final e in bad.entries) {
      test(e.key, () {
        Object? thrown;
        try {
          parseBandFile(e.value);
        } catch (err) {
          thrown = err;
        }
        expect(thrown, isA<BandFileFailure>(), reason: 'a ${thrown?.runtimeType} escaped: $thrown');
        final reason = (thrown! as BandFileFailure).reason;
        expect(reason, isNotEmpty);
        expect(reason, isNot(contains('Instance of')));
        expect(reason, isNot(contains('type \'')), reason: 'no Dart type error text for a person: $reason');
      });
    }
  });

  group('intake: a bad pick is an error outcome, the store stays empty', () {
    for (final e in bad.entries) {
      test(e.key, () async {
        final store = BandStore(StubBandClient());
        final files = FakeFiles()..chosen = [e.value];
        final intake = BandFileIntake(store: store, picker: files);
        addTearDown(() async {
          intake.dispose();
          store.dispose();
          await files.events.close();
        });
        await intake.importFromFiles();
        expect(intake.busy, isFalse);
        expect(intake.outcome?.error, isNotNull, reason: 'a person must be told');
        expect(store.hasImportedFile, isFalse);
      });
    }

    test('one bad file among good ones imports none of them', () async {
      final store = BandStore(StubBandClient());
      final files = FakeFiles()..chosen = [bytes(valid()), raw('{bad')];
      final intake = BandFileIntake(store: store, picker: files);
      addTearDown(() async {
        intake.dispose();
        store.dispose();
        await files.events.close();
      });
      await intake.importFromFiles();
      expect(intake.outcome?.error, isNotNull);
      expect(store.hasImportedFile, isFalse, reason: 'validate everything before importing anything');
    });
  });

  testWidgets('UI: Add band > Import band file with a malformed file shows an error and stays put', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    await repo.saveConversationProfile(profile);
    final look = ValueNotifier(const TwinAppearance(name: 'Mochi'));
    addTearDown(look.dispose);
    final voice = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: FakeSpeechInput(),
      output: FakeSpeechOutput(),
    );
    addTearDown(voice.dispose);
    final files = FakeFiles()..chosen = [raw('{"schema":"lifetwin.band_day.v0","minutes":"lots"}')];
    final routes = AgenticRoutes(
      look: look,
      api: ApiBase(),
      voice: () => voice,
      guide: ContractGuide(),
      changeClient: FakeChangeClient(),
      capabilities: FakeCapabilities(null),
      bandClient: StubBandClient(),
      bandFilePicker: files,
    )..attach(repo);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: routes.wrap,
        home: Builder(
          builder: (c) => Scaffold(body: Column(children: routes.pills(c))),
        ),
      ),
    );
    await t.tap(find.text('Add band'));
    await t.pumpAndSettle();
    await t.tap(find.text('Import band file'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull, reason: 'a malformed file must not crash');
    expect(routes.band.hasImportedFile, isFalse);
    expect(find.byType(SnackBar), findsOneWidget, reason: 'the person is told');
    expect(find.textContaining('Added'), findsNothing);
    expect(find.text('Import band file'), findsOneWidget, reason: 'still on the first band screen to try again');
  });
}
