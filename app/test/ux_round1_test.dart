// UX round 1 for older adults: one test group per audit finding.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/ui/widgets/widgets.dart';

const fields = [
  'age',
  'sex',
  'height_cm',
  'weight_kg',
  'sleep_hours',
  'exercise_minutes_weekly',
  'smoking_status',
  'alcohol_drinks_weekly',
  'diabetes',
  'systolic_bp',
  'diastolic_bp',
];

/// A server stand-in that walks through the fields in order, keeps skipped
/// fields, and understands "go back", like the real one.
class StepGuide implements ConversationGuide {
  StepGuide({this.message});

  /// Replaces every question's words (to test long lines).
  final String? message;
  final calls = <Map<String, dynamic>>[];
  Completer<void>? gate;

  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    bool aiHelper = false,
    String? importSource,
  }) async {
    calls.add({'action': action, 'text': ?text});
    if (gate != null) await gate!.future;
    final confirmed = Map<String, dynamic>.from((state?['confirmed_profile'] as Map?) ?? const {});
    final skipped = List<String>.from((state?['skipped_fields'] as List?) ?? const []);
    final pending = Map<String, dynamic>.from((state?['pending_profile'] as Map?) ?? const {});
    final current = state?['current_field'] as String?;
    String next() => fields.firstWhere((f) => !confirmed.containsKey(f) && !skipped.contains(f), orElse: () => '');
    GuideTurn ask(String field, [String? lead]) =>
        _turn('asking', '${lead ?? ''}Question about $field?', field, confirmed, skipped, {});
    switch (action) {
      case 'start':
        return ask('age');
      case 'skip':
        skipped.add(current!);
        return ask(next(), 'No problem. ');
      case 'confirm':
        confirmed.addAll(pending);
        return ask(next(), 'Got it. ');
      case 'reply' when text == 'go back':
        final i = fields.indexOf(current!);
        return ask(fields[i == 0 ? 0 : i - 1], "Okay, let's go back. ");
      case 'reply' when (state?['phase'] == 'confirming') && text == 'yes':
        confirmed.addAll(pending);
        return ask(next(), 'Got it. ');
      default:
        return _turn('confirming', 'I heard $text. Is that right?', current, confirmed, skipped, {current!: 1});
    }
  }

  GuideTurn _turn(
    String phase,
    String line,
    String? field,
    Map<String, dynamic> confirmed,
    List<String> skipped,
    Map<String, dynamic> pending,
  ) => GuideTurn(
    state: {
      'phase': phase,
      'current_field': field,
      'confirmed_profile': confirmed,
      'pending_profile': pending,
      'skipped_fields': skipped,
    },
    message: message ?? line,
    complete: false,
  );
}

/// A microphone whose words arrive while the test runs.
class LiveInput extends FakeSpeechInput {
  void Function(String)? say;
  @override
  Future<void> start(void Function(String text) onCaption) async {
    starts++;
    say = onCaption;
  }
}

class Rig {
  Rig({ConversationGuide? guide, SpeechInput? input}) : guide = guide ?? FakeConversationGuide() {
    this.input = input ?? FakeSpeechInput();
  }
  final ConversationGuide guide;
  late final SpeechInput input;
  final output = FakeSpeechOutput();
  late final c = VoiceOnboardingController(guide: guide, input: input, output: output);
  int settingsOpened = 0;
  int healthOpened = 0;

  FakeSpeechInput get fakeInput => input as FakeSpeechInput;
  List<Map<String, dynamic>> get calls =>
      guide is StepGuide ? (guide as StepGuide).calls : (guide as FakeConversationGuide).calls;

  Future<void> pump(
    WidgetTester t, {
    double scale = 1,
    bool reducedMotion = true,
    bool screenReader = false,
    bool health = true,
  }) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion,
              accessibleNavigation: screenReader,
            ),
            child: VoiceOnboardingScreen(
              controller: c,
              onDone: (_) {},
              onUseHealth: health ? () => healthOpened++ : null,
              onOpenSettings: () async => settingsOpened++,
            ),
          ),
        ),
      ),
    );
  }

  /// Answers both consent questions.
  Future<void> start(WidgetTester t, {required bool voice, bool settle = true}) async {
    for (final label in [voice ? "Yes, I'll talk" : "No, I'll type", 'Not now']) {
      await t.ensureVisible(find.text(label));
      await t.pumpAndSettle();
      await t.tap(find.text(label));
      if (settle) {
        await t.pumpAndSettle();
      } else {
        await t.pump();
        await t.pump();
      }
      await t.pump(const Duration(milliseconds: 700)); // the AI question ignores a second tap at first
    }
  }
}

