import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/health/health_summary.dart';
import 'package:lifesim/health/readback.dart';

final now = DateTime(2026, 10, 24);

void main() {
  test('every read-back asks whether it is accurate', () {
    for (final f in HealthField.values) {
      final c = HealthCandidate(field: f, value: 100, basis: 'test', measuredAt: DateTime(2026, 3, 3));
      expect(readBack(c, imperial: true, now: now), endsWith('Is this accurate?'));
    }
  });

  test('weight in pounds with the date it was measured', () {
    final c = HealthCandidate(field: HealthField.weightKg, value: 78, basis: '', measuredAt: DateTime(2026, 3, 3));
    expect(
      readBack(c, imperial: true, now: now),
      "Apple Health says you weigh about 172 pounds. That was measured on March 3. Is this accurate?",
    );
    expect(readBack(c, imperial: false, now: now), contains('78 kilograms'));
  });

  test('height in feet and inches', () {
    expect(spokenHeight(173, imperial: true), '5 feet 8 inches');
    expect(spokenHeight(182.88, imperial: true), '6 feet');
    expect(spokenHeight(173, imperial: false), '173 centimeters');
  });

  test('durations read naturally', () {
    expect(spokenDuration(45), '45 minutes');
    expect(spokenDuration(60), '1 hour');
    expect(spokenDuration(90), '1 and a half hours');
    expect(spokenDuration(130), '2 hours');
    expect(spokenDuration(420), '7 hours');
  });

  test('blood pressure uses top and bottom number instead of jargon', () {
    const c = HealthCandidate(field: HealthField.systolicBp, value: 126, basis: '');
    final text = readBack(c, imperial: true, now: now);
    expect(text, contains('top number'));
    expect(text, isNot(contains('systolic')));
  });

  test('dates from another year include the year', () {
    expect(spokenDate(DateTime(2025, 12, 1), now), 'December 1, 2025');
  });

  test('imperial only for countries that use it', () {
    expect(usesImperial('US'), isTrue);
    expect(usesImperial('GB'), isFalse);
    expect(usesImperial(null), isFalse);
  });
}
