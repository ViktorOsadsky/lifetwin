import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/health/health_reader.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/health/health_screen.dart';
import 'package:lifesim/health/health_summary.dart';

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
  await t.pumpWidget(MaterialApp(
      home: HealthImportScreen(reader: reader, now: () => now, onDone: (r) => result = r)));
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
    await t.pumpWidget(MaterialApp(
        home: HealthImportScreen(reader: FakeReader(samples), now: () => now, onDone: (r) => result = r)));
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
    await t.pumpWidget(MaterialApp(
        home: HealthImportScreen(reader: FakeReader(samples), now: () => now, onDone: (r) => result = r)));
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
    await t.pumpWidget(MaterialApp(home: HealthImportScreen(reader: FakeReader(samples), onDone: (r) => result = r)));
    await t.tap(find.text("No thanks, I'll answer myself"));
    expect(result!.samples, isEmpty);
    expect(result!.toAsk, HealthField.values);
  });
}
