import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/customize/customize_screen.dart';
import 'package:lifesim/forecast/fortune_ceremony_screen.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lottie/lottie.dart';

void setPhone(WidgetTester t) {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  test('a twin without the hat uses its own no-hat poses, never the standing fallback', () {
    for (final type in TwinType.values) {
      for (final pose in TwinPose.values) {
        final plain = twinAsset(type, TwinLook.plain, pose), hat = twinAsset(type, TwinLook.calHat, pose);
        expect(plain, 'assets/twin/${type.name}/pose_nohat/${pose.slug}.png');
        expect(hat, 'assets/twin/${type.name}/pose/${pose.slug}.png');
        expect(twinHasPose(type, TwinLook.plain, pose), isTrue);
        // The pair shares one canvas: the body never moves or rescales when the hat comes off.
        expect(twinSpriteSize1x[plain], twinSpriteSize1x[hat]);
        expect(twinFeetAnchor(type, TwinLook.plain, pose), twinFeetAnchor(type, TwinLook.calHat, pose));
      }
    }
  });

  test('the Stanford hat has its own poses on the same canvas as the Cal hat', () {
    for (final type in TwinType.values) {
      for (final pose in TwinPose.values) {
        final stanford = twinAsset(type, TwinLook.stanfordHat, pose), cal = twinAsset(type, TwinLook.calHat, pose);
        expect(stanford, 'assets/twin/${type.name}/pose_stanford/${pose.slug}.png');
        expect(twinSpriteSize1x[stanford], twinSpriteSize1x[cal]);
        expect(twinFeetAnchor(type, TwinLook.stanfordHat, pose), twinFeetAnchor(type, TwinLook.calHat, pose));
      }
    }
    expect(twinDescription(TwinType.bear, TwinLook.stanfordHat), 'Your bear twin in the Stanford hat');
  });

  testWidgets('every sprite the code names is bundled and matches the manifest', (t) async {
    final manifest = await t.runAsync(() => rootBundle.loadString('assets/twin/manifest.json'));
    final entries = {
      for (final e in (jsonDecode(manifest!) as Map<String, dynamic>)['twin'] as List) (e as Map)['path']: e,
    };
    for (final type in TwinType.values) {
      for (final look in TwinLook.values) {
        for (final pose in TwinPose.values) {
          final path = twinAsset(type, look, pose);
          final e = entries[path];
          expect(e, isNotNull, reason: path);
          final size = e!['size1x'] as Map;
          expect(Size((size['w'] as num).toDouble(), (size['h'] as num).toDouble()), twinSpriteSize1x[path], reason: path);
          expect((e['anchor'] as Map)['y'], closeTo(twinFeetAnchor(type, look, pose), 1e-4), reason: path);
          final bytes = await t.runAsync(() => rootBundle.load(path));
          expect(bytes!.lengthInBytes, greaterThan(1000), reason: path);
        }
      }
    }
  });

  testWidgets('Customize: choosing no hat shows the no-hat standing sprite', (t) async {
    setPhone(t);
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(MaterialApp(home: CustomizeScreen(appearance: look, onDone: () {})));
    await t.tap(find.text('No hat'));
    await t.pump();
    final sprite = t.widget<TwinSprite>(find.byType(TwinSprite));
    expect(sprite.appearance.sprite(sprite.pose), 'assets/twin/bear/pose_nohat/stand.png');
  });

  testWidgets('Customize: choosing the Stanford hat shows it and Save look keeps it', (t) async {
    setPhone(t);
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(MaterialApp(home: CustomizeScreen(appearance: look, onDone: () {})));
    await t.tap(find.text('Stanford hat'));
    await t.pump();
    final sprite = t.widget<TwinSprite>(find.byType(TwinSprite));
    expect(sprite.appearance.sprite(sprite.pose), 'assets/twin/bear/pose_stanford/stand.png');
    await t.ensureVisible(find.text('Save look'));
    await t.tap(find.text('Save look'));
    await t.pump();
    expect(look.value.look, TwinLook.stanfordHat);
    final hat = await t.runAsync(() => rootBundle.load(stanfordHatAsset));
    expect(hat!.lengthInBytes, greaterThan(1000));
  });

  testWidgets('the Lottie files load', (t) async {
    for (final name in ['ball_glow', 'bear_celebrate', 'bear_idle', 'bear_walk', 'bear_wave', 'human_idle']) {
      final c = await t.runAsync(() => AssetLottie('assets/lottie/$name.json').load());
      expect(c, isNotNull, reason: name);
      expect(c!.duration, greaterThan(Duration.zero), reason: name);
      expect(c.bounds.width, 512, reason: name);
    }
  });

  Future<LottieBuilder> pumpCeremony(WidgetTester t, {required bool reduced}) async {
    setPhone(t);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: const Size(390, 844), disableAnimations: reduced),
          child: FortuneCeremonyScreen(onAsk: () {}, onBack: () {}),
        ),
      ),
    );
    await t.pump();
    return t.widget<LottieBuilder>(
      find.descendant(of: find.byKey(const ValueKey('ball-glow-lottie')), matching: find.byType(LottieBuilder)),
    );
  }

  testWidgets('the ceremony plays ball_glow behind the ball on its own controller, resting at frame 0', (t) async {
    final lottie = await pumpCeremony(t, reduced: false);
    expect((lottie.lottie as AssetLottie).assetName, ballGlowLottie);
    expect(lottie.controller, isNotNull);
    expect(lottie.controller!.value, 0);
    await t.pumpAndSettle(); // nothing loops on its own
  });

  testWidgets('reduced motion: the ball glow shows frame 0, not animated', (t) async {
    final lottie = await pumpCeremony(t, reduced: true);
    expect(lottie.animate, isFalse);
    expect(lottie.controller, isNull);
    // Once the composition is in, the painted Lottie is still at its first frame.
    await t.runAsync(() => AssetLottie(ballGlowLottie).load());
    await t.pump();
    final inner = find.descendant(of: find.byKey(const ValueKey('ball-glow-lottie')), matching: find.byType(Lottie));
    if (inner.evaluate().isNotEmpty) {
      final w = t.widget<Lottie>(inner);
      expect(w.animate, isFalse);
      expect(w.controller, isNull);
    }
    await t.pumpAndSettle();
  });
}
