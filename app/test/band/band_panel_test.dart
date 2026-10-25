import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/band/band_charts.dart';
import 'package:lifesim/band/band_data.dart';
import 'package:lifesim/band/band_screens.dart';
import 'package:lifesim/band/band_service.dart';
import 'package:lifesim/band/band_store.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';

import '../checkin/daily_checkin_test.dart' show profile;
import '../support/app_fonts.dart';

// A Wednesday; the demo's last day is the Tuesday before.
final _now = DateTime(2026, 10, 28, 9);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<(BandStore, BandService)> demoPanel() async {
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => _now,
    );
    await repo.saveConversationProfile({
      ...profile,
      'moderate_recreation_min_week': 30,
    });
    final store = BandStore(StubBandClient(), now: () => _now)..setDemo(true);
    return (store, BandService(repository: repo, now: () => _now));
  }

  Future<void> show(
    WidgetTester t,
    BandStore store,
    BandService svc, {
    Size size = const Size(402, 874),
    double scale = 1,
    GlobalKey? key,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: key,
          child: BandPanelScreen(
            store: store,
            service: svc,
            onBack: () {},
            onSettings: () {},
            onUseSuggestion: (_) {},
          ),
        ),
      ),
    );
    await t.pump();
  }

  Future<void> tapText(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text));
    await t.pump();
    await t.tap(find.text(text));
  }

  Future<void> snap(WidgetTester t, GlobalKey key, String name) async {
    final dir = Directory('${Directory.current.path}/../../evidence_shots')
      ..createSync(recursive: true);
    await t.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('14-day demo: today numbers, 7-day strip, hourly toggle', (
    t,
  ) async {
    final (store, svc) = await demoPanel();
    await show(t, store, svc);
    final d = store.week().days.last;
    expect(find.text(groupThousands(d.steps)), findsOneWidget);
    expect(find.text('${d.moderateMinutes} active minutes'), findsOneWidget);
    expect(
      find.textContaining(
        'Sitting ${durationText(d.sittingMinutes!)} · longest stretch',
      ),
      findsOneWidget,
    );
    expect(find.text('Stood up ${d.standUps} times'), findsOneWidget);
    expect(find.text('Demo data'), findsOneWidget);
    expect(find.text('Mochi has a suggestion'), findsOneWidget);

    final strip = find.byType(BandWeekStrip);
    expect(strip, findsOneWidget);
    final days = t.widget<BandWeekStrip>(strip).days;
    expect(days, hasLength(7));
    expect(days.last.date, d.date);
    expect(
      find.descendant(of: strip, matching: find.byType(CustomPaint)),
      findsWidgets,
    );
    expect(
      find.textContaining('Steps this week: highest'),
      findsNothing,
    ); // semantics only, not drawn text

    expect(
      t.widget<BandHourlyChart>(find.byType(BandHourlyChart)).sitting,
      isFalse,
    );
    await tapText(t, 'Sitting');
    await t.pump();
    expect(
      t.widget<BandHourlyChart>(find.byType(BandHourlyChart)).sitting,
      isTrue,
    );
    expect(find.text('Minutes sitting each hour'), findsOneWidget);
    await tapText(t, 'Steps');
    await t.pump();
    expect(find.text('Steps each hour'), findsOneWidget);
    for (final tick in ['6a', '12p', '6p']) {
      expect(find.text(tick), findsOneWidget);
    }
  });

  testWidgets(
    'an invalid wear day says not enough wear time instead of numbers',
    (t) async {
      final (store, svc) = await demoPanel();
      store.setDemo(false);
      await store.pair(const BandDevice(name: 'LifeTwin Band'));
      for (var m = 0; m < 120; m++) {
        store.addMinute(BandMinute(at: DateTime(2026, 10, 28, 6, m), steps: 4));
      }
      await show(t, store, svc);
      expect(find.text('Not enough wear time today'), findsOneWidget);
      expect(find.textContaining('active minutes'), findsNothing);
      expect(find.textContaining('Stood up'), findsNothing);
    },
  );

  test(
    'semantics summaries name the highest, lowest, today and the busiest hour',
    () async {
      final store = BandStore(StubBandClient(), now: () => _now)..setDemo(true);
      final w = store.week();
      final summary = weekSummary(w.days);
      expect(summary, startsWith('Steps this week: highest '));
      expect(summary, contains('lowest '));
      expect(summary, contains('Today ${groupThousands(w.days.last.steps)}.'));
      expect(
        hourlySummary(w.days.last, sitting: false),
        contains('busiest hour from'),
      );
      expect(
        hourlySummary(w.days.last, sitting: true),
        contains('Longest sitting stretch'),
      );
    },
  );

  testWidgets('charts expose one screen-reader summary each', (t) async {
    final handle = t.ensureSemantics();
    final (store, svc) = await demoPanel();
    await show(t, store, svc);
    expect(
      find.bySemanticsLabel(RegExp(r'^Steps this week: highest')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Steps each hour: busiest hour')),
      findsOneWidget,
    );
    await tapText(t, 'Sitting');
    await t.pump();
    expect(
      find.bySemanticsLabel(RegExp(r'^Sitting each hour: most in the hour')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the suggestion card still opens', (t) async {
    final (store, svc) = await demoPanel();
    var used = 0;
    t.view.physicalSize = const Size(402, 874);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: BandPanelScreen(
          store: store,
          service: svc,
          onBack: () {},
          onSettings: () {},
          onUseSuggestion: (_) => used++,
        ),
      ),
    );
    await t.pump();
    await t.ensureVisible(find.text('Mochi has a suggestion'));
    await t.tap(find.text('Mochi has a suggestion'));
    expect(used, 1);
  });

  for (final (scale, size) in [
    (1.6, const Size(402, 874)),
    (1.6, const Size(320, 640)),
    (1.0, const Size(320, 640)),
  ]) {
    testWidgets('no overflow at ${size.width.toInt()} wide, text ${scale}x', (
      t,
    ) async {
      final (store, svc) = await demoPanel();
      await show(t, store, svc, size: size, scale: scale);
      expect(t.takeException(), isNull);
      await tapText(t, 'Sitting');
      await t.pump();
      await tapText(t, 'How the band counts');
      await t.pump();
      expect(t.takeException(), isNull);
      // The three hour ticks never overlap each other.
      final boxes = [
        for (final k in ['6a', '12p', '6p']) t.getRect(find.text(k)),
      ];
      expect(boxes[0].overlaps(boxes[1]), isFalse);
      expect(boxes[1].overlaps(boxes[2]), isFalse);
    });
  }

  testWidgets('render evidence shots', (t) async {
    // Material icons are not in the test font set; load them when the SDK is findable so shots show real glyphs.
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      final f = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (f.existsSync()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
        await loader.load();
      }
    }
    final (store, svc) = await demoPanel();
    final key = GlobalKey();
    // 402 wide like the phone; tall enough to show the whole page in one image (the page scrolls on a device).
    await show(t, store, svc, size: const Size(402, 1500), key: key);
    await tapText(t, 'How the band counts');
    await t.pump();
    await snap(t, key, 'band_panel.png');
    await tapText(t, 'Sitting');
    await t.pump();
    await snap(t, key, 'band_panel_sitting.png');
  });
}
