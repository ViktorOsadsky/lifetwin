import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_screen.dart';
import 'package:lifesim/experiment/experiment_screen.dart';
import 'package:lifesim/experiment/widgets/pills.dart';
import 'package:lifesim/twin/twin_checkin_store.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/widgets/bubble.dart';
import 'package:lifesim/ui/widgets/plate_window.dart';
import 'package:lifesim/voice/fakes.dart';

import 'checkin_controller_test.dart' show FakeCheckinGuide;
import 'experiment/experiment_screen_test.dart' show older;
import 'support/app_fonts.dart';

// Actual native QA read-back was 17 -> 53 pt at the largest accessibility size.
const nativeMaximumScale = 53 / 17;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<TwinRepository> repository() async {
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
    );
    await repo.saveConversationProfile(older);
    return repo;
  }

  Future<void> pumpScreen(
    WidgetTester t,
    Widget screen,
    double scale,
    double width,
  ) async {
    t.view.physicalSize = Size(width, 874);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: screen,
      ),
    );
    await t.pumpAndSettle();
  }

  for (final scale in [1.0, 1.6, nativeMaximumScale]) {
    testWidgets(
      'Experiment labels clear the name banner and each other at $scale',
      (t) async {
        final repo = await repository();
        await pumpScreen(
          t,
          ExperimentScreen(
            repository: repo,
            appearance: const TwinAppearance(name: 'My twin'),
            onBack: () {},
            onTellMochi: (_) {},
          ),
          scale,
          375,
        );
        final name = t.getRect(find.byType(NameBanner));
        final pills = find.byType(ModePill);
        expect(pills, findsNWidgets(2));
        final today = t.getRect(pills.at(0));
        final whatIf = t.getRect(pills.at(1));
        expect(
          today.overlaps(name),
          isFalse,
          reason: 'Today must clear the growing banner',
        );
        expect(
          whatIf.overlaps(name),
          isFalse,
          reason: 'What-if must clear the growing banner',
        );
        expect(
          today.overlaps(whatIf),
          isFalse,
          reason: 'whole mode labels must not overlap',
        );
        for (final label in ['Today', 'What-if']) {
          final finder = find.text(label);
          final paragraph = t.renderObject<RenderParagraph>(finder);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(paragraph.textScaler.scale(17), closeTo(17 * scale, 0.001));
          final rect = t.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(375));
        }
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final width in [375.0, 402.0]) {
    for (final scale in [1.6, nativeMaximumScale]) {
      testWidgets(
        'Check-in full question stays readable while typing at $width / $scale',
        (t) async {
          final repo = await repository();
          final controller = CheckinController(
            guide: FakeCheckinGuide(),
            input: FakeSpeechInput(),
            output: FakeSpeechOutput(),
            store: TwinCheckinStore(repo),
            voiceUsable: false,
          );
          addTearDown(controller.dispose);
          await pumpScreen(
            t,
            CheckInScreen(
              controller: controller,
              kind: CheckInKind.quick,
              repository: repo,
              appearance: const TwinAppearance(name: 'Mochi'),
              onDone: () {},
            ),
            scale,
            width,
          );
          final field = find.byType(TextField);
          await t.showKeyboard(field);
          await t.enterText(field, '7 hours');
          t.view.viewInsets = const FakeViewPadding(bottom: 336);
          t.view.padding = const FakeViewPadding(top: 62);
          await t.pumpAndSettle();

          void expectReadable(String question) {
            final text = find.text(question);
            expect(text, findsOneWidget);
            final bubble = find.ancestor(
              of: text,
              matching: find.byType(Bubble),
            );
            final scroll = find
                .ancestor(
                  of: bubble,
                  matching: find.byType(SingleChildScrollView),
                )
                .first;
            final viewport = t.getRect(scroll);
            final glyphs = t.getRect(text);
            // ExperimentPage's opaque/back bar is 76 pt tall once scrolled.
            expect(glyphs.top, greaterThanOrEqualTo(viewport.top + 76));
            expect(glyphs.bottom, lessThanOrEqualTo(viewport.bottom));
            expect(glyphs.overlaps(t.getRect(field)), isFalse);
            final input = t.getRect(field);
            final send = t.getRect(find.byTooltip('Send'));
            expect(input.bottom, lessThanOrEqualTo(874 - 336));
            expect(send.bottom, lessThanOrEqualTo(874 - 336));
            expect(send.height, greaterThanOrEqualTo(48));
            expect(send.width, greaterThanOrEqualTo(48));
            final paragraph = t.renderObject<RenderParagraph>(text);
            expect(
              paragraph.textScaler.scale(19),
              closeTo(19 * scale, 0.001),
              reason: 'the question must retain the chosen text size',
            );
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(t.testTextInput.isVisible, isTrue);
            expect(
              t
                  .widget<EditableText>(find.byType(EditableText))
                  .focusNode
                  .hasFocus,
              isTrue,
            );
          }

          expectReadable('How did you sleep?');
          expect(t.widget<TextField>(field).controller!.text, '7 hours');
          final prompt = find.text('How did you sleep?');
          final scrolling = Scrollable.of(t.element(prompt)).position;
          final beforeDrag = scrolling.pixels;
          await t.dragFrom(Offset(width / 2, 170), const Offset(0, -50));
          await t.pumpAndSettle();
          final userOffset = scrolling.pixels;
          expect(userOffset, greaterThan(beforeDrag));
          controller.notifyListeners();
          await t.pumpAndSettle();
          expect(
            scrolling.pixels,
            closeTo(userOffset, 0.01),
            reason:
                'an unrelated rebuild must not override the person’s scroll',
          );
          // A new question must also be brought into the readable viewport without
          // closing the keyboard or saving a completed check-in.
          await controller.skip();
          await t.pumpAndSettle();
          expectReadable('How much sitting?');
          expect(repo.store.checkins, isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
