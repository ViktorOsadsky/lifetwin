import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'theme.dart';
import 'twin_appearance.dart';
import 'twin_assets.dart';
import 'widgets/twin_sprite.dart';

/// Mochi waving on lavender while the model and the phone's store open.
///
/// It matches the iOS launch screen (ios/Runner/Base.lproj/LaunchScreen.storyboard:
/// the same colour and the same 139×180 wave sprite), so the hand-off from the
/// native launch screen has no flash.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  /// The default look: the bear in the Cal hat (the saved look isn't read yet).
  static const mochi = TwinAppearance();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'LifeTwin is loading',
      child: const ColoredBox(
        color: LtColors.lavender,
        child: Center(
          child: TwinSprite(appearance: mochi, pose: TwinPose.wave, shadow: false, isRoom: false),
        ),
      ),
    );
  }
}

/// Keeps the native launch screen up until Mochi's wave sprite is decoded, so
/// the loading screen never shows lavender without Mochi. The first frame is
/// let through after [timeout] whatever happens.
void holdFirstFrameUntilMochi(WidgetsBinding binding, {Duration timeout = const Duration(seconds: 2)}) {
  binding.deferFirstFrame();
  var released = false;
  void release() {
    if (released) return;
    released = true;
    binding.allowFirstFrame();
  }

  final stream = AssetImage(LoadingScreen.mochi.sprite(TwinPose.wave)).resolve(
    ImageConfiguration(
      devicePixelRatio: binding.platformDispatcher.implicitView?.devicePixelRatio,
      platform: defaultTargetPlatform,
    ),
  );
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (_, _) {
      stream.removeListener(listener);
      release();
    },
    onError: (_, _) {
      stream.removeListener(listener);
      release();
    },
  );
  stream.addListener(listener);
  Timer(timeout, release);
}
