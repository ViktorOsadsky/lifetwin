import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/health/health_reader.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/health/health_screen.dart';
import 'package:lifesim/health/health_summary.dart';
import 'package:lifesim/ui/widgets/widgets.dart';

final now = DateTime(2026, 10, 24, 12);

class FakeReader extends HealthReader {
  FakeReader(this.samples, {this.fail = false});
  final List<HealthSample> samples;
  final bool fail;

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<List<HealthSample>> read({required DateTime now, int days = 30}) async {
    if (fail) throw Exception('HealthKit unavailable');
    return samples;
  }
}

Future<HealthImportResult?> run(WidgetTester t, HealthReader reader, List<String> taps) async {
  HealthImportResult? result;
  await t.pumpWidget(
    MaterialApp(
      home: HealthImportScreen(reader: reader, now: () => now, onDone: (r) => result = r),
    ),
  );
  await t.tap(find.text('Yes, use my Health app'));
  await t.pumpAndSettle();
  for (final label in taps) {
    await t.tap(find.text(label));
    await t.pump(const Duration(seconds: 1));
  }
  await t.tap(find.text('Continue'));
  await t.pump();
  return result;
}

void main() {
  final samples = [
    HealthSample(type: 'WEIGHT', start: DateTime(2026, 10, 20), end: DateTime(2026, 10, 20), value: 78),
    HealthSample(type: 'HEIGHT', start: DateTime(2026, 3, 1), end: DateTime(2026, 3, 1), value: 1.73),
  ];

  testWidgets('confirmed and corrected values are kept apart', (t) async {
    final r = await run(t, FakeReader(samples), ["Yes, that's right", 'No, let me fix it']);
    expect(r!.confirmed.map((c) => c.field), [HealthField.heightCm]);
    expect(r.toAsk, contains(HealthField.weightKg));
    expect(r.toAsk, contains(HealthField.sleepHours)); // nothing found, so the mascot asks
    expect(r.samples, samples);
  });

  testWidgets('a quick double tap answers only one question', (t) async {
    HealthImportResult? result;
    await t.pumpWidget(
      MaterialApp(
        home: HealthImportScreen(reader: FakeReader(samples), now: () => now, onDone: (r) => result = r),
      ),
    );
    await t.tap(find.text('Yes, use my Health app'));
    await t.pumpAndSettle();
    expect(find.text('Question 1 of 2'), findsOneWidget);
    await t.tap(find.text("Yes, that's right"));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text("Yes, that's right"));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Question 2 of 2'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    expect(result, isNull);
  });

  testWidgets('go back undoes a mistaken answer', (t) async {
    HealthImportResult? result;
    await t.pumpWidget(
      MaterialApp(
        home: HealthImportScreen(reader: FakeReader(samples), now: () => now, onDone: (r) => result = r),
      ),
    );
    await t.tap(find.text('Yes, use my Health app'));
    await t.pumpAndSettle();
    expect(find.text('Go back'), findsNothing);
    await t.tap(find.text("Yes, that's right"));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('Go back'));
    await t.pump();
    expect(find.text('Question 1 of 2'), findsOneWidget);
    await t.tap(find.text('No, let me fix it'));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text("Yes, that's right"));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('Continue'));
    expect(result!.confirmed.map((c) => c.field), [HealthField.weightKg]);
    expect(result!.toAsk.where((f) => f == HealthField.heightCm), hasLength(1));
  });

  testWidgets('a Health app failure falls back to asking, without crashing', (t) async {
    final r = await run(t, FakeReader(const [], fail: true), []);
    expect(r!.confirmed, isEmpty);
    expect(r.toAsk, HealthField.values);
  });

  testWidgets('saying no skips Health entirely', (t) async {
    HealthImportResult? result;
    await t.pumpWidget(
      MaterialApp(
        home: HealthImportScreen(reader: FakeReader(samples), onDone: (r) => result = r),
      ),
    );
    await t.tap(find.text("No thanks, I'll answer myself"));
    expect(result!.samples, isEmpty);
    expect(result!.toAsk, HealthField.values);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('scale $scale on a 390x844 phone: the twin and big buttons on every step, nothing overflows', (
      t,
    ) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: HealthImportScreen(reader: FakeReader(samples), now: () => now, onDone: (_) {}),
          ),
        ),
      );
      Future<void> check(String label) async {
        expect(t.takeException(), isNull, reason: label);
        expect(find.byType(TwinSprite), findsOneWidget, reason: label);
        final b = find.ancestor(of: find.text(label), matching: find.byType(LipButton));
        expect(t.getSize(b).height, greaterThanOrEqualTo(72), reason: label);
        // The test font is far wider than the real one, so at 2.0 the pinned buttons
        // may need their own scroll here; on screen at 1.0.
        if (scale == 1.0) expect(t.getRect(b).bottom, lessThanOrEqualTo(844), reason: label);
        await t.ensureVisible(find.text(label));
        await t.pump();
        await t.tap(find.text(label));
        await t.pump(const Duration(seconds: 1));
      }

      await check('Yes, use my Health app');
      await t.pumpAndSettle();
      await check("Yes, that's right");
      await check('No, let me fix it');
      expect(find.text('Thank you'), findsOneWidget);
      expect(t.widget<TwinSprite>(find.byType(TwinSprite)).pose, TwinMood.pleased.pose);
      await check('Continue');
    });
  }
}
