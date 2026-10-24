import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/ui/widgets/widgets.dart';

class Rig {
  final guide = FakeConversationGuide();
  final input = FakeSpeechInput();
  final output = FakeSpeechOutput();
  late final c = VoiceOnboardingController(guide: guide, input: input, output: output);
  Map<String, dynamic>? done;
  bool health = false;

  Future<void> pump(WidgetTester t, {double scale = 1}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            size: const Size(390, 844),
            disableAnimations: true,
          ),
          child: VoiceOnboardingScreen(controller: c, onDone: (p) => done = p, onUseHealth: () => health = true),
        ),
      ),
    );
  }
}

/// Answers both consent questions: voice, then the AI helper.
Future<void> choose(WidgetTester t, String voiceLabel, {bool aiHelper = false}) async {
  await t.ensureVisible(find.text(voiceLabel));
  await t.pumpAndSettle();
  await t.tap(find.text(voiceLabel));
  await t.pumpAndSettle();
  await t.pump(const Duration(milliseconds: 700)); // the AI question ignores a second tap at first
  final second = aiHelper ? 'Yes, turn it on' : 'Not now';
  await t.ensureVisible(find.text(second));
  await t.pumpAndSettle();
  await t.tap(find.text(second));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a double tap on a voice answer does not also answer the AI-helper question', (t) async {
    for (final voice in ["Yes, I'll talk", "No, I'll type"]) {
      await t.pumpWidget(const SizedBox()); // a fresh screen each time
      final r = Rig();
      await r.pump(t);
      final at = t.getCenter(find.text(voice));
      await t.tapAt(at);
      await t.pump(const Duration(milliseconds: 60));
      expect(find.text('Let an AI helper read hard answers?'), findsOneWidget);
      await t.tapAt(at); // lands on "Yes, turn it on" or "Not now"
      await t.pumpAndSettle();
      expect(find.text('Let an AI helper read hard answers?'), findsOneWidget, reason: voice);
      expect(r.guide.calls, isEmpty);
      expect(r.c.aiHelper, isFalse);
      await t.pump(const Duration(milliseconds: 700));
      final notNow = t.getCenter(find.text('Not now'));
      await t.tapAt(notNow);
      await t.pump(const Duration(milliseconds: 60));
      await t.pumpAndSettle();
      expect(r.guide.calls.single['action'], 'start');
      expect(r.c.aiHelper, isFalse);
      // The first question's Health chip must not catch a second tap meant for "Not now".
      if (find.text('Use my Apple Health').hitTestable().evaluate().isNotEmpty) {
        await t.tapAt(t.getCenter(find.text('Use my Apple Health')));
        await t.pumpAndSettle();
        expect(r.health, isFalse, reason: 'a second tap opened the Health import');
      }
    }
  });

  testWidgets('a double tap on Skip or Go back acts once, not also on the next question', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "No, I'll type");
    await t.pump(const Duration(milliseconds: 700));
    final skip = t.getCenter(find.text('Skip this question'));
    await t.tapAt(skip);
    await t.pump(const Duration(milliseconds: 60)); // the next question is already there
    await t.tapAt(skip);
    await t.pumpAndSettle();
    expect(r.guide.calls.where((c) => c['action'] == 'skip'), hasLength(1));
    await t.pump(const Duration(milliseconds: 700));
    await t.tapAt(skip);
    await t.pumpAndSettle();
    expect(r.guide.calls.where((c) => c['action'] == 'skip'), hasLength(2));
  });

  testWidgets('consent explains Cartesia and offers Yes / No, I\'ll type; nothing starts before', (t) async {
    final r = Rig();
    await r.pump(t);
    expect(
      find.text(
        'You can talk to me, or type. While you talk, your voice is sent to Cartesia, '
        'a speech service, to turn it into words.',
      ),
      findsOneWidget,
    );
    // Honest copy: Cartesia's retention is not verified, so no promise about recordings.
    expect(find.textContaining('recordings'), findsNothing);
    expect(find.textContaining('hold the Talk button'), findsNothing);
    expect(r.guide.calls, isEmpty);
    expect(r.output.spoken, isEmpty);
    for (final label in ["Yes, I'll talk", "No, I'll type"]) {
      expect(
        t
            .getSize(
              find.ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate((w) => w is LipButton || w is LinkButton),
              ),
            )
            .height,
        greaterThanOrEqualTo(72),
      );
    }
  });

  testWidgets('Type instead on consent starts the same conversation by typing', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "No, I'll type");
    expect(find.text('How old are you?'), findsOneWidget);
    expect(find.text('Tap to talk'), findsNothing);
    expect(r.output.spoken, isEmpty);
    await t.pump(const Duration(milliseconds: 700)); // the first question's Health link ignores a second tap at first
    await t.tap(find.text('Use my Apple Health'));
    expect(r.health, true);
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No, change it'), findsOneWidget);
  });

  testWidgets('Yes consent shows caption, speaks it, and tap-to-talk works', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "Yes, I'll talk");
    expect(find.text('How old are you?'), findsOneWidget);
    expect(r.output.spoken, ['How old are you?']);
    expect(find.text('Hear it again'), findsOneWidget);
    expect(find.text('Tap to talk'), findsOneWidget);

    r.input.captions = ['I am 70'];
    await t.tap(find.text('Tap to talk')); // quick tap = start
    await t.pumpAndSettle();
    expect(find.text('Hearing:'), findsOneWidget);
    expect(find.text('I am 70'), findsOneWidget);
    expect(find.text('Listening…'), findsOneWidget);
    expect(find.text('tap when done'), findsOneWidget);
    await t.tap(find.byType(TalkButton)); // second tap = stop
    await t.pumpAndSettle();
    expect(r.guide.calls.last['text'], 'I am 70');
    expect(find.text('Yes'), findsOneWidget);

    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    await t.tap(find.text('Continue'));
    expect(r.done, {'age': 70});
  });

  testWidgets('holding the button sends when let go', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "Yes, I'll talk");
    final g = await t.startGesture(t.getCenter(find.byType(TalkButton)));
    await t.pump();
    expect(r.c.phase, VoicePhase.listening);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
    await g.up();
    await t.pumpAndSettle();
    expect(r.input.finishes, 1);
    expect(find.text('Yes'), findsOneWidget);
  });

  testWidgets('mic denied: plain message stays, typing box appears', (t) async {
    final r = Rig();
    r.input.startError = const MicDeniedException();
    await r.pump(t);
    await choose(t, "Yes, I'll talk");
    await t.tap(find.text('Tap to talk'));
    await t.pumpAndSettle();
    expect(find.textContaining('open Settings'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
    expect(find.textContaining('open Settings'), findsOneWidget); // never auto-dismissed
  });

  testWidgets('empty transcript message and large text scale do not overflow', (t) async {
    final r = Rig();
    r.input.transcript = '';
    await r.pump(t, scale: 2.0);
    await choose(t, "Yes, I'll talk");
    await t.ensureVisible(find.text('Tap to talk'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tap to talk'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byType(TalkButton));
    await t.pumpAndSettle();
    await t.tap(find.byType(TalkButton));
    await t.pumpAndSettle();
    expect(find.text(emptyTranscriptNotice), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('app starts on the Room; Talk opens the voice screen and Apple Health import', (t) async {
    final r = Rig();
    await t.pumpWidget(LifeTwinApp(controller: r.c));
    expect(find.byType(RoomScreen), findsOneWidget);
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    expect(find.text('Talk with me?'), findsOneWidget);
    await choose(t, "No, I'll type");
    await t.pump(const Duration(milliseconds: 700)); // the first question's Health link ignores a second tap at first
    await t.ensureVisible(find.text('Use my Apple Health'));
    await t.pumpAndSettle();
    await t.tap(find.text('Use my Apple Health'));
    await t.pumpAndSettle();
    expect(find.text('Use Apple Health?'), findsOneWidget);
  });

  testWidgets('AI helper consent explains where answers go; yes turns it on for every turn', (t) async {
    final r = Rig();
    await r.pump(t);
    await t.tap(find.text("No, I'll type"));
    await t.pumpAndSettle();
    expect(find.text('Let an AI helper read hard answers?'), findsOneWidget);
    expect(
      find.text(
        "If I can't understand an answer, an AI service can read your words. "
        "It's off unless you say yes. You can change this in Settings.",
      ),
      findsOneWidget,
    );
    expect(r.guide.calls, isEmpty); // nothing starts until both questions are answered
    for (final label in ['Yes, turn it on', 'Not now']) {
      expect(
        t
            .getSize(
              find.ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate((w) => w is LipButton || w is LinkButton),
              ),
            )
            .height,
        greaterThanOrEqualTo(72),
      );
    }
    await t.pump(const Duration(milliseconds: 700)); // the AI question ignores a second tap at first
    await t.tap(find.text('Yes, turn it on'));
    await t.pumpAndSettle();
    expect(r.c.aiHelper, isTrue);
    expect(r.guide.calls.single['aiHelper'], isTrue);
    // The chip says so on the question screen, and Settings agrees.
    expect(find.text('AI helper: On'), findsOneWidget);
    await t.ensureVisible(find.text('Settings'));
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  });

  testWidgets('saying not now still lets the AI helper read a hard answer later, without retyping', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "No, I'll type");
    await t.enterText(find.byType(TextField), 'about five foot eight');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(find.text('Yes, let the AI helper read it'), findsOneWidget);
    await t.tap(find.text('Yes, let the AI helper read it'));
    await t.pumpAndSettle();
    expect(r.guide.calls.last['action'], 'reply');
    expect(r.guide.calls.last['text'], 'about five foot eight');
    expect(r.guide.calls.last['aiHelper'], isTrue);
    expect(find.textContaining('5 feet 8 inches'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
  });

  testWidgets('a microphone that never answers does not leave the typing box dead', (t) async {
    final r = Rig();
    final hang = HangingInput();
    final c = VoiceOnboardingController(guide: r.guide, input: hang, output: r.output);
    await t.pumpWidget(
      MaterialApp(
        home: VoiceOnboardingScreen(controller: c, onDone: (_) {}),
      ),
    );
    await c.answerConsent(true);
    await t.pump();
    unawaited(c.startTalk());
    await t.pump();
    unawaited(c.stopTalk()); // finish() never returns
    await t.pump();
    expect(c.phase, VoicePhase.interpreting);
    await t.pump(const Duration(seconds: 21));
    expect(c.phase, VoicePhase.idle);
    expect(c.notice, isNotNull);
    // Person switches to typing and sends.
    await c.setTyping(true);
    await t.pump();
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pump();
    expect(r.guide.calls.last['text'], '70');
  });

  testWidgets('a hung switch to typing while the microphone starts still ends in typing', (t) async {
    final r = Rig();
    final hang = HangingInput()..hangCancel = true;
    final c = VoiceOnboardingController(guide: r.guide, input: hang, output: r.output);
    await t.pumpWidget(
      MaterialApp(
        home: VoiceOnboardingScreen(controller: c, onDone: (_) {}),
      ),
    );
    await c.answerConsent(true);
    await c.startTalk();
    final f = c.setTyping(true);
    await t.pump(const Duration(seconds: 5));
    await f;
    expect(c.typing, isTrue);
    expect(c.phase, VoicePhase.idle);
    await t.pump();
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.enabled ?? true, isTrue);
    expect(field.readOnly, isFalse);
  });

  testWidgets('a server that never answers ends in a retry, not a dead screen', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "No, I'll type");
    r.guide.gate = Completer<void>();
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pump();
    expect(find.text('One moment…'), findsWidgets);
    await t.pump(const Duration(seconds: 31));
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('after typing there is a Talk instead; voice is asked about first, then Type instead returns', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "No, I'll type");
    expect(find.text('Tap to talk'), findsNothing);
    final talk = find.text('Talk instead');
    await t.ensureVisible(talk);
    expect(
      t
          .getSize(find.ancestor(of: talk, matching: find.byWidgetPredicate((w) => w is LipButton || w is LinkButton)))
          .height,
      greaterThanOrEqualTo(56),
    );
    await t.tap(talk);
    await t.pumpAndSettle();
    expect(find.text('Talk with me?'), findsOneWidget);
    expect(find.textContaining('sent to Cartesia'), findsOneWidget);
    await t.tap(find.text('Keep typing'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await t.ensureVisible(talk);
    await t.tap(talk);
    await t.pumpAndSettle();
    await t.tap(find.text("Yes, I'll talk"));
    await t.pumpAndSettle();
    expect(find.text('Tap to talk'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await t.ensureVisible(find.text('Type instead'));
    await t.tap(find.text('Type instead'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Talk instead'), findsOneWidget);
  });

  testWidgets('Change asks for the right answer and sends it as a correction', (t) async {
    final r = Rig();
    await r.pump(t);
    await choose(t, "No, I'll type");
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    final calls = r.guide.calls.length;
    await t.tap(find.text('No, change it'));
    await t.pumpAndSettle();
    expect(r.guide.calls.length, calls); // nothing sent yet
    expect(find.text('Okay. What is the right answer?'), findsOneWidget);
    await t.enterText(find.byType(TextField), '71');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(r.guide.calls.last['action'], 'correct');
    expect(r.guide.calls.last['text'], '71');
  });

  testWidgets('Hide keyboard appears with the keyboard, is big, and unfocuses the field; the return key sends', (
    t,
  ) async {
    final r = Rig();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: VoiceOnboardingScreen(controller: r.c, onDone: (_) {}),
      ),
    );
    await choose(t, "No, I'll type");
    expect(find.text('Hide keyboard'), findsNothing);
    await t.showKeyboard(find.byType(TextField));
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(t.view.resetViewInsets);
    await t.pump();
    final hide = find.text('Hide keyboard');
    expect(hide, findsOneWidget);
    expect(
      t
          .getSize(find.ancestor(of: hide, matching: find.byWidgetPredicate((w) => w is LipButton || w is LinkButton)))
          .height,
      greaterThanOrEqualTo(72),
    );
    await t.ensureVisible(hide);
    await t.tap(hide);
    await t.pump();
    expect(
      FocusManager.instance.primaryFocus?.hasPrimaryFocus == true &&
          FocusManager.instance.primaryFocus?.context?.widget is EditableText,
      isFalse,
    );
    // Tapping empty space also unfocuses.
    await t.showKeyboard(find.byType(TextField));
    await t.tapAt(const Offset(40, 150)); // the window, beside the twin
    await t.pump();
    expect(FocusManager.instance.primaryFocus?.context?.widget is EditableText, isFalse);
    // The keyboard's own send key still sends.
    await t.enterText(find.byType(TextField), '70');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    expect(r.guide.calls.last['text'], '70');
  });
  group('quick answers', () {
    const cases = {
      'sex': [('Female', 'female'), ('Male', 'male')],
      'diabetes': [('Yes', 'yes'), ('No', 'no'), ('Not sure', "I don't know")],
      'smoking_status': [
        ('I smoke now', 'I smoke now'),
        ('I used to smoke', 'I used to smoke'),
        ('I never smoked', 'I have never smoked'),
      ],
    };

    Future<(FieldGuide, VoiceOnboardingController, FakeSpeechOutput)> open(
      WidgetTester t,
      String field, {
      double scale = 1,
      bool hold = false,
    }) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final guide = FieldGuide(field);
      final output = FakeSpeechOutput()..holdSpeech = hold;
      final c = VoiceOnboardingController(guide: guide, input: FakeSpeechInput(), output: output);
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(scale),
              size: const Size(390, 844),
              disableAnimations: true,
            ),
            child: VoiceOnboardingScreen(controller: c, onDone: (_) {}),
          ),
        ),
      );
      for (final l in ["Yes, I'll talk", 'Not now']) {
        await t.ensureVisible(find.text(l));
        await t.pumpAndSettle();
        await t.tap(find.text(l));
        await t.pumpAndSettle();
        await t.pump(const Duration(milliseconds: 700)); // the AI question ignores a second tap at first
      }
      if (hold) {
        await t.pump();
        await t.pump();
      } else {
        await t.pumpAndSettle();
      }
      return (guide, c, output);
    }

    for (final e in cases.entries) {
      testWidgets('${e.key}: each button sends its words, then the read-back appears', (t) async {
        for (final (label, say) in e.value) {
          final (guide, c, _) = await open(t, e.key);
          await t.tap(quickButton(label));
          await t.pumpAndSettle();
          expect(guide.calls.last, {'action': 'reply', 'text': say});
          expect(c.confirming, isTrue);
          expect(find.text('No, change it'), findsOneWidget);
          expect(quickButton(label), findsNothing);
          await t.pumpWidget(const SizedBox());
        }
      });

      testWidgets('${e.key}: buttons are tall and sit two per row at 390 wide', (t) async {
        await open(t, e.key);
        final rects = [for (final (label, _) in e.value) t.getRect(quickButton(label))];
        for (final r in rects) {
          expect(r.height, greaterThanOrEqualTo(72));
        }
        expect(rects[0].top, rects[1].top);
        expect(rects[0].width, lessThan(195));
        expect(t.takeException(), isNull);
      });

      testWidgets('${e.key}: no overflow at text scale 2.0, buttons stack', (t) async {
        await open(t, e.key, scale: 2.0);
        for (final (label, _) in e.value) {
          await t.ensureVisible(quickButton(label));
        }
        final first = t.getRect(quickButton(e.value[0].$1));
        final second = t.getRect(quickButton(e.value[1].$1));
        expect(second.top, greaterThan(first.top));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('no buttons for other fields', (t) async {
      await open(t, 'age');
      for (final l in ['Female', 'Male', 'Not sure', 'I smoke now']) {
        expect(find.text(l), findsNothing);
      }
      expect(find.text('Tap to talk'), findsOneWidget);
    });

    testWidgets('no buttons while confirming, or while correcting', (t) async {
      final (_, c, _) = await open(t, 'sex');
      await t.tap(find.text('Male'));
      await t.pumpAndSettle();
      expect(find.text('Female'), findsNothing);
      await t.tap(find.text('No, change it'));
      await t.pumpAndSettle();
      expect(c.correcting, isTrue);
      expect(find.text('Female'), findsNothing);
      expect(find.text('Okay. What is the right answer?'), findsOneWidget);
    });

    testWidgets('tapping while the mascot speaks stops the speech first', (t) async {
      final (guide, c, output) = await open(t, 'sex', hold: true);
      expect(c.phase, VoicePhase.speaking);
      output.holdSpeech = false;
      await t.tap(find.text('Female'));
      await t.pumpAndSettle();
      expect(output.stops, 1);
      expect(guide.calls.last['text'], 'female');
    });

    testWidgets('tapping while listening cancels the recording, then sends', (t) async {
      final (guide, c, _) = await open(t, 'sex');
      await t.tap(find.text('Tap to talk'));
      await t.pumpAndSettle();
      expect(c.phase, VoicePhase.listening);
      await t.tap(find.text('Male'));
      await t.pumpAndSettle();
      expect(guide.calls.last['text'], 'male');
      expect(guide.calls.where((x) => x['action'] == 'reply').length, 1);
    });

    testWidgets('buttons are disabled while busy', (t) async {
      final (guide, _, _) = await open(t, 'sex');
      guide.hold = Completer<void>();
      await t.tap(find.text('Female'));
      await t.pump();
      final b = t.widget<LipButton>(quickButton('Male'));
      expect(b.onTap, isNull);
      guide.hold!.complete();
      await t.pumpAndSettle();
    });
  });
}

/// A quick answer: a cream (secondary) button, unlike the read-back's mint Yes.
Finder quickButton(String label) =>
    find.byWidgetPredicate((w) => w is LipButton && w.label == label && w.kind == LipKind.secondary);

class FieldGuide implements ConversationGuide {
  FieldGuide(this.field);
  final String field;
  final calls = <Map<String, dynamic>>[];
  Completer<void>? hold;

  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, num>? values,
    bool aiHelper = false,
  }) async {
    calls.add({'action': action, 'text': ?text});
    if (hold != null) await hold!.future;
    final asking = action == 'start';
    return GuideTurn(
      state: {'phase': asking ? 'asking' : 'confirming', 'current_field': asking ? field : null},
      message: asking ? 'Question about $field?' : 'Is that right?',
      complete: false,
    );
  }
}

class HangingInput extends FakeSpeechInput {
  bool hangCancel = false;
  @override
  Future<String> finish() => Completer<String>().future;
  @override
  Future<void> cancel() => hangCancel ? Completer<void>().future : super.cancel();
}
