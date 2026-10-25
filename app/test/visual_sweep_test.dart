// The visual sweep: every screen and state at the demo phone sizes, at 1x and 2x text.
// Each picture is checked for overflow, clipped or mid-word text, overlapping text, tap targets
// under 48 pt and content under the dock. With EVIDENCE_DIR set, a PNG per screen and size plus a
// contact sheet per screen are written for review.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/band/band_ble.dart' show bandFirmwareUpdateNeeded;
import 'package:lifesim/band/band_file_session.dart';
import 'package:lifesim/band/band_store.dart';
import 'package:lifesim/documents/document_screen.dart';
import 'package:lifesim/documents/document_upload.dart';
import 'package:lifesim/experiment/idea_detail_screen.dart';
import 'package:lifesim/experiment/side_by_side_screen.dart';
import 'package:lifesim/twin/twin_experiment.dart' show LeverId;
import 'package:lifesim/wellness/history_screen.dart';
import 'package:lifesim/wellness/models.dart';
import 'package:lifesim/wellness/coach_client.dart' show DailyPlan;
import 'package:lifesim/checkin/checkin_client.dart' show CheckinGuide;
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/room/room_scene.dart' show RoomScene;
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart' show TalkButton;
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'checkin/daily_checkin_test.dart' show profile;
import 'checkin/readback_flow_test.dart' show ContractGuide;
import 'checkin_controller_test.dart' show FakePort;
import 'document_pdf_claude_test.dart' show FakeOcr, FakeText, FakePdfReader, claude, found;
import 'experiment/ideas_test.dart' show FakeSource, pace, sleep, sit;
import 'forecast_screen_test.dart' show FakeForecastClient, supportedJson;
import 'support/app_fonts.dart';
import 'wellness/coach_test.dart' show FakeCoach, planJson;
import 'support/assessments.dart';
import 'support/fake_change_client.dart';
import 'support/fake_weekly_guide.dart';
import 'whole_word_text_test.dart' show brokenWords;

/// The demo phone (iPhone 17 Pro), the small iPhone SE and the smallest supported width.
const sizes = [('17pro', Size(402, 874)), ('se', Size(375, 667)), ('320', Size(320, 568))];
const scales = [1.0, 2.0];

Future<void> loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final f = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())))).load();
}

