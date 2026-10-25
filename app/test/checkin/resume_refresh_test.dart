import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';

import '../checkin_reminders_test.dart' show FakePort;
import 'daily_checkin_test.dart' show profile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());

  testWidgets('coming back to the app refreshes the forecast and plans the reminders again', (t) async {
    var now = DateTime(2026, 10, 28, 9);
    final port = FakePort();
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => now,
      reminders: CheckinReminders(port),
    );
    await repo.saveConversationProfile(profile);
    await repo.saveCheckinSettings(
      await repo.reminders!.accept(repo.checkinSettings, localNow: now, history: const []),
    );
    var notified = 0;
    repo.addListener(() => notified++);
    await t.pumpWidget(
      MaterialApp(
        home: ResumeRefresh(repository: repo, now: () => now, child: const Text('home')),
      ),
    );
    final clearsBefore = port.clears;

    // Not resumed: nothing happens.
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(notified, 0);

    // A new day starts while the app was away.
    now = DateTime(2026, 10, 29, 8);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(notified, greaterThan(0), reason: 'the forecast was recomputed');
    expect(port.clears, greaterThan(clearsBefore), reason: 'reminders were planned again');
    expect(port.scheduled.first.$2, DateTime(2026, 10, 29, 10), reason: 'planned from the new day');
  });

  testWidgets('with reminders off, resuming only refreshes the forecast', (t) async {
    final port = FakePort();
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => DateTime(2026, 10, 28, 9),
      reminders: CheckinReminders(port),
    );
    await repo.saveConversationProfile(profile);
    await t.pumpWidget(
      MaterialApp(
        home: ResumeRefresh(repository: repo, child: const Text('home')),
      ),
    );
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(port.scheduled, isEmpty);
  });
}
