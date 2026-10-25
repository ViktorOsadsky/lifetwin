import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/checkin/checkin_client.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/voice/api_base.dart';

class FakePort implements NotificationPort {
  bool allow = true;
  int asks = 0;
  int clears = 0;
  final scheduled = <(int, DateTime, String)>[];

  @override
  Future<bool> requestPermission() async {
    asks++;
    return allow;
  }

  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime localWallTime,
    required String title,
    required String body,
  }) async => scheduled.add((id, localWallTime, body));

  @override
  Future<void> cancelAll() async {
    clears++;
    scheduled.clear();
  }
}

void main() {
  late FakePort port;
  late CheckinReminders reminders;
  const on = CheckinSettings(remindersOn: true, reminderOffered: true);
  setUp(() {
    port = FakePort();
    reminders = CheckinReminders(port);
  });

  group('reminders', () {
    test('are offered only after a finished check-in, and only once', () {
      expect(reminders.shouldOffer(const CheckinSettings(), []), isFalse); // never on first launch
      final history = [const CheckinEntry(kind: 'quick', date: '2026-10-24', answers: {})];
      expect(reminders.shouldOffer(const CheckinSettings(), history), isTrue);
      expect(reminders.shouldOffer(reminders.decline(const CheckinSettings()), history), isFalse);
    });

    test('are offered at the end of onboarding too, still only once', () {
      expect(reminders.shouldOffer(const CheckinSettings(), [], onboarded: true), isTrue);
      expect(reminders.shouldOffer(reminders.decline(const CheckinSettings()), [], onboarded: true), isFalse);
      expect(reminders.shouldOffer(on, [], onboarded: true), isFalse); // already on
    });

    test('a week away ends with a gentle pause, not silence', () async {
      await reminders.reschedule(on, localNow: DateTime(2026, 10, 24, 8), history: []);
      final bodies = port.scheduled.map((s) => s.$3).toList();
      expect(bodies, hasLength(reminderDays));
      expect(bodies.last, reminderPauseLine);
      expect(bodies.take(reminderDays - 1), everyElement(isIn(reminderLines)));
    });

    test('default to 10:00 and plan a week ahead, each at the chosen wall time', () async {
      final planned = await reminders.reschedule(on, localNow: DateTime(2026, 10, 24, 8), history: []);
      expect(planned, hasLength(reminderDays));
      expect(planned.first, DateTime(2026, 10, 24, 10));
      expect(planned.every((t) => t.hour == 10 && t.minute == 0), isTrue);
      expect(port.scheduled.map((s) => s.$1).toSet(), hasLength(reminderDays)); // one id per day
    });

    test('skip today once it is done or its time has passed', () async {
      final done = [const CheckinEntry(kind: 'quick', date: '2026-10-24', answers: {})];
      final afterDone = await reminders.reschedule(on, localNow: DateTime(2026, 10, 24, 8), history: done);
      expect(afterDone.first, DateTime(2026, 10, 25, 10));
      final late = await reminders.reschedule(on, localNow: DateTime(2026, 10, 24, 11), history: []);
      expect(late.first, DateTime(2026, 10, 25, 10));
      expect(late, hasLength(reminderDays));
    });

    test('stay at the same wall time across a daylight saving change', () async {
      // US clocks go back on 1 November 2026.
      final planned = await reminders.reschedule(
        on.copyWith(reminderHour: 9, reminderMinute: 15),
        localNow: DateTime(2026, 10, 30, 12),
        history: [],
      );
      expect(planned.map((t) => (t.month, t.day, t.hour, t.minute)), [
        for (final d in [(10, 31), (11, 1), (11, 2), (11, 3), (11, 4), (11, 5), (11, 6)]) (d.$1, d.$2, 9, 15),
      ]);
    });

    test('permission is asked only when the person says yes', () async {
      final next = await reminders.accept(
        const CheckinSettings(),
        localNow: DateTime(2026, 10, 24, 12),
        history: [],
        hour: 18,
        minute: 30,
      );
      expect(port.asks, 1);
      expect(next.remindersOn, isTrue);
      expect(next.reminderOffered, isTrue);
      expect(port.scheduled.first.$2, DateTime(2026, 10, 24, 18, 30));
    });

    test('if the phone says no, nothing is planned', () async {
      port.allow = false;
      final next = await reminders.accept(const CheckinSettings(), localNow: DateTime(2026, 10, 24, 8), history: []);
      expect(next.remindersOn, isFalse);
      expect(port.scheduled, isEmpty);
    });

    test('turning them off removes the planned ones', () async {
      await reminders.reschedule(on, localNow: DateTime(2026, 10, 24, 8), history: []);
      final off = await reminders.turnOff(on);
      expect(off.remindersOn, isFalse);
      expect(port.scheduled, isEmpty);
    });

    test('the words invite; they never mention missed days, streaks or health claims', () {
      for (final line in [...reminderLines, reminderPauseLine]) {
        expect(line.length, lessThan(80));
        expect(
          RegExp(r'missed|streak|forgot|again|late|healthier|improv|risk|should', caseSensitive: false).hasMatch(line),
          isFalse,
          reason: line,
        );
      }
    });
  });

  group('HTTP client', () {
    test('start sends the plan and the phone date; turn sends the state back', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'message': 'How did you sleep last night?',
            'complete': false,
            'emergency': false,
            'state': {'kind': 'quick', 'phase': 'asking', 'current_field': 'sleep_hours_last_night'},
            'mascot_events': [
              {'state': 'asking', 'caption': 'x'},
            ],
            'daily_logs': [
              {'date': '2026-10-23', 'sleep_hours': null, 'sedentary_min_day': 300},
            ],
          }),
          200,
        );
      });
      final api = HttpCheckinClient(client: client, base: ApiBase('http://test', client));
      final first = await api.start(
        kind: 'quick',
        localDate: '2026-10-24',
        quick: const QuickPlan(topics: [QuickTopic.sleep], activityDay: 'yesterday'),
      );
      expect(bodies.single['quick'], {
        'topics': ['sleep'],
        'activity_day': 'yesterday',
        'catch_up': false,
        'suggested': <String, dynamic>{},
      });
      expect(bodies.single['local_date'], '2026-10-24');
      expect(first.dailyLogs.single, const DayLog(date: '2026-10-23', sedentaryMin: 300));
      await api.turn(action: 'reply', state: first.state, text: '7 hours', fromTranscript: true);
      expect(bodies.last, {'action': 'reply', 'state': first.state, 'text': '7 hours', 'input_mode': 'transcript'});
    });

    test('each turn carries the consent for the current provider, never another or an empty map', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'state': {'kind': 'daily'},
            'message': 'Hi',
            'events': [
              {'state': 'asking', 'caption': 'x'},
            ],
          }),
          200,
        );
      });
      var consent = <String, bool>{'claude': true};
      final api = HttpCheckinClient(client: client, base: ApiBase('http://test', client), aiConsent: () => consent);
      await api.turn(action: 'reply', state: const {'kind': 'daily'}, text: 'okay');
      expect(bodies.last['outside_ai_consent'], {'claude': true});
      consent = {'claude': false, 'someone_else': true};
      await api.turn(action: 'reply', state: const {'kind': 'daily'}, text: 'okay');
      expect(bodies.last.containsKey('outside_ai_consent'), isFalse, reason: 'no yes for a provider the server knows');
      final plain = HttpCheckinClient(client: client, base: ApiBase('http://test', client));
      await plain.turn(action: 'reply', state: const {'kind': 'daily'}, text: 'okay');
      expect(bodies.last.containsKey('outside_ai_consent'), isFalse);
    });

    test("a refusal carries the server's words; a bare error is the network", () async {
      var status = 409;
      final client = MockClient(
        (request) async => http.Response(
          status == 409 ? jsonEncode({'status': 'error', 'code': 'x', 'message': 'Please start again.'}) : '',
          status,
        ),
      );
      final api = HttpCheckinClient(client: client, base: ApiBase('http://test', client));
      await expectLater(
        api.turn(action: 'confirm', state: const {}),
        throwsA(isA<GuideRejected>().having((e) => e.message, 'message', 'Please start again.')),
      );
      status = 502;
      await expectLater(api.turn(action: 'confirm', state: const {}), throwsA(isA<GuideFailure>()));
      status = 429;
      await expectLater(api.turn(action: 'confirm', state: const {}), throwsA(isA<GuideTooBusy>()));
    });
  });
}
