import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/change_chat.dart';
import 'package:lifesim/experiment/answers.dart';
import 'package:lifesim/checkin/consent_screens.dart';
import 'package:lifesim/checkin/consents.dart';
import 'package:lifesim/checkin/my_data_screen.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';

import '../support/app_fonts.dart';
import '../checkin_reminders_test.dart' show FakePort;
import '../support/fake_change_client.dart';
import 'daily_checkin_test.dart' show profile;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<TwinRepository> repoWith(Map<String, dynamic>? p, {FakePort? port}) async {
    final repo = TwinRepository(
      reminders: port == null ? null : CheckinReminders(port),
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => DateTime(2026, 10, 28),
    );
    if (p != null) await repo.saveConversationProfile(p);
    return repo;
  }

  Future<void> pump(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: lifeTwinTheme(), home: home));
    await t.pump();
  }

  Iterable<String> texts(WidgetTester t) => t
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
      .where((s) => s.isNotEmpty);

  test('every model input the app can ask about maps to a ChangeField, including sitting', () {
    for (final input in [
      'age',
      'sex_nhanes',
      'bmi',
      'sleep_hours',
      'vigorous_recreation_min_week',
      'moderate_recreation_min_week',
      'sedentary_min_day',
      'smoking_status',
      'diabetes_diagnosed',
      'hypertension_diagnosed',
      'general_health',
    ]) {
      expect(changeFields, contains(Answers.changeField(input)), reason: input);
    }
    expect(Answers.changeField('sedentary_min_day'), 'sedentary_min_day');
  });

  group('change through Mochi (Z-10, Z-30, Z-31, Z-32)', () {
    testWidgets('saves only after "Yes, save"; the sheet stays open; nothing before the yes', (t) async {
      final repo = await repoWith(profile);
      final client = FakeChangeClient();
      final c = ChangeChatController(client: client, repository: repo, field: 'sleep_hours');
      addTearDown(c.dispose);
      var closed = 0;
      await pump(t, ChangeChatScreen(controller: c, appearance: const TwinAppearance(), onClose: () => closed++));
      await t.pumpAndSettle();
      expect(client.starts.single.field, 'sleep_hours');
      expect(find.text('Update with Mochi'), findsOneWidget);
      await t.tap(find.byIcon(Icons.keyboard_alt_outlined));
      await t.pump();
      await t.enterText(find.byType(TextField), 'about 6 hours now');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pumpAndSettle();
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text('Yes, save'), findsOneWidget);
      expect(repo.profile['sleep_hours'], 7, reason: 'nothing is saved before the yes');
      await t.tap(find.text('Yes, save'));
      await t.pumpAndSettle();
      expect(repo.profile['sleep_hours'], 6);
      expect(find.text('Saved.'), findsWidgets);
      expect(closed, 0, reason: 'the sheet stays open after complete');
    });

    testWidgets('closing before the yes cancels: the saved answer is unchanged', (t) async {
      final repo = await repoWith(profile);
      final client = FakeChangeClient();
      final c = ChangeChatController(client: client, repository: repo);
      addTearDown(c.dispose);
      var closed = 0;
      await pump(t, ChangeChatScreen(controller: c, appearance: const TwinAppearance(), onClose: () => closed++));
      await t.pumpAndSettle();
      expect(find.text('What would you like to update?'), findsWidgets);
      await t.tap(find.byIcon(Icons.chevron_left_rounded));
      await t.pumpAndSettle();
      expect(client.turns, ['cancel']);
      expect(closed, 1);
      expect(repo.profile['sleep_hours'], 7);
    });

    testWidgets('no habit note without memory consent; with it, the note is kept', (t) async {
      final repo = await repoWith(profile);
      final c = ChangeChatController(client: FakeChangeClient(), repository: repo, field: 'sleep_hours');
      addTearDown(c.dispose);
      await c.start();
      await c.reply('6 hours');
      await c.confirm();
      expect(repo.store.habitNotes, isEmpty);
      await repo.applyMemoryConsent(true);
      final c2 = ChangeChatController(client: FakeChangeClient(), repository: repo, field: 'sleep_hours');
      addTearDown(c2.dispose);
      await c2.start();
      await c2.reply('6 hours');
      await c2.confirm();
      expect(repo.store.habitNotes.single['note'], {'field': 'sleep_hours', 'text': 'walks after dinner'});
    });

    testWidgets('an emergency pauses: nothing saved, Call 911 is a tapped tel: link, Continue resumes', (t) async {
      final repo = await repoWith(profile);
      final client = FakeChangeClient();
      final c = ChangeChatController(client: client, repository: repo, field: 'sleep_hours');
      addTearDown(c.dispose);
      final opened = <Uri>[];
      await pump(
        t,
        ChangeChatScreen(
          controller: c,
          appearance: const TwinAppearance(),
          onClose: () {},
          open: (u) async => opened.add(u),
        ),
      );
      await t.pumpAndSettle();
      await c.reply('I do not feel safe right now');
      await t.pumpAndSettle();
      expect(find.text('If you need help right now, please call 911.'), findsOneWidget);
      expect(opened, isEmpty);
      expect(repo.profile['sleep_hours'], 7);
      await t.tap(find.text('Call 911'));
      expect(opened.single.toString(), 'tel:911');
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(client.turns.last, 'resume');
    });
  });

  group('the AI consents are separate, dynamic and never state retention', () {
    test('the provider name comes from /api/capabilities and is never hard-coded', () {
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final text = f.readAsStringSync();
        for (final name in ['Muse by Meta', 'Claude by Anthropic']) {
          expect(text.contains(name), isFalse, reason: '${f.path} names $name');
        }
      }
      final p = AiProvider.fromCapabilities({
        'personalize': {'provider': 'muse', 'display_name': 'Name From The Server', 'configured': true},
      });
      expect((p!.id, p.displayName, p.configured), ('muse', 'Name From The Server', true));
      expect(
        AiProvider.fromCapabilities({
          'personalize': {'provider': 'x'},
        }),
        isNull,
      );
      expect(AiProvider.fromCapabilities(null), isNull);
    });

    testWidgets('consent screen: the name is dynamic, Yes and No equal, no retention promise, Back = No', (t) async {
      for (final name in ['Provider One', 'Another Provider']) {
        final answers = <bool>[];
        await pump(
          t,
          OutsideAiConsentScreen(
            provider: AiProvider(id: 'p', displayName: name, configured: true),
            onChoose: answers.add,
          ),
        );
        expect(find.text('With $name'), findsOneWidget);
        expect(find.text('Personal suggestions?'), findsOneWidget);
        final no = t.getSize(find.ancestor(of: find.text('No thanks'), matching: find.byType(ConstrainedBox)).first);
        final yes = t.getSize(find.ancestor(of: find.text('Yes, share'), matching: find.byType(ConstrainedBox)).first);
        expect(no, yes);
        expect(answers, isEmpty, reason: 'nothing is pre-selected');
        // Nothing about the provider's own retention or training.
        for (final s in texts(t)) {
          expect(
            RegExp(r'retain|retention|train|keeps|deleted|never stored', caseSensitive: false).hasMatch(s),
            isFalse,
            reason: s,
          );
        }
        await t.tap(find.text('What’s sent?'));
        await t.pumpAndSettle();
        expect(find.text('Never your name or contact details.'), findsOneWidget);
        expect(find.text('Apple Health numbers, like sleep and activity.'), findsOneWidget);
        await t.tap(find.text('Close'));
        await t.pumpAndSettle();
        await t.tap(find.text('No thanks'));
        expect(answers, [false]);
      }
    });

    testWidgets('re-consent when the provider changes: a new id has no answer, so it asks again', (t) async {
      final repo = await repoWith(profile);
      final store = ConsentStore(repo);
      const one = AiProvider(id: 'a', displayName: 'Provider A', configured: true);
      const two = AiProvider(id: 'b', displayName: 'Provider B', configured: true);
      expect(store.needsAnswer(one), isTrue);
      expect(store.mayShare(one), isFalse, reason: 'nothing is sent before a yes');
      await store.setOutsideAi('a', true);
      expect(store.mayShare(one), isTrue);
      expect(store.needsAnswer(two), isTrue);
      expect(store.mayShare(two), isFalse);
      // Not configured: never asked, never sent.
      const off = AiProvider(id: 'c', displayName: 'C', configured: false);
      expect(store.needsAnswer(off), isFalse);
      expect(store.mayShare(off), isFalse);
      expect(store.needsAnswer(null), isFalse);
      final answers = <bool>[];
      await pump(t, OutsideAiConsentScreen(provider: two, reconsent: true, onChoose: answers.add));
      expect(find.text('A new AI provider'), findsOneWidget);
      expect(find.textContaining('We now use Provider B'), findsOneWidget);
    });

    testWidgets('three consents stay separate: AI helper, personal suggestions, and memory', (t) async {
      final repo = await repoWith(profile);
      final store = ConsentStore(repo);
      const p = AiProvider(id: 'p', displayName: 'The Provider', configured: true);
      var asked = 0;
      await pump(t, AiSettingsScreen(consents: store, provider: p, onAskOutsideAi: () => asked++, onBack: () {}));
      expect(find.textContaining('Sends to The Provider'), findsOneWidget);
      expect(find.textContaining('With The Provider'), findsOneWidget);
      // Turning the helper on touches nothing else.
      await t.tap(find.text('AI helper'));
      await t.pump();
      expect(store.aiHelper, isTrue);
      expect(store.outsideAiFor('p'), isNull);
      expect(repo.store.memoryConsent, isFalse);
      // Personal suggestions asks first: the toggle does not flip by itself.
      await t.tap(find.text('Personal suggestions'));
      await t.pump();
      expect(asked, 1);
      expect(store.outsideAiFor('p'), isNull);
      await store.setOutsideAi('p', true);
      await t.pump();
      await t.tap(find.text('Personal suggestions'));
      await t.pump();
      expect(store.outsideAiFor('p'), isFalse);
      expect(store.aiHelper, isTrue);
    });

    testWidgets('memory opt-in: equal choices, nothing pre-selected, either way Mochi helps', (t) async {
      final answers = <bool>[];
      await pump(t, MemoryConsentScreen(appearance: const TwinAppearance(), onChoose: answers.add, onBack: () {}));
      expect(find.text('Mochi’s notebook'), findsOneWidget);
      expect(find.text('Either way, Mochi still helps.'), findsOneWidget);
      expect(answers, isEmpty);
      await t.tap(find.text('Yes, remember'));
      expect(answers, [true]);
      // The storage sentence is behind a tap, as required.
      await t.tap(find.text('Saved on this phone'));
      await t.pumpAndSettle();
      expect(find.text(serverSentence), findsOneWidget);
    });
  });

  group('My data and Delete my data (Z-21, Z-22, Z-36, Z-23)', () {
    testWidgets('two confirms; Keep changes nothing; Yes, delete clears answers, consents and reminders', (t) async {
      final port = FakePort();
      final repo = await repoWith(profile, port: port);
      await repo.applyMemoryConsent(true);
      await repo.addHabitNote({'topic': 'walks', 'text': 'x'});
      final consents = ConsentStore(repo);
      await consents.setOutsideAi('p', true);
      consents.setAiHelper(true);
      await repo.saveCheckinSettings(
        await repo.reminders!.accept(repo.checkinSettings, localNow: DateTime(2026, 10, 28), history: const []),
      );
      expect(repo.checkinSettings.remindersOn, isTrue);
      final clearsBefore = port.clears;
      var deleted = 0;
      await pump(
        t,
        MyDataScreen(
          repository: repo,
          consents: consents,
          onBack: () {},
          onAiPrivacy: () {},
          onDeleted: () => deleted++,
        ),
      );
      expect(find.text('Saved on this phone'), findsWidgets);
      expect(find.text('1 note · read only'), findsOneWidget);
      // Step 1: keep.
      await t.ensureVisible(find.text('Delete my data'));
      await t.tap(find.text('Delete my data'));
      await t.pumpAndSettle();
      expect(find.text('Delete your data?'), findsOneWidget);
      await t.tap(find.text('Keep my data'));
      await t.pumpAndSettle();
      expect(repo.store.hasProfile, isTrue);
      expect(deleted, 0);
      // Step 1: delete, then step 2: keep.
      await t.tap(find.text('Delete my data'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete everything'));
      await t.pumpAndSettle();
      expect(find.text('Delete everything now?'), findsOneWidget);
      await t.tap(find.text('Keep my data'));
      await t.pumpAndSettle();
      expect(repo.store.hasProfile, isTrue);
      expect(consents.outsideAiFor('p'), isTrue);
      // Both confirms: gone.
      await t.tap(find.text('Delete my data'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete everything'));
      await t.pumpAndSettle();
      await t.tap(find.text('Yes, delete'));
      await t.pumpAndSettle();
      expect(deleted, 1);
      expect(repo.store.hasProfile, isFalse);
      expect(repo.store.habitNotes, isEmpty);
      expect(repo.store.memoryConsent, isFalse);
      expect(consents.outsideAiFor('p'), isNull);
      expect(consents.aiHelper, isFalse);
      expect(port.clears, greaterThan(clearsBefore), reason: 'the planned reminders are cancelled');
      expect(repo.checkinSettings.remindersOn, isFalse);
    });

    testWidgets('turning memory off with notes asks first and clears the notebook', (t) async {
      final repo = await repoWith(profile);
      await repo.applyMemoryConsent(true);
      await repo.addHabitNote({'topic': 'walks', 'text': 'x'});
      await pump(
        t,
        MyDataScreen(
          repository: repo,
          consents: ConsentStore(repo),
          onBack: () {},
          onAiPrivacy: () {},
          onDeleted: () {},
        ),
      );
      await t.tap(find.text('Mochi remembers'));
      await t.pumpAndSettle();
      expect(find.text('Turn off memory?'), findsOneWidget);
      await t.tap(find.text('Keep it on'));
      await t.pumpAndSettle();
      expect(repo.store.memoryConsent, isTrue);
      await t.tap(find.text('Mochi remembers'));
      await t.pumpAndSettle();
      await t.tap(find.text('Turn off and clear'));
      await t.pumpAndSettle();
      expect(repo.store.memoryConsent, isFalse);
      expect(repo.store.habitNotes, isEmpty);
    });

    testWidgets(
      'reminders: permission is asked in context, the first time one is turned on; the text carries no health details',
      (t) async {
        final port = FakePort();
        final repo = await repoWith(profile, port: port);
        await pump(t, ReminderSettingsScreen(repository: repo, onBack: () {}, now: () => DateTime(2026, 10, 28, 8)));
        expect(port.asks, 0);
        await t.tap(find.text('Check-in reminder'));
        await t.pumpAndSettle();
        expect(port.asks, 1);
        expect(repo.checkinSettings.remindersOn, isTrue);
        expect(port.scheduled, isNotEmpty);
        await t.tap(find.text('Evening 7:30'));
        await t.pumpAndSettle();
        expect(repo.checkinSettings.reminderHour, 19);
        for (final line in reminderLines) {
          expect(line, isNot(matches(RegExp(r'missed|blood|weight|health', caseSensitive: false))));
        }
        await t.tap(find.text('Check-in reminder'));
        await t.pumpAndSettle();
        expect(repo.checkinSettings.remindersOn, isFalse);
        // The phone says no: it stays off.
        port.allow = false;
        await t.tap(find.text('Check-in reminder'));
        await t.pumpAndSettle();
        expect(repo.checkinSettings.remindersOn, isFalse);
      },
    );
  });
}
