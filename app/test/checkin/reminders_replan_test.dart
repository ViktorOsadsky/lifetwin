// Reminders are replanned on refresh: from the saved settings and the check-in history, exactly
// once per day, never for a done or past time, and cleared when switched off.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';

import '../checkin_reminders_test.dart' show FakePort;
import '../twin/store_and_checkin_test.dart' show responseFor;
import 'daily_checkin_test.dart' show profile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());

  late FakePort port;
  late DateTime now;

  Future<TwinRepository> repoOn({bool remindersOn = true, List<CheckinEntry> history = const []}) async {
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => now,
      reminders: CheckinReminders(port),
    );
    await repo.saveConversationProfile(profile);
    if (remindersOn) {
      await repo.saveCheckinSettings(await repo.reminders!.accept(repo.checkinSettings, localNow: now, history: const []));
    }
    for (final h in history) {
      await repo.applyCheckin({
        ...responseFor('checkin-daily-start'),
        'complete': true,
        'state': {
          'kind': h.kind,
          'phase': 'ready',
          'questions': ['wellbeing'],
          'current_field': null,
          'confirmed': {'wellbeing': 'okay'},
        },
      }, localDate: h.date);
    }
    return repo;
  }

  Future<void> resume(WidgetTester t, TwinRepository repo) async {
    await t.pumpWidget(
      MaterialApp(
        home: ResumeRefresh(repository: repo, now: () => now, child: const Text('home')),
      ),
    );
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    await t.pump();
  }

  setUp(() {
    port = FakePort();
    now = DateTime(2026, 10, 28, 9);
  });

  test('refresh() replans from the saved settings: one reminder per day, the last says the pause line', () async {
    final repo = await repoOn();
    port.scheduled.clear();
    repo.refresh();
    await Future<void>.delayed(Duration.zero);
    final days = port.scheduled.map((s) => s.$1).toList();
    expect(days.toSet(), hasLength(days.length), reason: 'a day is planned once');
    expect(days, hasLength(reminderDays));
    expect(port.scheduled.last.$3, endsWith(reminderPauseLine)); // the weekly one may share it
    expect(port.scheduled.where((s) => s.$3 == reminderPauseLine), hasLength(1));
  });

  test('a check-in already done today means no reminder for today after refresh', () async {
    final repo = await repoOn(history: [const CheckinEntry(kind: 'quick', date: '2026-10-28', answers: {})]);
    repo.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(port.scheduled.map((s) => s.$2), isNot(contains(DateTime(2026, 10, 28, 10))));
    expect(port.scheduled.first.$2, DateTime(2026, 10, 29, 10));
  });

  test('a weekly check-in today does not cancel today\'s daily reminder', () async {
    final repo = await repoOn(history: [const CheckinEntry(kind: 'weekly', date: '2026-10-28', answers: {})]);
    repo.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(port.scheduled.first.$2, DateTime(2026, 10, 28, 10));
  });

  test('a reminder time that already passed today is not planned', () async {
    now = DateTime(2026, 10, 28, 10, 30);
    final repo = await repoOn();
    repo.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(port.scheduled.first.$2, DateTime(2026, 10, 29, 10));
  });

  test('switched off: refresh clears everything the phone still holds and plans nothing', () async {
    final repo = await repoOn();
    expect(port.scheduled, isNotEmpty);
    await repo.saveCheckinSettings(repo.reminders!.decline(const CheckinSettings(remindersOn: false, reminderOffered: true)));
    repo.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(port.scheduled, isEmpty);
  });

  test('a notification port that throws never breaks refresh', () async {
    final broken = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => now,
      reminders: CheckinReminders(_ThrowingPort()),
    );
    await broken.saveConversationProfile(profile);
    await broken.saveCheckinSettings(const CheckinSettings(remindersOn: true, reminderOffered: true));
    expect(() => broken.refresh(), returnsNormally);
    expect(await broken.replanReminders(), isEmpty);
  });

  testWidgets('resume plans the week once, not twice', (t) async {
    final repo = await repoOn();
    now = DateTime(2026, 10, 29, 8);
    await resume(t, repo);
    await t.pumpAndSettle();
    final ids = port.scheduled.map((s) => s.$1).toList();
    expect(ids.toSet(), hasLength(ids.length), reason: 'ResumeRefresh and refresh() both replan; days must not double up: $ids');
    expect(port.scheduled.where((s) => s.$3.endsWith(reminderPauseLine)), hasLength(1), reason: 'one pause line, on the last day');
    expect(port.scheduled.last.$3, endsWith(reminderPauseLine)); // the weekly one may share it
  });

  testWidgets('resume the same day after checking in: today stays unplanned', (t) async {
    final repo = await repoOn(history: [const CheckinEntry(kind: 'daily', date: '2026-10-28', answers: {})]);
    await resume(t, repo);
    await t.pumpAndSettle();
    expect(port.scheduled.map((s) => s.$2), isNot(contains(DateTime(2026, 10, 28, 10))));
  });
}

class _ThrowingPort implements NotificationPort {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleAt({
    required int id,
    required DateTime localWallTime,
    required String title,
    required String body,
    String? payload,
  }) async => throw StateError('no notifications');
  @override
  Future<void> cancelAll() async => throw StateError('no notifications');
}
