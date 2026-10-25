import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/wellness/history_screen.dart';
import 'package:lifesim/wellness/models.dart';
import 'package:lifesim/wellness/coach_context.dart';
import 'package:lifesim/wellness/repository_adapter.dart';

class NoForecast implements ForecastClient {
  @override
  Future<Forecast> predict(Map<String, dynamic> profile) async =>
      throw const ForecastFailure('Not requested');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final flow = jsonDecode(
    File('test/fixtures/merged_flow.json').readAsStringSync(),
  ) as Map;
  Map<String, dynamic> copy(Object? value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());
  late DateTime now;
  late TwinRepository repo;
  late RepositoryWellness adapter;
  setUp(() async {
    now = DateTime(2026, 10, 26, 9, 30);
    repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => now,
    );
    adapter = RepositoryWellness(repo, now: () => now);
  });
  test('coach reads a fresh confirmed snapshot and scoped consent, without filling gaps', () async {
    var context = coachContext(repo, now: now);
    expect(context['profile'], isEmpty);
    expect(context['checkins'], isEmpty);
    expect(context['habit_notes'], isNull);
    expect(context['outside_ai_consent'], isEmpty);
    expect(context['local_date'], '2026-10-26');
    expect(context['local_time'], '09:30');
    await repo.saveConversationProfile({'age': 60, 'height_cm': 160, 'weight_kg': 70},
      sources: {'weight_kg': HistorySource.wristband});
    await repo.setOutsideAiConsent(true, provider: 'muse');
    context = coachContext(repo, now: now);
    expect(context['profile'], {'age': 60, 'height_cm': 160});
    expect(context['outside_ai_consent'], {'muse': true});
    expect(context, isNot(contains('healthScore')));
    expect(context, isNot(contains('experiment')));
    await repo.deleteMyData();
    context = coachContext(repo, now: now);
    expect(context['profile'], isEmpty);
    expect(context['outside_ai_consent'], isEmpty);
  });

  tearDown(() {
    adapter.dispose();
    repo.dispose();
  });

  Future<void> onboard() async {
    final ready = copy(flow['onboarding_ready']);
    await repo.saveOnboarding(
      copy(ready['state']),
      modelInputs: copy(ready['model_inputs']),
      sources: const {'height_cm': HistorySource.appleHealth},
    );
  }

  Future<void> quickDays() async {
    for (final raw in (flow['quick_week'] as List).take(4)) {
      final response = copy(raw);
      final date = (response['state'] as Map)['local_date'] as String;
      final day = DateTime.parse(date);
      now = DateTime(day.year, day.month, day.day, 20, 15);
      await repo.applyCheckin(response, localDate: date);
    }
    now = DateTime(2026, 10, 26, 9, 30);
    repo.refresh();
  }

  test('real history and day logs remain unknown until confirmed, with no invented score', () async {
    expect(adapter.snapshot.displayScore, isNull);
    expect(
      adapter.snapshot.days.every((d) => d.values.isEmpty && !d.logged),
      isTrue,
    );
    await onboard();
    expect(
      adapter.snapshot.days.every((d) => !d.logged),
      isTrue,
    ); // onboarding is not a check-in
    await quickDays();
    final snapshot = adapter.snapshot;
    expect(snapshot.goodWeeks, 1);
    expect(snapshot.goodWeeks, repo.goodWeeks());
    expect(snapshot.days.length, 7);
    expect(snapshot.days.every((d) => d.healthScore == null), isTrue);
    expect(snapshot.days.any((d) => d.logged), isTrue);
    expect(snapshot.days.last.date, DateTime(2026, 10, 26));
    expect(snapshot.days.last.values, isEmpty);
    expect(
      snapshot.days
          .where((d) => d.values.isNotEmpty)
          .expand((d) => d.values)
          .every((v) => v.source == ValueSource.youSaid),
      isTrue,
    );
  });

  test('read-only mapping retains mixed sources, estimates, corrections and previous values', () async {
    await onboard();
    await quickDays();
    await repo.recordImport({
      'sleep_hours': 7,
    }, source: HistorySource.wristband);
    final row = repo.store.dayLogs.firstWhere((d) => d.sleepHours != null);
    final day = DateTime.parse(row.date);
    final corrected = await repo.applyDayCorrection(
      day,
      'sleep_hours',
      row.sleepHours == 5.5 ? 6.5 : 5.5,
    );
    expect(corrected, isNotNull);
    final values = adapter.historyDays().expand((d) => d.values).toList();
    expect(values.any((v) => v.source == ValueSource.appleHealth), isTrue);
    expect(
      values.any((v) => v.source == ValueSource.wristband && v.estimated),
      isTrue,
    );
    expect(values.any((v) => v.previousValue != null), isTrue);
    expect(values.any((v) => v.status == 'Later corrected'), isTrue);
    expect(values.every((v) => v.recordedAt != null), isTrue);
    expect(
      repo.store.dayLogs.firstWhere((d) => d.date == row.date).sleepHours,
      corrected!.items.single.value,
    );
  });

  test('repository notifications refresh the presentation and deletion clears its history', () async {
    var changes = 0;
    adapter.addListener(() => changes++);
    await onboard();
    expect(changes, greaterThan(0));
    expect(adapter.historyDays(), isNotEmpty);
    await repo.setOutsideAiConsent(true, provider: 'muse');
    expect(adapter.settingsFor(providerId: 'muse').personalSuggestions, isTrue);
    expect(
      adapter.settingsFor(providerId: 'other').personalSuggestions,
      isFalse,
    );
    await repo.deleteMyData();
    expect(adapter.historyDays(), isEmpty);
    expect(adapter.snapshot.goodWeeks, 0);
    expect(adapter.settingsFor().reminderMinutes, 600);
    expect(adapter.settingsFor().personalSuggestions, isFalse);
  });

  testWidgets('the actual app opens repository History from wellness Home', (
    t,
  ) async {
    now = DateTime.now();
    await t.runAsync(onboard);
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final controller = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: FakeSpeechInput(),
      output: FakeSpeechOutput(),
    );
    await t.pumpWidget(
      LifeTwinApp(
        controller: controller,
        forecastClient: NoForecast(),
        twin: Future.value(repo),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('My history'));
    await t.tap(find.text('My history'));
    await t.pumpAndSettle();
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('Your history'), findsOneWidget);
    expect(find.text('Apple Health'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