/// A bounded settle: some indicators animate forever, so pumpAndSettle would time out.
Future<void> settle(WidgetTester t, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

/// What one sweep entry has to work with once the app is up.
class Sweep {
  Sweep(this.t, this.routes, this.repo, this.input, this.voice);
  final WidgetTester t;
  final AgenticRoutes routes;
  final TwinRepository repo;
  final FakeSpeechInput input;
  final VoiceOnboardingController voice;
  NavigatorState get navigator => routes.navigatorKey.currentState!;

  Future<void> push(Widget Function(BuildContext c) page) async {
    navigator.push(MaterialPageRoute<void>(builder: page)).ignore();
  }

  Future<void> tap(String text) async {
    await t.ensureVisible(find.text(text).last);
    await settle(t, 3);
    await t.tap(find.text(text).last);
    await settle(t, 4);
  }
  BuildContext get nav => routes.navigatorKey.currentContext!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    await loadMaterialIcons();
    model = await TwinModelService.load();
  });
  tearDown(BandFileSession.disposeIfCreated);

  final evidenceDir = Platform.environment['EVIDENCE_DIR'];
  final shotKey = GlobalKey();

  Future<ui.Image?> capture(WidgetTester t) async {
    if (evidenceDir == null) return null;
    await t.runAsync(() async {
      final c = t.element(find.byType(Navigator).first);
      await precacheImage(const AssetImage('assets/scene/room/room_bg.jpg'), c);
      for (final pose in TwinPose.values) {
        try {
          await precacheImage(AssetImage(twinAsset(TwinType.bear, TwinLook.calHat, pose)), c);
        } catch (_) {}
      }
    });
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 100));
    ui.Image? img;
    await t.runAsync(() async {
      final b = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      img = await b.toImage(pixelRatio: 1);
    });
    return img;
  }

  Future<void> writePng(WidgetTester t, ui.Image img, String path) async {
    await t.runAsync(() async {
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final f = File(path)..parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  /// All pictures of one screen in one image: a row per (text size, top/end), a column per phone.
  Future<void> sheet(WidgetTester t, String name, Map<String, ui.Image> shots) async {
    if (shots.isEmpty) return;
    const gap = 24.0, label = 28.0;
    final rows = <String>{for (final k in shots.keys) k.split('@').last}.toList();
    final cols = [for (final s in sizes) s.$1];
    final width = sizes.fold<double>(0, (a, s) => a + s.$2.width + gap) + gap;
    final rowH = <double>[
      for (final r in rows)
        sizes.fold<double>(0, (a, s) => (shots['${s.$1}@$r']?.height.toDouble() ?? 0) > a ? shots['${s.$1}@$r']!.height.toDouble() : a),
    ];
    final height = rowH.fold<double>(0, (a, h) => a + h + label + gap) + gap;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = const Color(0xFF555555));
    var y = gap;
    for (var r = 0; r < rows.length; r++) {
      var x = gap;
      for (var c = 0; c < cols.length; c++) {
        final tp = TextPainter(
          text: TextSpan(text: '${cols[c]} ${rows[r]}', style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 18, fontFamily: 'Atkinson Hyperlegible')),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x, y));
        tp.dispose();
        final img = shots['${cols[c]}@${rows[r]}'];
        if (img != null) canvas.drawImage(img, Offset(x, y + label), Paint());
        x += sizes[c].$2.width + gap;
      }
      y += rowH[r] + label + gap;
    }
    final out = await rec.endRecording().toImage(width.ceil(), height.ceil());
    await writePng(t, out, '$evidenceDir/sheets/$name.png');
  }

  /// Painted on screen: not inside an offstage route (the Room under a pushed page) or a hidden layer.
  bool shown(RenderObject o) {
    for (RenderObject? p = o; p != null; p = p.parent) {
      if (p is RenderOffstage && p.offstage) return false;
      if (p is RenderOpacity && p.opacity == 0) return false;
      if (p is RenderAnimatedOpacity && p.opacity.value == 0) return false;
      if (p is RenderSliverOpacity && p.opacity == 0) return false;
    }
    return true;
  }

  /// The Room's dock, when it is on screen.
  final dockFinder = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Dock');
  Rect? dockRect(WidgetTester t) {
    final dock = dockFinder.evaluate();
    if (dock.isEmpty || !shown(dock.first.renderObject!)) return null;
    return t.getRect(dockFinder);
  }

  /// Geometry problems on the current screen.
  List<String> problems(WidgetTester t, {bool end = false, bool checkTargets = true, Set<String> allowOverlap = const {}}) {
    final out = <String>[];
    final screen = Offset.zero & t.view.physicalSize;
    // Mid-word breaks and cut-off text.
    // A line deliberately ended with "…" (a one-line preview) is not cut off.
    final ellipsed = {
      for (final p in t.allRenderObjects.whereType<RenderParagraph>())
        if (p.overflow == TextOverflow.ellipsis) 'cut off: "${p.text.toPlainText(includeSemanticsLabels: false)}"',
    };
    final hidden = {
      for (final p in t.allRenderObjects.whereType<RenderParagraph>())
        if (!shown(p)) p.text.toPlainText(includeSemanticsLabels: false),
    };
    out.addAll(
      brokenWords(t)
          .where((p) => !ellipsed.contains(p) && !hidden.any((h) => p.replaceAll('|', '').contains(h)))
          // A line may break after a dash ("Monday–|Sunday").
          .where((p) => !p.contains('–|') && !p.contains('—|'))
          .map((p) => 'text: $p'),
    );
    // Visible text that overlaps other visible text.
    // Each text with its page, the list it scrolls in, and whether it is part of the room picture
    // (which is painted under the cards by design).
    final texts = <(String, Rect, ModalRoute<Object?>?, ScrollableState?, bool)>[];
    for (final e in find.byType(RichText).evaluate()) {
      final p = e.renderObject;
      if (p is! RenderParagraph || !p.attached || !p.hasSize || p.size.isEmpty || !shown(p)) continue;
      final s = p.text.toPlainText(includeSemanticsLabels: false).trim();
      if (s.isEmpty || s.runes.length == 1 && s.runes.first > 0xE000) continue; // icons
      var r = MatrixUtils.transformRect(p.getTransformTo(null), Offset.zero & p.size);
      // Only the part its list shows: text scrolled out of a list is clipped away.
      final list = Scrollable.maybeOf(e);
      if (list != null) {
        final box = list.context.findRenderObject()! as RenderBox;
        final view = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
        if (!view.overlaps(r)) continue;
        r = r.intersect(view);
      }
      if (!screen.overlaps(r)) continue;
      final scene = e.findAncestorWidgetOfExactType<RoomScene>() != null;
      texts.add((s, r, ModalRoute.of(e), list, scene));
    }
    for (var i = 0; i < texts.length; i++) {
      for (var j = i + 1; j < texts.length; j++) {
        final a = texts[i], b = texts[j];
        final o = a.$2.intersect(b.$2);
        // The outlined display text is the same words painted twice (stroke and fill).
        if (a.$1 == b.$1 && (a.$2.center - b.$2.center).distance < 3) continue;
        // A sheet or dialog over the page below, and the room picture under the cards.
        if (a.$3 != b.$3 || a.$5 != b.$5) continue;
        // A list scrolling under a fixed bar: allowed mid-list; at the end, the last line must clear it.
        // (A fixed header at the top may cover the list; only a bar at the bottom must clear it.)
        if (a.$4 != b.$4 && (!end || o.center.dy < screen.height / 2)) continue;
        if (o.width > 2 && o.height > 2 && !allowOverlap.contains(a.$1) && !allowOverlap.contains(b.$1)) {
          out.add('overlap: "${a.$1}" and "${b.$1}"');
        }
      }
    }
    // Text under the dock.
    final dock = dockRect(t);
    if (dock != null) {
      final dockTexts = find.descendant(of: dockFinder, matching: find.byType(RichText));
      final inDock = {for (final e in dockTexts.evaluate()) e.renderObject};
      final room = ModalRoute.of(dockFinder.evaluate().first);
      for (final e in find.byType(RichText).evaluate()) {
        final p = e.renderObject;
        // Only the Room's own text; a sheet over the Room covers the dock.
        if (p is! RenderParagraph || ModalRoute.of(e) != room) continue;
        if (inDock.contains(p) || !p.attached || !p.hasSize || !shown(p)) continue;
        final r = MatrixUtils.transformRect(p.getTransformTo(null), Offset.zero & p.size);
        final o = r.intersect(dock);
        if (o.width > 2 && o.height > 2) out.add('under the dock: "${p.text.toPlainText()}"');
      }
    }
    // Tap targets under 48 pt (buttons, ink and gesture detectors with a tap).
    if (checkTargets) {
      final tappables = find.byWidgetPredicate(
        (w) =>
            w is InkResponse && w.onTap != null ||
            w is GestureDetector && w.onTap != null ||
            w is ButtonStyleButton && w.onPressed != null ||
            w is IconButton && w.onPressed != null,
      );
      for (final e in tappables.evaluate()) {
        final box = e.renderObject;
        if (box is! RenderBox || !box.attached || !box.hasSize || !shown(box)) continue;
        // Material chips pad their tap area to 48 outside the drawn chip.
        if (e.findAncestorWidgetOfExactType<RawChip>() != null) continue;
        final r = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
        if (!screen.overlaps(r) || r.width >= screen.width * 0.9 && r.height >= screen.height * 0.4) continue;
        // Partly scrolled off screen: judged when it is fully visible.
        if (!screen.inflate(0.5).contains(r.topLeft) || !screen.inflate(0.5).contains(r.bottomRight)) continue;
        // Covered by a card or sheet: not tappable here, so not judged.
        final hit = HitTestResult();
        t.binding.hitTestInView(hit, r.center, t.view.viewId);
        if (!hit.path.any((h) => h.target == box)) continue;
        if (r.width < 47.5 || r.height < 47.5) {
          final label = find.descendant(of: find.byWidget(e.widget), matching: find.byType(Text)).evaluate();
          final what = label.isEmpty ? '' : ' "${(label.first.widget as Text).data ?? ''}"';
          out.add('small target ${e.widget.runtimeType}$what ${r.size.width.toStringAsFixed(0)}x${r.size.height.toStringAsFixed(0)} at ${r.topLeft}');
        }
      }
    }
    return out;
  }

  /// One sweep entry: [open] brings the screen up (the app is already on the Room).
  void sweep(
    String name,
    Future<void> Function(Sweep s) open, {
    Map<String, Object> prefs = const {},
    bool withProfile = true,
    bool guestEntry = false,
    bool loading = false,
    bool handsFree = false,
    Map<String, Object> profileData = profile,
    BandClient? bandClient,
    bool ideas = true,
    CheckinGuide? guide,
    bool checkTargets = true,
    Set<String> allowOverlap = const {},
    Set<String> knownTargets = const {},
  }) {
    testWidgets('sweep: $name', (t) async {
      final shots = <String, ui.Image>{};
      final failures = <String>[];
      for (final (sizeName, size) in sizes) {
        for (final scale in scales) {
          SharedPreferences.setMockInitialValues({...prefs});
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          t.platformDispatcher.textScaleFactorTestValue = scale;
          // Joined 8 days ago, so the weekly check-in is open.
          var clock = DateTime.now().subtract(const Duration(days: 8));
          final repo = TwinRepository(
            model: model,
            store: await TwinStore.open(MemoryBackend()),
            reminders: CheckinReminders(FakePort()),
            clock: () => clock,
          );
          if (withProfile) await repo.saveConversationProfile(profileData);
          clock = DateTime.now();
          final look = ValueNotifier(const TwinAppearance(name: 'Mochi', look: TwinLook.calHat));
          final input = FakeSpeechInput();
          final voice = VoiceOnboardingController(
            guide: FakeConversationGuide(),
            input: input,
            output: FakeSpeechOutput(),
            handsFree: handsFree,
          );
          final routes = AgenticRoutes(
            look: look,
            api: ApiBase('http://test'),
            voice: () => voice,
            guide: guide ?? ContractGuide(),
            changeClient: FakeChangeClient(),
            openSettings: () async {},
            bandClient: bandClient ?? StubBandClient(),
            coach: FakeCoach()..responses.addAll([for (var i = 0; i < 8; i++) DailyPlan.fromJson(planJson())]),
            ideasSource: ideas ? (_) => FakeSource([pace, sleep, sit]) : null,
          );
          final forecast = FakeForecastClient()..answers.addAll([for (var i = 0; i < 6; i++) forecastFrom(supportedJson())]);
          await t.pumpWidget(
            RepaintBoundary(
              key: shotKey,
              child: LifeTwinApp(
                controller: voice,
                forecastClient: forecast,
                twin: Future.value(repo),
                agentic: routes,
                appearance: look,
                showGuestEntry: guestEntry,
                loadingScreen: loading,
              ),
            ),
          );
          await settle(t, 6);
          final s = Sweep(t, routes, repo, input, voice);
          await open(s);
          await settle(t);
          final tag = '$sizeName ${scale}x';
          final ex = t.takeException();
          if (ex != null) {
            if (Platform.environment['SWEEP_DEBUG'] != null) {
              for (final f in t.allRenderObjects.whereType<RenderFlex>()) {
                if (!f.hasSize) continue;
                var used = 0.0;
                f.visitChildren((c) => used += f.direction == Axis.horizontal ? (c as RenderBox).size.width : (c as RenderBox).size.height);
                final room = f.direction == Axis.horizontal ? f.size.width : f.size.height;
                if (used > room + 1) debugPrint('OVERFLOW ${f.debugCreator}');
              }
            }
            final where = ex is FlutterError ? ex.diagnostics.map((d) => d.toString()).where((l) => l.contains('Column') || l.contains('Row') || l.contains('file:')).take(2).join(' / ') : '';
            failures.add('$name $tag: exception ${ex.toString().split('\n').first} $where');
          }
          final found = problems(t, checkTargets: checkTargets, allowOverlap: allowOverlap)
              .where((p) => !knownTargets.any(p.contains));
          failures.addAll(found.map((p) => '$name $tag: $p'));
          final row = '${scale}x';
          final top = await capture(t);
          if (top != null) {
            shots['$sizeName@$row'] = top;
            await writePng(t, top, '$evidenceDir/$name/$sizeName-${scale}x.png');
          }
          // The end of a scrolling page, so nothing hidden under the dock or the edge goes unseen.
          final scrollables = find.byType(Scrollable).evaluate().map((e) => (e as StatefulElement).state as ScrollableState).where(
            (st) =>
                st.position.axis == Axis.vertical &&
                st.position.maxScrollExtent > 40 &&
                st.context.findRenderObject()!.paintBounds.height > 200 &&
                shown(st.context.findRenderObject()!) &&
                (ModalRoute.of(st.context)?.isCurrent ?? true),
          );
          if (scrollables.isNotEmpty) {
            final st = scrollables.first;
            st.position.jumpTo(st.position.maxScrollExtent);
            await settle(t, 3);
            failures.addAll(
              problems(t, end: true, checkTargets: checkTargets, allowOverlap: allowOverlap)
                  .where((p) => !knownTargets.any(p.contains))
                  .map((p) => '$name $tag end: $p'),
            );
            final end = await capture(t);
            if (end != null) {
              shots['$sizeName@$row end'] = end;
              await writePng(t, end, '$evidenceDir/$name/$sizeName-${scale}x-end.png');
            }
          }
          await t.pumpWidget(const SizedBox());
          await settle(t, 2);
          look.dispose();
        }
      }
      t.view.reset();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      if (evidenceDir != null) await sheet(t, name, shots);
      expect(failures, isEmpty, reason: name);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }

  sweep('room', (s) async {});
  sweep('room-collapsed', (s) async {}, prefs: {'home_score_collapsed': true});
  sweep('room-no-profile', (s) async {}, withProfile: false);
  sweep('startup-wave', (s) async {}, loading: true);
  sweep('guest-entry', (s) async {}, guestEntry: true, withProfile: false);
  sweep('settings', (s) async {
    await s.t.tap(find.byTooltip('Settings'));
  });
  sweep('customize', (s) => s.tap('Customize'));
  sweep('history', (s) async {
    await s.t.tap(find.byTooltip('My history').first);
  });
  sweep('experiment', (s) async => s.routes.experiment(s.nav));
  sweep('ideas', (s) async => s.routes.ideas(s.nav, origin: 'Room'));
  sweep('today-plan', (s) async => s.routes.todayPlan(s.nav));
  sweep('weekly-checkin', (s) async => s.routes.weeklyCheckIn(s.nav).ignore(), guide: FakeWeeklyGuide());
  sweep('notebook', (s) async => s.routes.notebook(s.nav));
  sweep('reminders', (s) async => s.routes.reminders(s.nav));
  sweep('ai-privacy', (s) async => s.routes.aiPrivacy(s.nav));
  sweep('my-data', (s) async => s.routes.myData(s.nav));
  sweep('health-documents', (s) async => s.routes.healthDocuments(s.nav));
  sweep('still-learning', (s) async => s.routes.stillLearning(s.nav));
  sweep('what-i-see', (s) async => s.routes.wellness(s.nav));
  sweep('drivers', (s) async => s.routes.drivers(s.nav));
  sweep('band', (s) async => s.routes.bandFlow(s.nav));
  sweep('band-demo', (s) async {
    s.routes.bandFlow(s.nav);
    await settle(s.t);
    await s.tap('Try the demo band');
  });
  sweep('band-firmware', (s) async {
    s.routes.bandFlow(s.nav);
    await settle(s.t);
    await s.tap('Find my band');
    await s.tap('Pair');
  }, bandClient: FirmwareBand());
  sweep('band-bluetooth-off', (s) async {
    s.routes.bandFlow(s.nav);
    await settle(s.t);
    await s.tap('Find my band');
  }, bandClient: StubBandClient(state: BluetoothState.off));
  sweep('band-no-band', (s) async {
    s.routes.bandFlow(s.nav);
    await settle(s.t);
    await s.tap('Find my band');
  }, bandClient: StubBandClient());
  sweep('score-info', (s) async {
    await s.t.tap(find.byTooltip('About the health score').first);
  });
  sweep('daily-checkin', (s) async {
    await s.tap('Check in');
  });
  sweep('daily-checkin-typed', (s) async {
    await s.tap('Check in');
    await s.tap('Type instead');
    await s.t.enterText(find.byType(TextField).first, 'About 7 hours, slept fine');
    await s.t.testTextInput.receiveAction(TextInputAction.send);
  });
  sweep('weekly-checkin-readback', (s) async {
    s.routes.weeklyCheckIn(s.nav).ignore();
    await settle(s.t);
    await s.tap('Type instead');
    await s.t.enterText(find.byType(TextField).first, 'Walked most days, slept about 7 hours');
    await s.t.testTextInput.receiveAction(TextInputAction.send);
  }, guide: FakeWeeklyGuide());
  sweep('ideas-error', (s) async => s.routes.ideas(s.nav, origin: 'Room'), ideas: false);
  sweep('idea-detail', (s) async {
    await s.push(
      (c) => IdeaDetailScreen(
        idea: pace,
        appearance: const TwinAppearance(name: 'Mochi', look: TwinLook.calHat),
        onBack: () => Navigator.of(c).pop(),
        backLabel: 'Back to ideas',
        onTry: () {},
      ),
    );
  });
  sweep('experiment-better', (s) async {
    final exp = s.repo.experiment()!..set(LeverId.moderate, 300)..set(LeverId.sleepHours, 8);
    await s.push((c) => SideBySideScreen(repository: s.repo, whatIf: exp, appearance: const TwinAppearance(name: 'Mochi')));
  });
  sweep('experiment-worse', (s) async {
    final exp = s.repo.experiment()!..set(LeverId.moderate, 0)..set(LeverId.sitting, 720);
    await s.push((c) => SideBySideScreen(repository: s.repo, whatIf: exp, appearance: const TwinAppearance(name: 'Mochi')));
  });
  sweep('history-days', (s) async {
    final now = DateTime.now();
    await s.push(
      (c) => HistoryScreen(
        days: [
          for (var i = 0; i < 9; i++)
            WellnessDay(
              date: now.subtract(Duration(days: i)),
              values: [
                HistoryValue(label: 'Sleep', value: '${6 + i % 3} hours'),
                HistoryValue(label: 'Walking', value: '${20 + i * 5} minutes'),
              ],
            ),
        ],
        goodWeeks: 2,
        now: now,
        onBack: () => Navigator.of(c).pop(),
        onTalk: () {},
      ),
    );
  });
  sweep('erase-confirm', (s) async {
    s.routes.myData(s.nav);
    await settle(s.t);
    await s.tap('Delete my data');
  });
  sweep('erase-final', (s) async {
    s.routes.myData(s.nav);
    await settle(s.t);
    await s.tap('Delete my data');
    await s.tap('Delete everything');
  });
  sweep('customize-coming-soon', (s) async {
    await s.tap('Customize');
    await s.tap('Beanie');
  });
  sweep('pdf-consent', (s) async {
    final ocr = FakeOcr();
    await s.push(
      (c) => DocumentUploadScreen(
        service: DocumentUploadService(
          ocr: ocr,
          extractor: FakeText(),
          pdfPicker: ocr,
          pdfReader: FakePdfReader(claude, answer: found('claude')),
        ),
        onDone: (_) {},
      ),
    );
  });
  // The onboarding conversation, opened from Talk with no profile yet.
  Future<void> talk(Sweep s) async {
    await s.tap('Talk');
  }

  Future<void> consent(Sweep s, String voice) async {
    await talk(s);
    await s.tap(voice);
    await s.t.pump(const Duration(milliseconds: 700));
    await s.tap('Not now');
  }

  sweep('onboarding-consent', talk, withProfile: false);
  sweep('onboarding-question', (s) => consent(s, "Yes, I'll talk"), withProfile: false);
  sweep('onboarding-listening', (s) async {
    await consent(s, "Yes, I'll talk");
    s.input.captions = ['I am 70'];
    await s.tap('Talk or type');
  }, withProfile: false);
  sweep('onboarding-readback', (s) async {
    await consent(s, "Yes, I'll talk");
    s.input.captions = ['I am 70'];
    await s.tap('Talk or type');
    await s.t.tap(find.byType(TalkButton));
  }, withProfile: false);
  sweep('onboarding-typing', (s) => consent(s, "No, I'll type"), withProfile: false);
  sweep('onboarding-typed-readback', (s) async {
    await consent(s, "No, I'll type");
    await s.t.enterText(find.byType(TextField), '70');
    await s.tap('Send');
  }, withProfile: false);
  sweep('onboarding-mic-off', (s) async {
    await consent(s, "Yes, I'll talk");
    s.voice.turnMicOff();
  }, withProfile: false, handsFree: true);
  sweep('onboarding-done', (s) async {
    await consent(s, "No, I'll type");
    for (var i = 0; i < 20 && find.text('Continue').evaluate().isEmpty; i++) {
      if (find.text('Yes').evaluate().isNotEmpty) {
        await s.tap('Yes');
        continue;
      }
      final field = find.byType(TextField);
      if (field.evaluate().isEmpty) break;
      await s.t.enterText(field, '70');
      await s.tap('Send');
    }
  }, withProfile: false);
  sweep('answer-more', (s) async {}, profileData: {...profile}..remove('sleep_hours')..remove('sedentary_min_day'));
  sweep('answer-more-flow', (s) async => s.routes.answerMissing(s.nav).ignore(),
      profileData: {...profile}..remove('sleep_hours')..remove('sedentary_min_day'));
  sweep('change-answer', (s) async => s.routes.changeAnswer(s.nav));
}

/// A band that pairs but needs newer firmware to send its days.
class FirmwareBand extends StubBandClient {
  FirmwareBand() : super(devices: [const BandDevice(name: 'LifeTwin Band', strength: 3)]);
  @override
  Future<bool> pair(BandDevice device) async => throw bandFirmwareUpdateNeeded;
}
