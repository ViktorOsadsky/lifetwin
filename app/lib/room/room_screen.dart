import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../forecast/forecast_client.dart';
import '../ui/swoosh_route.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import 'room_layout_data.dart';
import 'room_scene.dart';
import 'room_sim.dart';

/// V-1 / V-7 Room. Owner ruling (2026-10-24, Tier-1): the room is a
/// pre-rendered room plus sprite actors. [RoomScene] draws the layers
/// rendered from the approved three.js prototype with the chosen twin
/// between them; [RoomSim] runs the behaviours. Flame is the upgrade path:
/// it would replace [RoomScene] (and its `FloorProjector`) only.
///
/// Around the room: the `{ Name }` banner and the outlook card at the top;
/// the status line, the activity row (Exercise · Eat · Sleep) and the dock
/// (Customize · Talk · Fortune) at the bottom.
class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.appearance,
    required this.onTalk,
    required this.onCustomize,
    required this.onFortune,
    this.outlook,
  });

  /// Cosmetic look only; never part of the health profile.
  final ValueListenable<TwinAppearance> appearance;
  final VoidCallback onTalk;
  final VoidCallback onCustomize;

  /// Opens the fortune ceremony; completes when the person is back.
  final Future<void> Function() onFortune;

  /// The last real forecast, if any. Nothing is shown that it doesn't hold.
  final ValueListenable<Forecast?>? outlook;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final RoomSim _sim = RoomSim(layout: roomLayout)..onFortune = _openFortune;

  Future<void> _openFortune() async {
    await widget.onFortune();
    if (mounted) _sim.fortuneDone();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sim.reduced = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    _sim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SwooshRoomStage(
      builder: (context, f) => Scaffold(
        backgroundColor: const Color(0xFFEFE6F4),
        body: Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<TwinAppearance>(
                valueListenable: widget.appearance,
                builder: (context, look, _) => RoomScene(sim: _sim, appearance: look),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(
                      banner: ValueListenableBuilder<TwinAppearance>(
                        valueListenable: widget.appearance,
                        builder: (context, look, _) => NameBanner(name: look.name),
                      ),
                      card: _OutlookCard(outlook: widget.outlook, onTap: () => _sim.press(RoomAction.fortune)),
                    ),
                    const Spacer(),
                    Opacity(
                      opacity: f.barOpacity.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, f.barOffsetY),
                        child: ListenableBuilder(
                          listenable: _sim,
                          builder: (context, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: StatusPill(label: _sim.status, icon: Icons.circle),
                              ),
                              const SizedBox(height: 10),
                              _ActivityRow(sim: _sim),
                              const SizedBox(height: 10),
                              _Dock(
                                frame: f,
                                onTalk: widget.onTalk,
                                onCustomize: widget.onCustomize,
                                onFortune: () => _sim.press(RoomAction.fortune),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The banner and the outlook card side by side, stacked when the screen is
/// narrow or the text is large (so nothing wraps letter by letter).
class _TopBar extends StatelessWidget {
  const _TopBar({required this.banner, required this.card});
  final Widget banner;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final big = MediaQuery.textScalerOf(context).scale(17) > 17 * 1.15;
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 340 && !big
          ? Row(children: [banner, const SizedBox(width: 10), Expanded(child: card)])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Align(alignment: Alignment.centerLeft, child: banner), const SizedBox(height: 8), card],
            ),
    );
  }
}

/// "Your 5-yr look": the real number when there is a forecast, otherwise an
/// invitation. Never an invented number.
class _OutlookCard extends StatelessWidget {
  const _OutlookCard({required this.outlook, required this.onTap});
  final ValueListenable<Forecast?>? outlook;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final source = outlook;
    if (source == null) return _card(null);
    return ValueListenableBuilder<Forecast?>(valueListenable: source, builder: (context, f, _) => _card(f));
  }

  Widget _card(Forecast? f) {
    final has = f != null && f.supported;
    final years = has ? f.maxHorizonYears : 5;
    final line = has ? 'about ${f.outOf100(years)} in 100' : 'Ask the ball';
    return Semantics(
      button: true,
      label: 'Your $years-year look: $line',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(
            color: LtColors.paper,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: LtColors.container, width: LtBorders.container),
            boxShadow: LtShadows.soft,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: has
                    ? BearHeadArray(
                        filled: f.outOf100(years),
                        filledColor: LtColors.ink,
                        emptyColor: LtColors.container,
                      )
                    : const Icon(Icons.auto_awesome_rounded, color: LtColors.ink, size: 28),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Your $years-yr look', style: LtText.body()),
                    Text(line, style: LtText.display(19)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Exercise · Eat · Sleep: compact toggles above the dock.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.sim});
  final RoomSim sim;

  @override
  Widget build(BuildContext context) {
    Widget item(RoomAction a, String label, IconData icon) {
      final on = sim.action == a;
      return Expanded(
        child: Semantics(
          button: true,
          toggled: on,
          label: label,
          excludeSemantics: true,
          onTap: () => sim.press(a),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => sim.press(a),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: on ? LtColors.mint : LtColors.paper,
                borderRadius: BorderRadius.circular(LtRadii.chip),
                border: Border.all(color: on ? LtColors.controlOnMint : LtColors.control, width: LtBorders.control),
                boxShadow: LtShadows.small,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: LtColors.ink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label, style: LtText.body(weight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        item(RoomAction.exercise, 'Exercise', Icons.fitness_center_rounded),
        const SizedBox(width: 8),
        item(RoomAction.eat, 'Eat', Icons.restaurant_rounded),
        const SizedBox(width: 8),
        item(RoomAction.sleep, 'Sleep', Icons.bedtime_rounded),
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
                  boxShadow: [
                    BoxShadow(color: lip, offset: const Offset(0, 3)),
                    ...LtShadows.soft,
                  ],
                ),
                child: Icon(icon, size: 30, color: iconColor),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: LtText.body(weight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
