import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui/swoosh_route.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart';

/// V-1 / V-7 Room: the calm island plate with the chosen twin composited on
/// it, a greeting bubble, the mood chip, and the dock (Customize · Talk ·
/// Fortune). This is the approved static 2D design.
class RoomScreen extends StatelessWidget {
  const RoomScreen({
    super.key,
    required this.appearance,
    required this.onTalk,
    required this.onCustomize,
    required this.onFortune,
    this.mood = 'Feeling cozy',
  });

  /// Cosmetic look only; never part of the health profile.
  final ValueListenable<TwinAppearance> appearance;
  final VoidCallback onTalk;
  final VoidCallback onCustomize;
  final VoidCallback onFortune;
  final String mood;

  @override
  Widget build(BuildContext context) {
    return SwooshRoomStage(
      builder: (context, f) => ModeScaffold(
        mode: LtMode.room,
        gradient: Gradient.lerp(LtMode.room.gradient, LtMode.onboarding.gradient, f.tint),
        child: ValueListenableBuilder<TwinAppearance>(
          valueListenable: appearance,
          builder: (context, look, _) => PlateSheetLayout(
            minWindow: 220,
            overlap: 24,
            window: PlateWindow(
              name: look.name,
              // TODO(tier-1): room rendering approach pending owner ruling.
              // The options (pre-rendered room + sprite actors, Flame
              // isometric, flutter_scene 3D, three.js WebView) are listed in
              // docs/design/painted-card-direction.md. A future room engine
              // replaces this PlateScene; the frame, bubble, chip and dock
              // stay as they are.
              plate: PlateScene(
                asset: ScenePlate.room.asset,
                focus: const Offset(0.5, 0.554),
                focusTarget: const Offset(0.496, 0.62),
                zoom: 1.11,
                twinBuilder: (feet, scale, box) => plantTwin(
                  feet,
                  TwinSprite(appearance: look, height: math.max(60.0, math.min(253 * scale, box.height * 0.8)), hero: true, isRoom: true),
                ),
              ),
              overlay: _RoomOverlay(frame: f, mood: mood),
            ),
            sheet: Opacity(
              opacity: f.barOpacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, f.barOffsetY),
                child: _Dock(frame: f, onTalk: onTalk, onCustomize: onCustomize, onFortune: onFortune),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomOverlay extends StatelessWidget {
  const _RoomOverlay({required this.frame, required this.mood});
  final SwooshRoomFrame frame;
  final String mood;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 24,
          right: 8,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Opacity(
              opacity: frame.bubbleOpacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: frame.bubbleScale,
                alignment: Alignment.bottomLeft,
                child: const Bubble(text: 'Hi! Want to chat?', fontSize: 21, tail: BubbleTail.bottom, tailAt: 0),
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          bottom: 38,
          child: Opacity(
            opacity: frame.chipOpacity.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, frame.chipOffsetY),
              child: Transform.rotate(angle: -3 * math.pi / 180, child: StatusPill(label: mood)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.frame, required this.onTalk, required this.onCustomize, required this.onFortune});
  final SwooshRoomFrame frame;
  final VoidCallback onTalk;
  final VoidCallback onCustomize;
  final VoidCallback onFortune;

  @override
  Widget build(BuildContext context) {
    return Sheet(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: _DockItem(
              label: 'Customize',
              icon: Icons.checkroom_rounded,
              face: LtColors.peach,
              lip: LtColors.peachLip,
              iconColor: LtColors.ink,
              onTap: onCustomize,
            ),
          ),
          Flexible(
            flex: 2,
            child: Transform.scale(
              scale: frame.talkScale,
              child: LipButton(
                label: 'Talk',
                icon: Icons.mic_none_rounded,
                height: 72,
                fontSize: 26,
                expand: false,
                hint: 'Chat with your twin',
                onTap: onTalk,
              ),
            ),
          ),
          Flexible(
            child: _DockItem(
              label: 'Fortune',
              icon: Icons.auto_awesome_rounded,
              face: LtColors.night,
              lip: const Color(0xFF0F1430),
              iconColor: LtColors.gold,
              onTap: onFortune,
            ),
          ),
        ],
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.label,
    required this.icon,
    required this.face,
    required this.lip,
    required this.iconColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color face;
  final Color lip;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 88, minHeight: 96),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: face,
                  shape: BoxShape.circle,
                  border: Border.all(color: LtColors.control, width: LtBorders.control),
                  boxShadow: [BoxShadow(color: lip, offset: const Offset(0, 3)), ...LtShadows.soft],
                ),
                child: Icon(icon, size: 30, color: iconColor),
              ),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, style: LtText.body(weight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