/// The tappable control (a lip button or a text link) that shows [label].
Finder button(String label) => find
    .ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is LipButton || w is LinkButton))
    .first;

/// The Talk button's words. While listening they are two lines ("Listening…" over
/// "tap when done"), read here as one.
String talkLabel(WidgetTester t) => t
    .widgetList<Text>(find.descendant(of: find.byType(TalkButton), matching: find.byType(Text)))
    .map((w) => w.data)
    .join(' ');

/// The twin's pose in the window (one sprite on screen).
TwinPose twinPose(WidgetTester t) => t.widget<TwinSprite>(find.byType(TwinSprite)).pose;

/// The painted window's height: 250 at full size, 150 when it makes room.
double windowHeight(WidgetTester t) => t.getSize(find.byType(PlateWindow)).height;

Future<void> tapTalk(WidgetTester t) async {
  await t.ensureVisible(find.byType(TalkButton));
  await t.tap(find.byType(TalkButton));
  await t.pump();
  await t.pump();
}

/// Taps a button inside the settings sheet or the screen, scrolling to it first.
Future<void> tapText(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label).last);
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

bool fieldFocused(WidgetTester t) => t.state<EditableTextState>(find.byType(EditableText)).widget.focusNode.hasFocus;

void main() {
  group('1. read-back by voice', () {
    testWidgets('voice read-back shows Talk, Yes and "No, change it"; a spoken yes is sent as a reply', (t) async {
      final r = Rig();
      await r.pump(t);
      await r.start(t, voice: true);
      await tapTalk(t);
      await tapTalk(t);
      await t.pumpAndSettle();
      expect(r.c.confirming, isTrue);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No, change it'), findsOneWidget);
      expect(find.text('Change'), findsNothing);
      expect(find.byType(TalkButton), findsOneWidget);

      r.fakeInput.transcript = 'yes';
      await tapTalk(t);
      await tapTalk(t);
      await t.pumpAndSettle();
      // Sent as a reply (not a correction) so the server can hear "yes", "no" or a new value.
      expect(r.calls.last, containsPair('action', 'reply'));
      expect(r.calls.last, containsPair('text', 'yes'));
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('typed read-back has no Talk button', (t) async {
      final r = Rig();
      await r.pump(t);
      await r.start(t, voice: false);
      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      expect(find.text('No, change it'), findsOneWidget);
      expect(find.byType(TalkButton), findsNothing);
    });
  });

  group('2. skip', () {
    for (final voice in [true, false]) {
      testWidgets('a tall "Skip this question" sits under ${voice ? 'Talk' : 'Send'} and skips', (t) async {
        final r = Rig(guide: StepGuide());
        await r.pump(t);
        await r.start(t, voice: voice);
        final skip = button('Skip this question');
        expect(t.getSize(skip).height, greaterThanOrEqualTo(56));
        final above = voice ? find.byType(TalkButton) : button('Send');
        expect(t.getRect(skip).top, greaterThanOrEqualTo(t.getRect(above).bottom));
        await t.tap(skip);
        await t.pumpAndSettle();
        expect(r.calls.last['action'], 'skip');
        expect(find.textContaining('Question about sex'), findsOneWidget);
      });
    }

    testWidgets('hidden while an answer is being checked', (t) async {
      final r = Rig(guide: StepGuide());
      await r.pump(t);
      await r.start(t, voice: false);
      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      expect(r.c.confirming, isTrue);
      expect(find.text('Skip this question'), findsNothing);
    });
  });

  group('3. question text', () {
    final long = List.filled(14, 'This is a long question that needs a lot of room to read.').join(' ');

    testWidgets('a long line is not cut off: it scrolls while the controls stay pinned', (t) async {
      final r = Rig(guide: StepGuide(message: long));
      await r.pump(t);
      await r.start(t, voice: true);
      final talkBefore = t.getRect(find.byType(TalkButton));
      expect(talkBefore.bottom, lessThanOrEqualTo(844));
      // The whole line can be scrolled into view, and the controls do not move.
      final story = t.state<ScrollableState>(
        find.ancestor(of: find.text(long), matching: find.byType(Scrollable)).first,
      );
      expect(story.position.maxScrollExtent, greaterThan(0));
      story.position.jumpTo(story.position.maxScrollExtent);
      await t.pumpAndSettle();
      expect(t.getRect(find.byType(TalkButton)), talkBefore);
      final viewport = t.getRect(find.byWidget(story.widget));
      expect(viewport.bottom, lessThanOrEqualTo(talkBefore.top));
      expect(t.getRect(find.text(long)).bottom, lessThanOrEqualTo(viewport.bottom));
      expect(t.takeException(), isNull);
      // Lines over 80 characters use the smaller style.
      final style = t.widget<Text>(find.text(long)).style!;
      expect(style.fontSize, 20);
    });

    testWidgets('a short line keeps the large style', (t) async {
      final r = Rig(guide: StepGuide());
      await r.pump(t);
      await r.start(t, voice: false);
      final line = find.text('Question about age?');
      expect(t.widget<Text>(line).style!.fontSize, 26);
      // The question sits in the full-size window, beside the twin.
      expect(find.byType(TwinSprite), findsOneWidget);
      expect(windowHeight(t), greaterThanOrEqualTo(200));
      final window = t.getRect(find.byType(PlateWindow));
      expect(window.contains(t.getRect(line).center), isTrue);
    });

    for (final scale in [1.5, 2.0]) {
      testWidgets('at text scale $scale the window shrinks, the words go under it and nothing overflows', (t) async {
        final r = Rig(guide: StepGuide(message: long));
        await r.pump(t, scale: scale);
        await r.start(t, voice: false);
        // With large text the twin takes no room the words need.
        expect(find.byType(TwinSprite), findsOneWidget);
        expect(windowHeight(t), lessThanOrEqualTo(150));
        expect(t.getRect(find.byType(PlateWindow)).bottom, lessThanOrEqualTo(t.getRect(find.text(long)).top));
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('Send'));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('4. speaking', () {
    testWidgets('shows Speaking… and Stop; Talk says "Tap to answer"; Stop ends the speech', (t) async {
      final r = Rig();
      r.output.holdSpeech = true;
      await r.pump(t);
      await r.start(t, voice: true, settle: false);
      expect(r.c.phase, VoicePhase.speaking);
      expect(find.text('Speaking…'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Hear it again'), findsNothing);
      expect(talkLabel(t), 'Tap to answer');
      expect(t.getSize(button('Stop')).height, greaterThanOrEqualTo(56));
      await t.ensureVisible(find.text('Stop')); // the Apple Health button leaves the story less room
      await t.pump();
      await t.tap(find.text('Stop'));
      await t.pumpAndSettle();
      expect(r.output.stops, 1);
      expect(r.c.phase, VoicePhase.idle);
      expect(find.text('Speaking…'), findsNothing);
      expect(find.text('Hear it again'), findsOneWidget);
      expect(talkLabel(t), 'Talk or type');
    });
  });

  group('notices', () {
    testWidgets('very large text: a new turn shows its controls from the top (Yes not scrolled away)', (t) async {
      final r = Rig(guide: StepGuide());
      await r.pump(t, scale: 3);
      await r.start(t, voice: false);
      await t.enterText(find.byType(TextField), '70');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      // The person scrolled the controls down (to Skip, say), then sends.
      final controlsScroll = find
          .descendant(of: find.byType(SingleChildScrollView).last, matching: find.byType(Scrollable))
          .first;
      await t.drag(controlsScroll, const Offset(0, -600));
      await t.pumpAndSettle();
      expect(t.state<ScrollableState>(controlsScroll).position.pixels, greaterThan(0));
      await r.c.submitTyped('70');
      await t.pumpAndSettle();
      expect(r.c.confirming, isTrue);
      expect(find.text('Yes').hitTestable(), findsOneWidget);
      final yes = t.getRect(find.text('Yes'));
      final controls = t.getRect(find.byType(SingleChildScrollView).last);
      expect(yes.top, greaterThanOrEqualTo(controls.top));
    });

    testWidgets('large text: the end of Pip\'s line (the question) is in view on each new turn', (t) async {
      const line = "Hi, I'm your guide. You can talk or type, and you can skip any question. How old are you?";
      final r = Rig(guide: StepGuide(message: line));
      await r.pump(t, scale: 2);
      await r.start(t, voice: false);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      Rect visible() => t.getRect(find.byType(Scrollable).first);
      final text = find.textContaining('How old are you?');
      expect(t.getRect(text).bottom, lessThanOrEqualTo(visible().bottom + 0.5));
      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      expect(r.c.confirming, isTrue); // the read-back (StepGuide uses the same words)
      expect(t.getRect(text).bottom, lessThanOrEqualTo(visible().bottom + 0.5));
    });

    testWidgets('large text: a turn that arrives with the keyboard up is in view once it goes down', (t) async {
      const line = "Hi, I'm your guide. You can talk or type, and you can skip any question. How old are you?";
      final r = Rig(guide: StepGuide(message: line));
      await r.pump(t, scale: 2);
      await r.start(t, voice: false);
      t.view.viewInsets = const FakeViewPadding(bottom: 336); // the keyboard
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      t.view.resetViewInsets(); // read-back: no typing box, so the keyboard goes down
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      final end = t.getRect(find.textContaining('How old are you?')).bottom;
      expect(end, lessThanOrEqualTo(t.getRect(find.byType(Scrollable).first).bottom + 0.5));
    });

    testWidgets('typing: a new question\'s quick answers scroll into view', (t) async {
      final r = Rig(guide: StepGuide(message: 'Got it. What sex were you at birth: female or male?'));
      await r.pump(t);
      await r.start(t, voice: false);
      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      await t.tap(find.text('Yes'));
      await t.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      expect(r.c.state?['current_field'], 'sex');
      expect(find.text('Female').hitTestable(), findsOneWidget);
      expect(find.text('Male').hitTestable(), findsOneWidget);
    });

    testWidgets('a new notice scrolls into view with its button (mic denied, no network)', (t) async {
      final r = Rig();
      r.fakeInput.startError = const MicDeniedException();
      await r.pump(t);
      await r.start(t, voice: true);
      await tapTalk(t);
      await t.pumpAndSettle();
      // The always-there Home row leaves less room, so the notice's top may be scrolled
      // just out of view; its end and the Open Settings button must be on screen.
      expect(t.getRect(find.text(micDeniedNotice)).bottom, greaterThan(56));
      expect(find.text('Open Settings').hitTestable(), findsOneWidget);
      (r.guide as FakeConversationGuide).failNext = true;
      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      expect(find.text('Try again').hitTestable(), findsOneWidget);
    });
  });

  group('the "Allow microphone?" question', () {
    for (final allow in [true, false]) {
      testWidgets('waits as long as the person reads it, then ${allow ? 'listens' : 'says why not'}', (t) async {
        final r = Rig();
        r.fakeInput.permission = Completer<bool>();
        await r.pump(t);
        await r.start(t, voice: true);
        await tapTalk(t);
        await t.pump(const Duration(seconds: 25)); // well past the 10 s start limit
        expect(r.c.notice, isNull);
        expect(r.fakeInput.starts, 0);
        r.fakeInput.permission!.complete(allow);
        await t.pump();
        await t.pump();
        if (allow) {
          expect(r.c.phase, VoicePhase.listening);
          expect(r.fakeInput.starts, 1);
          await r.c.cancelTalk();
        } else {
          expect(r.c.notice, micDeniedNotice);
          expect(r.c.typing, isTrue);
        }
        await t.pumpAndSettle();
      });
    }
  });

  group('leaving the app', () {
    testWidgets('while listening closes the microphone and sends nothing; back, Talk works again', (t) async {
      final r = Rig();
      r.fakeInput.captions = ['I am'];
      await r.pump(t);
      await r.start(t, voice: true);
      await tapTalk(t);
      expect(r.c.phase, VoicePhase.listening);
      final sent = r.calls.length;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pumpAndSettle();
      expect(r.c.phase, VoicePhase.idle);
      expect(r.fakeInput.cancels, 1);
      expect(r.calls, hasLength(sent), reason: 'half-heard words must not be sent');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text('Talk or type'), findsOneWidget);
      await tapTalk(t);
      expect(r.c.phase, VoicePhase.listening);
      await r.c.cancelTalk(); // stops the listening clock before the test ends
      await t.pumpAndSettle();
    });

    testWidgets('while Pip speaks stops the speech', (t) async {
      final r = Rig();
      r.output.holdSpeech = true;
      await r.pump(t);
      await r.start(t, voice: true, settle: false);
      expect(r.c.phase, VoicePhase.speaking);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await t.pump();
      await t.pump();
      expect(r.output.stops, greaterThanOrEqualTo(1));
      expect(r.c.phase, VoicePhase.idle);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
    });
  });

  group('5. Talk button', () {
    Future<List<String>> recordHaptics(WidgetTester t) async {
      final calls = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add('${call.arguments}');
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      return calls;
    }

    String? semanticsValue(WidgetTester t) => t
        .widget<Semantics>(find.descendant(of: find.byType(TalkButton), matching: find.byType(Semantics)).first)
        .properties
        .value;

    testWidgets('idle "Tap to talk"; listening shows a red dot, "Listening… tap when done", value and haptics', (
      t,
    ) async {
      final haptics = await recordHaptics(t);
      final r = Rig();
      await r.pump(t);
      await r.start(t, voice: true);
      expect(talkLabel(t), 'Talk or type');
      expect(semanticsValue(t), 'Not listening');
      expect(find.byType(RecordingDot), findsNothing);

      await tapTalk(t);
      expect(r.c.phase, VoicePhase.listening);
      expect(talkLabel(t), 'Listening… tap when done');
      expect(semanticsValue(t), 'Listening');
      expect(find.byType(RecordingDot), findsOneWidget);
      // Reduced motion: the dot stays still.
      expect(find.descendant(of: find.byType(TalkButton), matching: find.byType(FadeTransition)), findsNothing);
      expect(haptics, hasLength(1));

      await tapTalk(t);
      await t.pumpAndSettle();
      expect(haptics, hasLength(2));
    });

    testWidgets('the dot pulses only when motion is allowed', (t) async {
      final r = Rig();
      await r.pump(t, reducedMotion: false);
      await r.start(t, voice: true);
      await tapTalk(t);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.descendant(of: find.byType(TalkButton), matching: find.byType(FadeTransition)), findsOneWidget);
      await tapTalk(t);
      await t.pumpAndSettle();
    });
  });

  group('6. silence timeout', () {
    testWidgets('closes the microphone after 8 s with no words and says it heard nothing', (t) async {
      final r = Rig();
      r.fakeInput.transcript = '';
      await r.pump(t);
      await r.start(t, voice: true);
      await tapTalk(t);
      await t.pump(const Duration(seconds: 7));
      expect(r.c.phase, VoicePhase.listening);
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(r.c.phase, isNot(VoicePhase.listening));
      expect(r.fakeInput.finishes, 1);
      expect(find.text("I didn't hear anything. Tap Talk and try again, or type."), findsOneWidget);
      expect(r.calls.length, 1); // nothing sent
    });

    testWidgets('closes after 30 s in all, counting down in the last 10 s, and sends what was heard', (t) async {
      final input = LiveInput()..transcript = 'I am seventy';
      final r = Rig(input: input);
      await r.pump(t);
      await r.start(t, voice: true);
      await tapTalk(t);
      for (var s = 1; s <= 30; s++) {
        input.say!('word $s');
        await t.pump(const Duration(seconds: 1));
        if (s == 19) expect(talkLabel(t), 'Listening… tap when done');
        if (s == 20) expect(talkLabel(t), 'Listening… tap when done (10 s left)');
        if (s == 25) expect(talkLabel(t), 'Listening… tap when done (5 s left)');
      }
      await t.pumpAndSettle();
      expect(input.finishes, 1);
      expect(r.calls.last['text'], 'I am seventy');
    });
  });

  group('7 and 9. go back and progress', () {
    testWidgets('"Question N of 11" counts confirmed and skipped; Go back appears after an answer', (t) async {
      final r = Rig(guide: StepGuide());
      await r.pump(t);
      await r.start(t, voice: false);
      expect(find.text('Question 1 of 12'), findsOneWidget);
      expect(find.text('Go back'), findsNothing);

      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      expect(find.text('Question 1 of 12'), findsOneWidget); // still checking the first answer
      expect(find.text('Go back'), findsNothing);
      await t.tap(find.text('Yes'));
      await t.pumpAndSettle();
      expect(find.text('Question 2 of 12'), findsOneWidget);

      await t.pump(const Duration(milliseconds: 700)); // links that stay in place ignore a second tap at first
      await tapText(t, 'Skip this question');
      expect(find.text('Question 3 of 12'), findsOneWidget);

      expect(t.getSize(button('Go back')).height, greaterThanOrEqualTo(56));
      await t.pump(const Duration(milliseconds: 700)); // links that stay in place ignore a second tap at first
      await tapText(t, 'Go back');
      expect(r.calls.last, {'action': 'reply', 'text': 'go back'});
      expect(find.textContaining('Question about sex'), findsOneWidget);
      // The reopened question counts as the one being asked.
      expect(find.text('Question 2 of 12'), findsOneWidget);
      expect(find.text('You said: go back'), findsNothing);
    });
  });

  group('8. controls', () {
    testWidgets('the AI helper chip and Settings switch stay in step', (t) async {
      final r = Rig(guide: StepGuide());
      await r.pump(t);
      await r.start(t, voice: false);
      expect(find.text('AI helper: Off'), findsOneWidget);
      expect(find.text('Use my Apple Health'), findsNothing, reason: 'the opening is decluttered');
      expect(find.widgetWithText(LinkButton, 'Talk instead'), findsOneWidget);

      await tapText(t, 'Settings');
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(r.c.aiHelper, isTrue);
      await tapText(t, 'Done');
      expect(find.text('AI helper: On'), findsOneWidget);
      await tapText(t, 'AI helper: On');
      expect(r.c.aiHelper, isFalse);

      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      await t.tap(find.text('Yes'));
      await t.pumpAndSettle();
      expect(find.text('Use my Apple Health'), findsNothing);
    });

    for (final scale in [1.0, 3.1]) {
      testWidgets('scale $scale: the opening has no Apple Health button and does not overflow', (t) async {
        final r = Rig();
        await r.pump(t, scale: scale);
        await r.start(t, voice: true);
        expect(t.takeException(), isNull);
        expect(find.text('Use my Apple Health'), findsNothing);
      });
    }

    testWidgets('Talk instead and Type instead look the same', (t) async {
      final r = Rig();
      await r.pump(t);
      await r.start(t, voice: true);
      expect(find.widgetWithText(LinkButton, 'Type instead'), findsOneWidget);
      final size = t.getSize(button('Type instead'));
      await tapText(t, 'Type instead');
      expect(find.widgetWithText(LinkButton, 'Talk instead'), findsOneWidget);
      expect(t.getSize(button('Talk instead')).height, size.height);
    });

    testWidgets('Settings can switch to typing', (t) async {
      final r = Rig();
      await r.pump(t);
      await r.start(t, voice: true);
      await tapText(t, 'Settings');
      await tapText(t, 'Type');
      expect(r.c.typing, isTrue);
    });
  });

  group('10. keyboard', () {
    testWidgets('number pad for number questions, normal keyboard otherwise', (t) async {
      final r = Rig(guide: StepGuide());
      await r.pump(t);
      await r.start(t, voice: false);
      TextInputType kind() => t.widget<TextField>(find.byType(TextField)).keyboardType;
      expect(kind(), const TextInputType.numberWithOptions(decimal: true));
      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      await t.tap(find.text('Yes'));
      await t.pumpAndSettle();
      expect(r.c.state?['current_field'], 'sex');
      expect(kind(), isNot(const TextInputType.numberWithOptions(decimal: true)));
    });

    // Root cause of the swallowed taps: the old layout sized its scroll area
    // from SliverFillRemaining, which under-measured the controls. With the
    // keyboard up, Send and Hide keyboard were laid out below the visible
    // area and could not be scrolled to, so a tap there landed on the
    // tap-outside detector and closed the keyboard instead. Separately the
    // field was disabled while waiting, which dropped focus and the keyboard.
    for (final scale in [1.0, 2.0]) {
      testWidgets('scale $scale: with the keyboard up, field, Send and Hide keyboard are on screen and work', (
        t,
      ) async {
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
        final r = Rig();
        await r.pump(t, scale: scale);
        await r.start(t, voice: false);
        // A first answer the server could not read, so a caption and an offer are on screen.
        await t.enterText(find.byType(TextField), 'about five foot eight');
        await t.tap(find.text('Send'));
        await t.pumpAndSettle();
        expect(r.c.caption, isNotEmpty);

        await t.ensureVisible(find.byType(TextField));
        await t.tap(find.byType(TextField));
        await t.pump();
        final before = t.state(find.byType(EditableText));
        t.view.viewInsets = const FakeViewPadding(bottom: 336);
        addTearDown(t.view.resetViewInsets);
        await t.pump();
        // The field kept its state and focus while the screen rearranged itself.
        expect(identical(t.state(find.byType(EditableText)), before), isTrue);
        expect(fieldFocused(t), isTrue);

        const visibleBottom = 844.0 - 336;
        final hide = t.getRect(button('Hide keyboard'));
        expect(hide.bottom, lessThanOrEqualTo(visibleBottom));
        expect(hide.height, greaterThanOrEqualTo(72));
        if (scale == 1.0) {
          expect(t.getRect(button('Send')).bottom, lessThanOrEqualTo(visibleBottom));
          expect(t.getRect(find.byType(TextField)).bottom, lessThanOrEqualTo(visibleBottom));
        }

        // Typing and Send both land.
        await t.enterText(find.byType(TextField), '70');
        await t.pump();
        await t.ensureVisible(find.text('Send'));
        await t.tap(find.text('Send'));
        await t.pumpAndSettle();
        expect(r.calls.last['text'], '70');
      });
    }

    testWidgets('the field keeps focus while the server answers', (t) async {
      final guide = StepGuide();
      final r = Rig(guide: guide);
      await r.pump(t);
      await r.start(t, voice: false);
      await t.tap(find.byType(TextField));
      await t.pump();
      t.view.viewInsets = const FakeViewPadding(bottom: 336);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      await t.tap(find.text('Skip this question'));
      await t.pump();
      guide.gate = Completer<void>();
      await t.enterText(find.byType(TextField), 'female');
      await t.tap(find.text('Send'));
      await t.pump();
      expect(r.c.phase, VoicePhase.interpreting);
      expect(fieldFocused(t), isTrue);
      expect(t.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      guide.gate!.complete();
      await t.pumpAndSettle();
    });
  });

  group('11 and 12. what is said out loud', () {
    testWidgets('parentheses are shown but not spoken', (t) async {
      final r = Rig();
      await r.pump(t);
      for (final l in ["Yes, I'll talk", 'Yes, turn it on']) {
        await tapText(t, l);
        await t.pump(const Duration(milliseconds: 700)); // the AI question ignores a second tap at first
      }
      r.fakeInput.transcript = 'about five foot eight';
      await tapTalk(t);
      await tapTalk(t);
      await t.pumpAndSettle();
      expect(find.textContaining('(about 173 cm)'), findsOneWidget);
      expect(r.output.spoken.last, 'I heard you are 5 feet 8 inches tall. Is that right?');
    });

    testWidgets('mic denied is spoken and offers Open Settings', (t) async {
      final r = Rig();
      r.fakeInput.startError = const MicDeniedException();
      await r.pump(t);
      await r.start(t, voice: true);
      await tapTalk(t);
      await t.pumpAndSettle();
      expect(r.output.spoken.last, micDeniedNotice);
      await tapText(t, 'Open Settings');
      expect(r.settingsOpened, 1);
    });

    testWidgets('no network is spoken by voice', (t) async {
      final r = Rig();
      await r.pump(t);
      await r.start(t, voice: true);
      (r.guide as FakeConversationGuide).failNext = true;
      await r.c.submitTyped('70');
      await t.pumpAndSettle();
      expect(r.output.spoken.last, noNetworkNotice);
    });

    testWidgets('no network is not spoken when typing', (t) async {
      final typed = Rig();
      await typed.pump(t);
      await typed.start(t, voice: false);
      (typed.guide as FakeConversationGuide).failNext = true;
      await typed.c.submitTyped('70');
      await t.pumpAndSettle();
      expect(find.text(noNetworkNotice), findsOneWidget);
      expect(typed.output.spoken, isEmpty);
    });
  });

  group('13. VoiceOver', () {
    testWidgets('every control has a name; no unnamed screen-sized button', (t) async {
      final handle = t.ensureSemantics();
      final r = Rig();
      await r.pump(t);
      await r.start(t, voice: false);
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      await t.enterText(find.byType(TextField), '70');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('with a screen reader on, the mascot does not also speak; the line is a live region', (t) async {
      final r = Rig();
      r.fakeInput.startError = const MicDeniedException();
      await r.pump(t, screenReader: true);
      await r.start(t, voice: true);
      expect(r.c.mascotLine, 'How old are you?');
      expect(r.output.spoken, isEmpty);
      final live = find.ancestor(
        of: find.text('How old are you?'),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      );
      expect(live, findsWidgets);
      await tapTalk(t);
      await t.pumpAndSettle();
      expect(r.output.spoken, isEmpty); // the notice is announced by VoiceOver, not spoken twice
    });
  });

  group('the twin', () {
    testWidgets('waves while a question shows, thinks while the mic is on, jumps on the read-back and after "Got it"', (
      t,
    ) async {
      final r = Rig(guide: StepGuide());
      r.fakeInput.captions = ['I am 70'];
      await r.pump(t);
      await r.start(t, voice: true);
      expect(twinPose(t), TwinMood.asking.pose);
      await tapTalk(t);
      expect(r.c.phase, VoicePhase.listening);
      expect(twinPose(t), TwinMood.listening.pose);
      // Listening: the caption card shows the words large.
      expect(find.text('Hearing:'), findsOneWidget);
      await tapTalk(t);
      await t.pumpAndSettle();
      expect(r.c.confirming, isTrue);
      expect(twinPose(t), TwinMood.pleased.pose);
      await t.tap(find.text('Yes'));
      await t.pumpAndSettle();
      expect(r.c.mascotLine, startsWith('Got it.'));
      expect(twinPose(t), TwinMood.pleased.pose);
      await t.pump(const Duration(milliseconds: 700)); // links that stay in place ignore a second tap at first
      await tapText(t, 'Skip this question');
      expect(twinPose(t), TwinMood.asking.pose);
    });

    testWidgets('the live caption is large while listening', (t) async {
      final input = LiveInput()..transcript = 'about five foot ten';
      final r = Rig(input: input);
      await r.pump(t);
      await r.start(t, voice: true);
      await tapTalk(t);
      input.say!('about five foot ten');
      await t.pump();
      final words = t.widget<Text>(find.text('about five foot ten'));
      expect(words.style!.fontSize, greaterThanOrEqualTo(32));
      final live = find.ancestor(
        of: find.text('about five foot ten'),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      );
      expect(live, findsWidgets);
      await tapTalk(t);
      await t.pumpAndSettle();
    });

    testWidgets('scale 2.0: question, listening and read-back fit, with the window made small', (t) async {
      final r = Rig(guide: StepGuide());
      r.fakeInput.captions = ['I am 70'];
      await r.pump(t, scale: 2.0);
      await r.start(t, voice: true);
      expect(t.takeException(), isNull);
      expect(windowHeight(t), lessThanOrEqualTo(150));
      expect(t.getRect(find.byType(TalkButton)).bottom, lessThanOrEqualTo(844));
      await tapTalk(t);
      expect(r.c.phase, VoicePhase.listening);
      expect(t.takeException(), isNull);
      expect(windowHeight(t), lessThanOrEqualTo(150));
      await tapTalk(t);
      await t.pumpAndSettle();
      expect(r.c.confirming, isTrue);
      expect(t.takeException(), isNull);
      expect(t.getRect(button('Yes')).bottom, lessThanOrEqualTo(844));
      expect(t.getSize(button('Yes')).height, greaterThanOrEqualTo(72));
    });

    testWidgets('reduced motion: nothing keeps moving', (t) async {
      final r = Rig();
      await r.pump(t);
      await r.start(t, voice: true);
      expect(t.hasRunningAnimations, isFalse);
    });
  });

  group('14. looks', () {
    testWidgets('"You said:" is not italic; button words are ink; links are ink and underlined', (t) async {
      final r = Rig();
      await r.pump(t);
      await r.start(t, voice: false);
      await t.enterText(find.byType(TextField), 'about five foot eight');
      await t.tap(find.text('Send'));
      await t.pumpAndSettle();
      final said = t.widget<Text>(find.textContaining('You said:'));
      expect(said.style?.fontStyle, isNot(FontStyle.italic));

      for (final label in ['Send', 'Talk instead']) {
        expect(t.widget<Text>(find.text(label)).style?.color, LtColors.ink, reason: label);
      }
      final skip = t.widget<Text>(find.text('Skip this question')).style!;
      expect(skip.color, LtColors.ink);
      expect(skip.decoration, TextDecoration.underline);
    });

    testWidgets('no debug banner', (t) async {
      await t.pumpWidget(LifeTwinApp(controller: Rig().c));
      expect(t.widget<MaterialApp>(find.byType(MaterialApp)).debugShowCheckedModeBanner, isFalse);
    });
  });
}
