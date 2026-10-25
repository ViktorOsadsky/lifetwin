// Seam: what the app really SENDS. Every request body below is produced by the app's own
// client and context code (coachContext, HttpCheckinClient, HttpConversationGuide,
// HttpChangeClient, HttpDocumentExtractor, HttpCoachClient) with a recording HTTP client, then
// compared with test/fixtures/app_requests.json. The server tests
// (server/tests/test_seams.py) replay that file against the real in-process server and
// validate each body against the contracts/ request schemas, so a drift on either side fails.
//
// Update the file after a deliberate change with:
//   UPDATE_SEAM_FIXTURES=1 flutter test test/seams/app_requests_test.dart
// then regenerate the server side with `uv run python server/tests/make_seam_fixture.py`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/checkin/change_chat.dart';
import 'package:lifesim/checkin/checkin_client.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/documents/document_extract.dart';
import 'package:lifesim/twin/twin_checkin_store.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/voice/http_conversation_guide.dart';
import 'package:lifesim/wellness/coach_client.dart';
import 'package:lifesim/wellness/coach_context.dart';

const fixturePath = 'test/fixtures/app_requests.json';
final Map<String, dynamic> flow =
    jsonDecode(File('test/fixtures/merged_flow.json').readAsStringSync()) as Map<String, dynamic>;
Map<String, dynamic> copy(Object? j) => Map<String, dynamic>.from(jsonDecode(jsonEncode(j)) as Map);

class _Port implements NotificationPort {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime localWallTime,
    required String title,
    required String body,
  }) async {}
  @override
  Future<void> cancelAll() async {}
}

class Recorder {
  final calls = <Map<String, dynamic>>[];
  late final http.Client client = MockClient((request) async {
    calls.add({'path': request.url.path, 'body': jsonDecode(request.body)});
    // Any well-formed answer: these tests only look at what was sent.
    return http.Response(jsonEncode(reply), 200);
  });
  Object reply = <String, dynamic>{};
  Map<String, dynamic> get last => calls.last;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('what the app sends matches test/fixtures/app_requests.json', () async {
    final model = await TwinModelService.load();
    // Monday 26 October 2026, morning, after a week of check-ins: the context the Today
    // card and the daily plan send.
    final now = DateTime(2026, 10, 26, 9, 30);
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      reminders: CheckinReminders(_Port()),
      clock: () => now,
    );
    final checkins = TwinCheckinStore(repo);
    final ready = copy(flow['onboarding_ready']);
    await repo.saveOnboarding(
      Map<String, dynamic>.from(ready['state'] as Map),
      modelInputs: Map<String, dynamic>.from(ready['model_inputs'] as Map),
      sources: const {
        'height_cm': HistorySource.appleHealth,
        'weight_kg': HistorySource.appleHealth,
        'sleep_hours': HistorySource.appleHealth,
      },
    );
    for (final r in flow['quick_week'] as List) {
      final day = (r as Map)['state']['local_date'] as String;
      await checkins.applyFinishedCheckin(copy(r), localDate: day);
    }
    await checkins.applyFinishedCheckin(copy(flow['weekly']), localDate: '2026-10-25');
    repo.refresh();

    final out = <String, dynamic>{
      'about':
          'Request bodies recorded from the app\'s own clients by app/test/seams/app_requests_test.dart. '
          'Replayed against the server by server/tests/test_seams.py.',
    };

    // Coach: the exact body HttpCoachClient posts.
    final coach = Recorder();
    await HttpCoachClient(
      base: ApiBase('https://t.test'),
      client: coach.client,
    ).plan(coachContext(repo, now: now)).then((_) {}, onError: (_) {});
    out['coach_plan'] = coach.last;

    // Check-ins: start (quick, daily, weekly, with age) and a turn.
    final c = Recorder()..reply = copy(flow['daily']);
    final guide = HttpCheckinClient(client: c.client, base: ApiBase('https://t.test'), age: () => repo.profile['age']);
    await guide.start(
      kind: 'quick',
      localDate: '2026-10-26',
      previous: const {'sleep_hours_last_night': 7},
      quick: const QuickPlan(
        topics: [QuickTopic.sleep, QuickTopic.activity, QuickTopic.sitting],
        activityDay: 'yesterday',
        catchUp: true,
        suggestedSleepLastNight: 7.5,
        suggestedActivityMinutes: 30,
      ),
    );
    out['checkin_start_quick'] = c.last;
    await guide.start(kind: 'daily', localDate: '2026-10-26');
    out['checkin_start_daily'] = c.last;
    await guide.start(kind: 'weekly', localDate: '2026-10-25');
    out['checkin_start_weekly'] = c.last;
    await guide.turn(action: 'reply', state: const {}, text: 'about 7 hours', fromTranscript: true);
    out['checkin_turn_reply'] = c.last;
    await guide.turn(action: 'confirm', state: const {});
    out['checkin_turn_confirm'] = c.last;

    // Onboarding.
    final o = Recorder()..reply = ready;
    final onboarding = HttpConversationGuide(client: o.client, base: ApiBase('https://t.test'));
    await onboarding.turn(action: 'start', aiHelper: false);
    out['onboarding_start'] = o.last;
    await onboarding.turn(action: 'reply', state: const {}, text: 'I\'m 72, female', aiHelper: true);
    out['onboarding_reply'] = o.last;
    await onboarding.turn(
      action: 'import',
      state: const {},
      values: const {'height_cm': 162.6, 'weight_kg': 68.0, 'sleep_hours': 6.5},
      importSource: 'apple_health',
    );
    out['onboarding_import'] = o.last;

    // Change conversation.
    final ch = Recorder()..reply = copy(flow['daily']);
    final change = HttpChangeClient(client: ch.client, base: ApiBase('https://t.test'));
    final profile = Map<String, dynamic>.from(repo.profile);
    await change.start(profile: profile, field: 'weight_kg', memoryConsent: true);
    out['change_start'] = ch.last;
    await change.turn(
      action: 'reply',
      state: const {},
      profile: profile,
      memoryConsent: false,
      text: 'I lost some weight',
    );
    out['change_turn'] = ch.last;

    // Documents.
    final d = Recorder()..reply = <String, dynamic>{'schema_version': '1.0', 'candidates': []};
    await HttpDocumentExtractor(client: d.client, base: ApiBase('https://t.test')).extract([
      'Blood pressure 128/78 mmHg on 2026-10-01',
    ]).then((_) {}, onError: (_) {});
    out['documents_extract'] = d.last;

    final text = '${const JsonEncoder.withIndent(' ').convert(out)}\n';
    if (Platform.environment['UPDATE_SEAM_FIXTURES'] == '1') {
      File(fixturePath).writeAsStringSync(text);
    }
    expect(
      File(fixturePath).readAsStringSync(),
      text,
      reason: 'app request bodies changed; run with UPDATE_SEAM_FIXTURES=1 and regenerate the server fixture',
    );
  });
}
