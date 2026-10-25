import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../twin/twin_state.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/lottie_burst.dart';
import '../ui/widgets/home_button.dart';
import '../ui/widgets/widgets.dart';
import 'widgets/widgets.dart';

/// The frame every Experiment screen shares (design Y): a scroll view with the dock and the back
/// button pinned. The back button floats over the content; once the page scrolls, a 76px
/// paper bar fades in and the button slides into it. Screens with a [title] have that bar
/// from the start (and a What-if pill when [whatIfPill]). Content is laid out with minimum
/// heights only, so large text grows instead of clipping.
class ExperimentPage extends StatefulWidget {
  const ExperimentPage({
    super.key,
    required this.body,
    required this.onBack,
    this.dock,
    this.title,
    this.whatIfPill = false,
    this.mode = LtMode.sun,
    this.backLabel = 'Back',
    this.onLeaveCheck,
  });

  final Widget body;
  final VoidCallback onBack;

  /// Pinned at the bottom (usually a [HonestyDock]).
  final Widget? dock;

  /// A title bar ("Experiment", "Side by side"); null for a plate window screen.
  final String? title;
  final bool whatIfPill;
  final LtMode mode;
  final String backLabel;

  /// For conversation screens: true while leaving would cut a talk short (Home asks first).
  final bool Function()? onLeaveCheck;

  @override
  State<ExperimentPage> createState() => _ExperimentPageState();
}

class _ExperimentPageState extends State<ExperimentPage> {
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final s = _scroll.hasClients && _scroll.offset > 0;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final titled = widget.title != null;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final d = reduced ? Duration.zero : const Duration(milliseconds: 200);
    final barOn = titled || _scrolled;
    return ModeScaffold(
      mode: widget.mode,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(14, titled ? 90 : 76 + 0, 14, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [widget.body]),
                ),
                // The bar: always there with a title; otherwise it fades in once scrolled.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 76,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: barOn ? 1 : 0,
                      duration: d,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: LtColors.paper,
                          border: Border(
                            bottom: BorderSide(
                              color: titled && !_scrolled ? Colors.transparent : LtColors.container,
                              width: LtBorders.container,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (titled)
                  Positioned(
                    left: HomeButton.shownFor(context) ? 150 : 82,
                    right: widget.whatIfPill ? 100 : 16,
                    top: 0,
                    height: 76,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        header: true,
                        child: Text(
                          widget.title!,
                          style: LtText.display(26),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                if (titled && widget.whatIfPill) const Positioned(right: 16, top: 22, child: ModePill.whatIf()),
                AnimatedPositioned(
                  duration: d,
                  curve: Curves.easeOut,
                  left: titled || _scrolled ? 16 : 30,
                  top: titled || _scrolled ? 12 : 50,
                  child: RoundBackButton(label: widget.backLabel, onTap: widget.onBack, onLeaveCheck: widget.onLeaveCheck),
                ),
              ],
            ),
          ),
          if (widget.dock != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
              child: SingleChildScrollView(child: widget.dock),
            ),
        ],
      ),
    );
  }
}

/// One twin standing in a plate window: its state, where across the window it stands, and
/// whether a lilac halo blooms behind it (the what-if twin).
class TwinSlot {
  const TwinSlot({required this.state, required this.x, this.halo = false, this.height = 196, this.pose, this.hop});
  final TwinState state;

  /// Where the feet are across the window, 0 to 1.
  final double x;
  final bool halo;
  final double height;

  /// A pose of its own (an idea's), instead of the one the state picks.
  final TwinPose? pose;

  /// Lifts the twin by this many logical pixels (negative is up) while it plays; null: still.
  final Animation<double>? hop;
}

/// A plate window (233 high) with the `{ Name }` banner, [twins] standing on the meadow, and
/// an [overlay] (pills, speech bubble). The back button is the page's, not the window's.
class ExperimentPlate extends StatelessWidget {
  const ExperimentPlate({
    super.key,
    required this.appearance,
    required this.twins,
    this.overlay,
    this.bubble,
    this.divider = false,
  });

  final TwinAppearance appearance;
  final List<TwinSlot> twins;
  final Widget? overlay;

  /// Mochi's words, in a speech bubble on the right.
  final String? bubble;

  /// A dashed line between two twins.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 233 + PlateWindow.bannerOverhang,
      child: PlateWindow(
        name: appearance.name,
        plate: PlateScene(
          asset: ScenePlate.room.asset,
          focus: const Offset(0.5, 0.554),
          focusTarget: Offset(twins.length > 1 ? 0.5 : 0.3, 0.88),
          zoom: 1.38,
          twinBuilder: (feet, scale, box) => Stack(
            children: [
              if (divider)
                Positioned(left: box.width / 2 - 1, top: 36, bottom: 24, width: 2, child: const _DashedLine()),
              for (final t in twins)
                () {
                  final h = math.max(60.0, math.min(t.height, box.height * 0.84));
                  final left = box.width * t.x - h / 2;
                  final top = feet.dy - h * twinFeetAnchor(appearance.type, appearance.look);
                  return Positioned(
                    left: left,
                    top: top,
                    width: h,
                    height: h,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (t.halo)
                          Positioned(
                            left: -h * 0.1,
                            top: h * 0.0,
                            width: h * 1.2,
                            height: h * 1.2,
                            child: const LottieBurst.whatIfAppear(),
                          ),
                        if (t.hop == null)
                          TwinStateSprite(state: t.state, appearance: appearance, height: h, pose: t.pose)
                        else
                          AnimatedBuilder(
                            animation: t.hop!,
                            builder: (_, child) => Transform.translate(offset: Offset(0, t.hop!.value), child: child),
                            child: TwinStateSprite(state: t.state, appearance: appearance, height: h, pose: t.pose),
                          ),
                      ],
                    ),
                  );
                }(),
            ],
          ),
        ),
        overlay: LayoutBuilder(
          builder: (context, box) => Stack(
            clipBehavior: Clip.none, // the voice pill hangs over the bottom edge
            children: [
              ?overlay,
              if (bubble != null)
                Positioned(
                  right: 6,
                  top: 119,
                  width: math.min(170, box.maxWidth * 0.5),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Bubble(text: bubble!, tail: BubbleTail.left, fontSize: 19),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _DashedLinePainter());
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = LtColors.container
      ..strokeWidth = 1.5;
    for (var y = 0.0; y < size.height; y += 10) {
      canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, math.min(y + 5, size.height)), p);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => false;
}
