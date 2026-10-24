// QA: Apple Health import with sample readings (a fake reader; the simulator's Health
// app has no data and its permission sheet is native). Checked values become answers,
// those questions are not asked again, and nothing gets stuck.
//   flutter test integration_test/qa_health_test.dart -d <sim> --dart-define=API_BASE_URL=http://127.0.0.1:8051
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/health/health_reader.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';

import 'support/qa_support.dart';

class FakeReader extends HealthReader {
  FakeReader(this.samples);
  final List<HealthSample> samples;
  @override
  Future<bool> requestAccess() async => true;
  @override
  Future<List<HealthSample>> read({required DateTime now, int days = 30}) async => samples;
}

/// Height 1.65 m, 68 kg, 7 h sleep a night, 150 min exercise a week, 128/82.
List<HealthSample> readings(DateTime now) {
  HealthSample s(String type, DateTime start, DateTime end, num value) =>
      HealthSample(type: type, start: start, end: end, value: value);
  final day = DateTime(now.year, now.month, now.day);
  return [
    s('HEIGHT', day.subtract(const Duration(days: 40)), day.subtract(const Duration(days: 40)), 1.65),
    s('WEIGHT', day.subtract(const Duration(days: 2)), day.subtract(const Duration(days: 2)), 68),
    for (var d = 1; d <= 6; d++)
      s(
        'SLEEP_ASLEEP',
        day.subtract(Duration(days: d, hours: 1)),
        day.subtract(Duration(days: d)).add(const Duration(hours: 6)),
        420,
      ),
    for (var d = 1; d <= 28; d++)
      if (d % 7 < 5)
        // Counted back from now, not from midnight, so the oldest one stays inside the
        // 28-day window whatever the time of day (from 9:00 on it used to fall out: 143).
        s(
          'EXERCISE_TIME',
          now.subtract(Duration(days: d)).add(const Duration(minutes: 5)),
          now.subtract(Duration(days: d)).add(const Duration(minutes: 35)),
          30,
        ),
    s('BLOOD_PRESSURE_SYSTOLIC', day.subtract(const Duration(days: 3)), day.subtract(const Duration(days: 3)), 128),
    s('BLOOD_PRESSURE_DIASTOLIC', day.subtract(const Duration(days: 3)), day.subtract(const Duration(days: 3)), 82),
  ];
}

Future<void> openHealth(WidgetTester t, String label) async {
  await hideKeyboard(t);
  await tapText(t, label);
  await tapText(t, 'Yes, use Apple Health');
}

/// Answers every Health question: [wrong] counts down the ones marked "No, let me fix it".
Future<void> checkAll(WidgetTester t, {int wrong = 0}) async {
  for (var i = 0; i < 10 && find.text('Thank you').evaluate().isEmpty; i++) {
    await pumpFor(t, const Duration(milliseconds: 900)); // the screen ignores a quick second tap
    await tapText(t, wrong-- > 0 ? 'No, let me fix it' : "Yes, that's right");
  }
  await tapText(t, 'Continue');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(qaReset);

  testWidgets('Health readings become answers; those questions are not asked again', (t) async {
    await startTyped(t, app: LifeTwinApp(healthReader: FakeReader(readings(DateTime.now()))));
    await openHealth(t, 'Use my Apple Health');
    await checkAll(t);
    await waitFor(t, find.textContaining('from Apple Health'));
    await settled(t);
    final c = ctl(t);
    expect(c.notice, isNull);
    expect(c.state?['current_field'], 'age', reason: 'the open question stays');
    final p = c.confirmedProfile;
    expect((p['height_cm'] as num).round(), 165);
    expect((p['weight_kg'] as num).round(), 68);
    expect(p['sleep_hours'], 7);
    expect(p['exercise_minutes_weekly'], 150);
    expect(p['systolic_bp'], 128);
    expect(p['diastolic_bp'], 82);
    await say(t, '71', 'you are 71');
    await yes(t, 'What sex');
    await tapText(t, 'Female');
    await waitFor(t, find.textContaining('female at birth'));
    await settled(t);
    await yes(t, 'Do you smoke'); // height, weight, sleep and exercise are not asked
    await tapText(t, 'I never smoked');
    await waitFor(t, find.textContaining('never smoked'));
    await settled(t);
    await yes(t, 'alcoholic drinks');
    await say(t, 'none', "don't drink");
    await yes(t, 'diabetes');
    await tapText(t, 'No');
    await waitFor(t, find.textContaining('not told you'));
    await settled(t);
    await yes(t, 'All done'); // blood pressure came from Health
    await tapText(t, 'Continue');
    await askTheBall(t);
    await waitFor(t, find.textContaining('were still living 5 years later'));
  });

  testWidgets('a reading marked wrong is asked; none found says so; Health again after done', (t) async {
    await startTyped(t, app: LifeTwinApp(healthReader: FakeReader(readings(DateTime.now()))));
    // Height (the first reading) is marked wrong, so it is asked later.
    await openHealth(t, 'Use my Apple Health');
    await checkAll(t, wrong: 1);
    await waitFor(t, find.textContaining('from Apple Health'));
    await settled(t);
    expect(ctl(t).confirmedProfile['height_cm'], isNull);
    await say(t, '71', 'you are 71');
    await yes(t, 'What sex');
    await tapText(t, 'Male');
    await waitFor(t, find.textContaining('male at birth'));
    await settled(t);
    await yes(t, 'How tall');
    await say(t, '5 foot 6', '5 feet 6 inches');
    await yes(t, 'Do you smoke');
    for (var i = 0; i < 6 && find.text('Continue').evaluate().isEmpty; i++) {
      await tapText(t, 'Skip this question');
      await pumpFor(t, const Duration(milliseconds: 600));
      await settled(t);
    }
    // From the done screen, the Health app again: values checked again, still done.
    await openHealth(t, 'Use my Apple Health');
    await checkAll(t);
    await waitFor(t, find.textContaining('from Apple Health'));
    await settled(t);
    await pumpFor(t, const Duration(seconds: 1)); // the Health screen slides away
    expect(ctl(t).phase, VoicePhase.done);
    expect(find.text('Continue'), findsOneWidget);
    expect((ctl(t).confirmedProfile['height_cm'] as num).round(), 165);
  });

  testWidgets('no Health readings: plain words, and the questions go on', (t) async {
    await startTyped(t, app: LifeTwinApp(healthReader: FakeReader(const [])));
    await openHealth(t, 'Use my Apple Health');
    await waitFor(t, find.text("I couldn't find any readings"));
    await tapText(t, 'Continue');
    await waitFor(t, find.text(healthNoneNotice));
    await pumpFor(t, const Duration(milliseconds: 800)); // the Health screen slides away
    await say(t, '71', 'you are 71');
  });
}
