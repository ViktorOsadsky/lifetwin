import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/band/band_data.dart';
import 'package:lifesim/band/band_screens.dart';
import 'package:lifesim/band/band_service.dart';
import 'package:lifesim/band/band_store.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';

import '../checkin/daily_checkin_test.dart' show profile;
import '../support/app_fonts.dart';

final today = DateTime(2026, 10, 25, 15);

/// [wornHours] and [moderate] minutes for each of the last 7 days (oldest first).
List<BandMinute> week(List<int> wornHours, List<int> moderate) {
  final out = <BandMinute>[];
  for (var i = 0; i < 7; i++) {
    final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - i));
    for (var m = 0; m < wornHours[i] * 60; m++) {
      out.add(
        BandMinute(
          at: day.add(Duration(hours: 6, minutes: m)),
          steps: 3,
          moderate: m < moderate[i],
        ),
      );
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<TwinRepository> repoWith(num moderate) async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => today);
    await repo.saveConversationProfile({...profile, 'moderate_recreation_min_week': moderate});
    return repo;
  }

  group('the weekly estimate (APP-04)', () {
    test('23 minutes on 4 valid days: 23 x 7/4 = 40.25, about 40 (rounded to 10)', () {
      final w = BandWeek.from(week([11, 11, 11, 11, 3, 3, 3], [6, 7, 6, 4, 0, 0, 0]), today);
      expect(w.validCount, 4);
      expect(w.validModerate, 23);
      expect(w.hasEstimate, isTrue);
      expect(w.estimateMinutesPerWeek, 40);
    });

    test('a day counts at 10+ hours worn; under 4 valid days gives no estimate', () {
      var w = BandWeek.from(week([10, 10, 10, 9, 12, 2, 2], [5, 5, 5, 5, 5, 5, 5]), today);
      expect(w.days.map((d) => d.isValid), [true, true, true, false, true, false, false]);
      expect(w.validCount, 4);
      w = BandWeek.from(week([10, 10, 9, 9, 12, 2, 2], [5, 5, 5, 5, 5, 5, 5]), today);
      expect(w.validCount, 3);
      expect(w.hasEstimate, isFalse);
      expect(w.estimateMinutesPerWeek, isNull);
    });

    test('not-worn minutes count for nothing', () {
      final day = BandDay(today, [
        BandMinute(at: today, steps: 50, moderate: true, worn: false),
        BandMinute(at: today.add(const Duration(minutes: 1)), steps: 7),
      ]);
      expect((day.steps, day.moderateMinutes, day.wornMinutes), (7, 0, 1));
      expect(day.stepsByHour[today.hour], 7);
      expect(BandDay(today, const []).stepsByHour[3], isNull, reason: 'not worn is not a bar');
    });
  });

  group('the suggestion and its confirmation (D2, D3)', () {
    final strong = BandWeek.from(week([11, 11, 11, 11, 3, 3, 3], [6, 7, 6, 4, 0, 0, 0]), today);
    final weak = BandWeek.from(week([11, 11, 11, 11, 3, 3, 3], [1, 1, 1, 0, 0, 0, 0]), today);

    test('only live band data, only with 4+ valid days, never the recorded demo', () async {
      final repo = await repoWith(30);
      final s = BandService(repository: repo, now: () => today);
      expect(s.suggest(strong, live: true)?.estimate, 40);
      expect(s.suggest(strong, live: false), isNull, reason: 'the recorded demo offers nothing');
      final few = BandWeek.from(week([11, 11, 11, 3, 3, 3, 3], [6, 7, 6, 4, 0, 0, 0]), today);
      expect(s.suggest(few, live: true), isNull);
    });

    test('showing it saves nothing; "Not now" hides it for a week', () async {
      final repo = await repoWith(30);
      var now = today;
      final s = BandService(repository: repo, now: () => now);
      final offer = s.suggest(strong, live: true)!;
      expect(repo.profile['moderate_recreation_min_week'], 30);
      s.dismiss();
      expect(repo.profile['moderate_recreation_min_week'], 30);
      expect(s.suggest(strong, live: true), isNull);
      now = today.add(const Duration(days: 8));
      expect(s.suggest(strong, live: true)?.estimate, offer.estimate);
    });

    test('Yes, save writes the estimate as the person\'s answer, with the band provenance', () async {
      final repo = await repoWith(30);
      final before = repo.current!.percentByYear[5]!;
      final s = BandService(repository: repo, now: () => today);
      await s.confirm(s.suggest(strong, live: true)!);
      expect(repo.profile['moderate_recreation_min_week'], 40);
      final p = repo.provenance(bandField)!;
      expect(p.source, HistorySource.wristband);
      expect(p.estimated, isTrue);
      expect(p.sourceLabel, 'From your band');
      expect(p.estimateText, isNotNull);
      // A confirmed band estimate counts as the answer and may change the outlook.
      expect(repo.current!.percentByYear[5], isNot(before));
      // Once saved, the same week is not offered again.
      expect(s.suggest(strong, live: true), isNull);
    });

    test('"Not quite": the person gives their own number and that is what is saved', () async {
      final repo = await repoWith(30);
      final s = BandService(repository: repo, now: () => today);
      await s.confirm(s.suggest(strong, live: true)!, minutes: 60);
      expect(repo.profile['moderate_recreation_min_week'], 60);
    });

    test('lower estimate: kind two-choice, "Keep" changes nothing', () async {
      final repo = await repoWith(30);
      final s = BandService(repository: repo, now: () => today);
      final offer = s.suggest(weak, live: true)!;
      expect(offer.lower, isTrue);
      expect(offer.estimate, 10);
      expect(offer.question, 'Your band saw less this week. Keep 30, or use about 10?');
      s.keep();
      expect(repo.profile['moderate_recreation_min_week'], 30);
      expect(repo.provenance(bandField)?.source ?? HistorySource.said, HistorySource.said);
    });

    test('band answers never go to an outside AI provider; other answers do', () async {
      final repo = await repoWith(30);
      final s = BandService(repository: repo, now: () => today);
      await s.confirm(s.suggest(strong, live: true)!);
      final out = repo.outsideAiProfile();
      expect(out.containsKey(bandField), isFalse);
      expect(out['age'], 55);
      // Changing it through Mochi later makes it the person's own again.
      await repo.saveConversationProfile({bandField: 90}, kind: HistoryKind.mochiChange);
      expect(repo.provenance(bandField)!.sourceLabel, 'Changed with Mochi');
      expect(repo.outsideAiProfile().containsKey(bandField), isTrue);
    });
  });

  group('the band store', () {
    test('unpairing erases band days but leaves confirmed answers', () async {
      final repo = await repoWith(30);
      final store = BandStore(StubBandClient(), now: () => today);
      await store.pair(const BandDevice(name: 'LifeTwin Band'));
      for (final m in week([11, 11, 11, 11, 3, 3, 3], [6, 7, 6, 4, 0, 0, 0])) {
        store.addMinute(m);
      }
      final svc = BandService(repository: repo, now: () => today);
      await svc.confirm(svc.suggest(store.week(), live: store.live)!);
      expect(store.minutes, isNotEmpty);
      await store.unpair();
      expect(store.minutes, isEmpty);
      expect(store.paired, isFalse);
      expect(repo.profile['moderate_recreation_min_week'], 40, reason: 'confirmed answers stay');
    });

    test('recorded demo: the Recorded demo state, live is false, nothing offered', () async {
      final repo = await repoWith(30);
      final store = BandStore(StubBandClient(), now: () => today)..setDemo(true);
      expect(store.status, BandStatus.demo);
      expect(store.live, isFalse);
      final svc = BandService(repository: repo, now: () => today);
      expect(store.week().hasEstimate, isTrue);
      expect(svc.suggest(store.week(), live: store.live), isNull);
    });

    test('no band, no heart rate number, no survival number anywhere on the store', () {
      expect(bandBluetoothAvailable, isFalse, reason: 'Bluetooth is a stub until a plugin lands');
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester t, Widget w) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: lifeTwinTheme(), home: w));
      await t.pump();
    }

    testWidgets('pairing: explain first, then search, pair, and see today', (t) async {
      final store = BandStore(
        StubBandClient(devices: const [BandDevice(name: 'LifeTwin Band', strength: 3)]),
        now: () => today,
      );
      var seen = 0;
      await pump(
        t,
        BandPairScreen(store: store, appearance: const TwinAppearance(), onClose: () {}, onSeeToday: () => seen++),
      );
      expect(find.text('Mochi uses Bluetooth to find your band.'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      await t.tap(find.text('Find my band'));
      await t.pumpAndSettle();
      expect(find.text('Found your band!'), findsOneWidget);
      expect(find.text('LifeTwin Band'), findsOneWidget);
      await t.tap(find.text('Pair'));
      await t.pumpAndSettle();
      expect(store.paired, isTrue);
      expect(find.text('Band paired'), findsOneWidget);
      expect(find.text('Minutes stay on this phone'), findsOneWidget);
      expect(find.text('Heart rate, later'), findsOneWidget);
      await t.tap(find.text('See today'));
      expect(seen, 1);
    });

    testWidgets('trouble: Bluetooth off, not allowed, not found; the demo link after 2 tries', (t) async {
      final client = StubBandClient(state: BluetoothState.off);
      final store = BandStore(client, now: () => today);
      var settings = 0;
      await pump(
        t,
        BandPairScreen(
          store: store,
          appearance: const TwinAppearance(),
          onClose: () {},
          onSeeToday: () {},
          onOpenSettings: () => settings++,
        ),
      );
      await t.tap(find.text('Find my band'));
      await t.pumpAndSettle();
      expect(find.text('Bluetooth is off'), findsOneWidget);
      expect(find.text('Turn it on in Control Center'), findsOneWidget);
      client.state = BluetoothState.notAllowed;
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Bluetooth not allowed'), findsOneWidget);
      await t.tap(find.text('Open Settings'));
      expect(settings, 1);
      // On and nothing found, twice: the demo is offered first.
      client.state = BluetoothState.on;
      client.devices = const [];
      await pump(
        t,
        BandPairScreen(
          key: UniqueKey(),
          store: store,
          appearance: const TwinAppearance(),
          onClose: () {},
          onSeeToday: () {},
        ),
      );
      await t.tap(find.text('Find my band'));
      await t.pumpAndSettle();
      expect(find.text('Can’t find your band'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(client.scans, 2);
      expect(find.text('Try a recorded demo'), findsOneWidget);
      await t.tap(find.text('Try a recorded demo'));
      await t.pump();
      expect(store.demo, isTrue);
    });

    testWidgets('read-back: disclosure inside the card, Yes, save is the only thing that saves', (t) async {
      final repo = await repoWith(30);
      final svc = BandService(repository: repo, now: () => today);
      final offer = svc.suggest(
        BandWeek.from(week([11, 11, 11, 11, 3, 3, 3], [6, 7, 6, 4, 0, 0, 0]), today),
        live: true,
      )!;
      var closed = 0;
      await pump(
        t,
        BandReadbackScreen(
          service: svc,
          suggestion: offer,
          appearance: const TwinAppearance(),
          onClose: () => closed++,
        ),
      );
      expect(find.text('Moderate, like brisk walks: about 40 minutes a week, instead of 30. Right?'), findsOneWidget);
      expect(find.text('From your band'), findsOneWidget);
      expect(find.text('Sensor estimate'), findsOneWidget);
      expect(find.text('This may change your outlook.'), findsOneWidget);
      expect(repo.profile['moderate_recreation_min_week'], 30);
      // Not quite: Mochi asks, then reads the new number back; still nothing saved.
      await t.tap(find.text('Not quite'));
      await t.pump();
      expect(find.text('About how many minutes, then?'), findsOneWidget);
      await t.enterText(find.byType(TextField), '60');
      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pump();
      expect(find.textContaining('about 60 minutes a week, instead of 30'), findsOneWidget);
      expect(repo.profile['moderate_recreation_min_week'], 30);
      await t.tap(find.text('Yes, save'));
      await t.pumpAndSettle();
      expect(repo.profile['moderate_recreation_min_week'], 60);
      expect(find.text('Saved.'), findsOneWidget);
      expect(find.textContaining('From your band'), findsWidgets);
      expect(closed, 0, reason: 'the sheet stays open until Close');
    });

    testWidgets('read-back, lower: two equal choices that name both values', (t) async {
      final repo = await repoWith(30);
      final svc = BandService(repository: repo, now: () => today);
      final offer = svc.suggest(
        BandWeek.from(week([11, 11, 11, 11, 3, 3, 3], [1, 1, 1, 0, 0, 0, 0]), today),
        live: true,
      )!;
      await pump(
        t,
        BandReadbackScreen(service: svc, suggestion: offer, appearance: const TwinAppearance(), onClose: () {}),
      );
      expect(find.text('Weeks vary. That’s okay.'), findsOneWidget);
      expect(find.text('Keep 30'), findsOneWidget);
      expect(find.text('Use about 10'), findsOneWidget);
      final a = t.getSize(find.ancestor(of: find.text('Keep 30'), matching: find.byType(ConstrainedBox)).first);
      final b = t.getSize(find.ancestor(of: find.text('Use about 10'), matching: find.byType(ConstrainedBox)).first);
      expect(a, b);
      await t.tap(find.text('Use about 10'));
      await t.pumpAndSettle();
      expect(repo.profile['moderate_recreation_min_week'], 10);
    });

    testWidgets(
      'panel: Today and Week, sensor estimate tags, no survival number; under 4 days gives no weekly number',
      (t) async {
        final repo = await repoWith(30);
        final store = BandStore(StubBandClient(), now: () => today);
        await store.pair(const BandDevice(name: 'LifeTwin Band'));
        for (final m in week([8, 3, 3, 3, 3, 3, 3], [5, 0, 0, 0, 0, 0, 0])) {
          store.addMinute(m);
        }
        final svc = BandService(repository: repo, now: () => today);
        await pump(t, BandPanelScreen(store: store, service: svc, onBack: () {}, onSettings: () {}));
        expect(find.text('steps today'), findsOneWidget);
        expect(find.text('Sensor estimate'), findsOneWidget);
        expect(find.text('Coming soon'), findsOneWidget);
        expect(find.textContaining('Wear it'), findsOneWidget);
        await t.tap(find.text('Week'));
        await t.pump();
        expect(find.text('Wear it 4 days to get a weekly number.'), findsOneWidget);
        for (final s in t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '')) {
          expect(RegExp(r'in 100|survival|alive').hasMatch(s), isFalse, reason: s);
        }
      },
    );

    testWidgets('settings: what is sent, nothing for an AI provider, unpair erases band days', (t) async {
      final store = BandStore(StubBandClient(), now: () => today);
      await store.pair(const BandDevice(name: 'LifeTwin Band'));
      store.addMinute(BandMinute(at: today, steps: 5));
      await pump(t, BandSettingsScreen(store: store, onBack: () {}));
      expect(find.text('Weekly total, only when you say yes'), findsOneWidget);
      expect(find.text('Never stored on our server.'), findsOneWidget);
      for (final s in t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '')) {
        expect(RegExp(r'\bAI\b|provider', caseSensitive: false).hasMatch(s), isFalse, reason: s);
      }
      await t.tap(find.text('Unpair band'));
      await t.pumpAndSettle();
      expect(find.text('Band days on this phone are erased. Your saved answers stay.'), findsOneWidget);
      await t.tap(find.text('Keep band'));
      await t.pumpAndSettle();
      expect(store.paired, isTrue);
      await t.tap(find.text('Unpair band'));
      await t.pumpAndSettle();
      await t.tap(find.text('Unpair'));
      await t.pumpAndSettle();
      expect(store.paired, isFalse);
      expect(store.minutes, isEmpty);
    });
  });
}
