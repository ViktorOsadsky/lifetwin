import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/forecast/profile_labels.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';

GuideTurn _turn(String phase, String? current, Map<String, dynamic> confirmed, {List<String> skipped = const [], List<String> unknown = const [], bool complete = false}) =>
    GuideTurn(
      state: {
        'phase': phase,
        'current_field': current,
        'confirmed_profile': confirmed,
        'skipped_fields': skipped,
        'unknown_fields': unknown,
      },
      message: 'x',
      complete: complete,
    );

void main() {
  VoiceOnboardingController make() =>
      VoiceOnboardingController(guide: FakeConversationGuide(), input: FakeSpeechInput(), output: FakeSpeechOutput());

  test('the count is the number of asked questions, so the last one is 12 of 12 once', () {
    final c = make();
    expect(VoiceOnboardingController.questionCount, 12);
    final done = VoiceOnboardingController.askedFields.sublist(0, 11);
    c.turn = _turn('asking', 'vigorous_recreation_min_week', {for (final f in done.sublist(0, 6)) f: 1}, skipped: done.sublist(6, 9), unknown: done.sublist(9));
    expect(c.questionNumber, 12);
  });

  test('"I don\'t know" and skipped answers each count as done', () {
    final c = make();
    c.turn = _turn('asking', 'sex', {'age': 60}, unknown: ['smoking_status'], skipped: ['height_cm']);
    expect(c.questionNumber, 4);
  });

  test('a follow-up question or the end shows no number', () {
    final c = make();
    c.turn = _turn('probing', null, {'age': 60});
    expect(c.questionNumber, isNull);
    c.turn = _turn('ready', null, {'age': 60}, complete: true);
    expect(c.questionNumber, isNull);
  });

  test('labels for the five model inputs', () {
    final labels = {for (final (k, l) in profileLabels({
      'general_health': 'very_good',
      'hypertension_diagnosed': false,
      'sedentary_min_day': 360,
      'moderate_recreation_min_week': 150,
      'vigorous_recreation_min_week': 0,
    }, imperial: false)) k: l};
    expect(labels, {
      'general_health': 'Health: very good',
      'hypertension_diagnosed': 'Told you have high blood pressure: no',
      'sedentary_min_day': 'Sitting: 6 h a day',
      'moderate_recreation_min_week': 'Easier activity: 150 min a week',
      'vigorous_recreation_min_week': 'Out-of-breath activity: none',
    });
    expect(profileLabels({'hypertension_diagnosed': true}, imperial: false).single.$2, 'Told you have high blood pressure: yes');
  });

  test('unreadable values say not sure, never 0', () {
    final l = [for (final (_, t) in profileLabels({'general_health': '?', 'sedentary_min_day': 'x', 'vigorous_recreation_min_week': 'x'}, imperial: false)) t];
    expect(l, ['Health: not sure', 'Sitting: not sure', 'Out-of-breath activity: not sure']);
  });
}
