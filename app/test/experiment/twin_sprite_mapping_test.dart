import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/twin_state.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/twin_pose_map.dart';
import 'package:lifesim/ui/widgets/twin_state_sprite.dart';

TwinState stateOf(TwinMood mood, TwinStateReason reason) => TwinState(mood: mood, pose: TwinPose.stand, reason: reason);

void main() {
  test('every mood and reason maps to one sprite pose', () {
    for (final mood in TwinMood.values) {
      for (final reason in TwinStateReason.values) {
        final expected = switch (mood) {
          TwinMood.concerned => TwinPose.concerned,
          TwinMood.sleepy => TwinPose.sleepy,
          TwinMood.curious => TwinPose.thinking,
          TwinMood.cozy => TwinPose.sit,
          TwinMood.content => reason == TwinStateReason.needsInput ? TwinPose.wave : TwinPose.stand,
          TwinMood.cheerful => reason == TwinStateReason.active ? TwinPose.jump : TwinPose.proud,
        };
        expect(poseForTwinState(stateOf(mood, reason)), expected, reason: '$mood / $reason');
      }
    }
  });

  test('the engine pose is ignored, and listening is never chosen', () {
    for (final mood in TwinMood.values) {
      for (final reason in TwinStateReason.values) {
        for (final enginePose in [TwinPose.stand, TwinPose.jump, TwinPose.think]) {
          final s = TwinState(mood: mood, pose: enginePose, reason: reason);
          expect(poseForTwinState(s), poseForTwinState(stateOf(mood, reason)));
          expect(poseForTwinState(s), isNot(TwinPose.listening));
          expect(poseForTwinState(s), isNot(TwinPose.dizzy)); // game health only
          expect(poseForTwinState(s), isNot(TwinPose.shrug)); // forecast unsupported only
        }
      }
    }
  });

  test('the sprites for every pose are bundled in all four versions', () {
    for (final type in TwinType.values) {
      for (final look in TwinLook.values) {
        for (final pose in TwinPose.values) {
          expect(twinSpriteSize1x[twinAsset(type, look, pose)], isNotNull, reason: '$type $look $pose');
        }
      }
    }
  });

  for (final type in TwinType.values) {
    for (final look in TwinLook.values) {
      testWidgets('${type.name} ${look.name}: every mood stands on the same baseline at one scale', (t) async {
        final appearance = TwinAppearance(type: type, look: look);
        final tops = <double>[];
        final scales = <double>[];
        for (final mood in TwinMood.values) {
          await t.pumpWidget(
            MaterialApp(
              home: Center(
                child: TwinStateSprite(
                  state: stateOf(mood, mood == TwinMood.cheerful ? TwinStateReason.active : TwinStateReason.steady),
                  appearance: appearance,
                  height: 200,
                ),
              ),
            ),
          );
          final pose = poseForTwinState(
            stateOf(mood, mood == TwinMood.cheerful ? TwinStateReason.active : TwinStateReason.steady),
          );
          final img = t.widget<Image>(find.byType(Image));
          expect((img.image as AssetImage).assetName, appearance.sprite(pose));
          final box = t.getRect(find.byType(Image));
          final native = type == TwinType.bear ? pose.bearNative : pose.humanNative;
          final feet = twinFeetAnchor(type, look, pose);
          tops.add(box.top + feet * box.height - t.getTopLeft(find.byType(TwinStateSprite)).dy);
          scales.add(box.height / native.height);
        }
        // Feet on one baseline, one scale for every pose.
        for (final y in tops) {
          expect(y, closeTo(tops.first, 0.01));
        }
        for (final s in scales) {
          expect(s, closeTo(scales.first, 1e-6));
        }
      });
    }
  }
}
