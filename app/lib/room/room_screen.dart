import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../checkin/check_in_entry.dart';
import '../experiment/room_pills.dart';
import '../twin/twin_model.dart' show TwinAssessment, extrapolationCaveat;
import '../forecast/forecast_client.dart';
import '../wellness/home_panel.dart';
import '../wellness/models.dart';
import '../ui/swoosh_route.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';
import '../widgets/whole_word_text.dart';
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
/// (Customize · Talk · Fortune) at the bottom. The room is told how much
/// the UI covers, so on short screens it slides up and keeps the mat clear.
class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.appearance,
    required this.onTalk,
    required this.onCustomize,
    required this.onFortune,
    this.outlook,
    this.hasProfile = false,
    this.wellness,
    this.onQuiz,
    this.onHistory,
    this.extraPills = const [],
    this.onDrivers,
    this.onSettings,
    this.onBand,
    this.today,
    this.stateLine,
  });

  /// Cosmetic look only; never part of the health profile.
  final ValueListenable<TwinAppearance> appearance;
  final VoidCallback onTalk;
  final VoidCallback onCustomize;

  /// Opens the fortune ceremony; completes when the person is back.
  final Future<void> Function() onFortune;

  /// The last real forecast, if any. Nothing is shown that it doesn't hold.
  final ValueListenable<Forecast?>? outlook;

  /// True once an intake has been confirmed (and is still complete) this session. Without
  /// it the fortune does not open: the twin asks to talk first.
  final bool hasProfile;

  /// Health score from the twin repository (the model's number as is).
  final WellnessSnapshot? wellness;
  final VoidCallback? onQuiz;
  final VoidCallback? onHistory;
  /// More pills beside the status line (`roomPills`).
  final List<Widget> extraPills;

  /// The pinned Settings icon in the header (Apple Health, documents, privacy and the rest live there).
  final VoidCallback? onSettings;

  /// The pinned "Add band" icon in the header (the wristband flow).
  final VoidCallback? onBand;

  /// Home's one "Today with Mochi" slot, under the check-in button.
  final Widget? today;

  /// A small state line on the score card ("Still learning 2").
  final String? stateLine;

  /// "What moves it" on the Home card.
  final VoidCallback? onDrivers;

  static const talkFirst = "Let's talk first, so I can make your forecast.";

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late final RoomSim _sim = RoomSim(layout: roomLayout)..onFortune = _openFortune;
  final _topKey = GlobalKey();
  final _bottomKey = GlobalKey();
  EdgeInsets _clear = EdgeInsets.zero;
  bool _measuring = false;

  @override
  void initState() {
    super.initState();
    _measureSoon();
  }

  /// After layout, read how tall the top bar and the bottom UI are (their
  /// laid-out sizes, so the swoosh's slide does not move the room).
  void _measureSoon() {
    if (_measuring) return;
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      if (!mounted) return;
      final top = _topKey.currentContext?.size?.height;
      final bottom = _bottomKey.currentContext?.size?.height;
      if (top == null || bottom == null) return;
      final pad = MediaQuery.paddingOf(context);
      final clear = EdgeInsets.only(top: pad.top + 8 + top, bottom: pad.bottom + 12 + bottom);
      if ((clear.top - _clear.top).abs() > 0.5 || (clear.bottom - _clear.bottom).abs() > 0.5) {
        setState(() => _clear = clear);
      }
    });
  }

  /// Shown after Fortune (or the outlook card) is pressed before there is a profile.
  bool _needTalk = false;

  Future<void> _openFortune() async {
    await widget.onFortune();
    if (mounted) _sim.fortuneDone();
  }

  /// A second press of the same action within 0.7 s (a double tap, a tremor) is ignored:
  /// pressing an action again stops it, so a double tap would undo the first tap.
  Timer? _pressLock;
  RoomAction? _lastPress;

  void _press(RoomAction a) {
    if (_lastPress == a && (_pressLock?.isActive ?? false)) return;
    _lastPress = a;
    _pressLock?.cancel();
    _pressLock = Timer(const Duration(milliseconds: 700), () {});
    _sim.press(a);
  }

  /// Fortune and the outlook card: with no finished conversation nothing opens and the
  /// twin says why, as on main.
  void _fortune() {
    if (widget.hasProfile) {
      _press(RoomAction.fortune);
    } else {
      setState(() => _needTalk = true);
    }
  }

  @override
  void didUpdateWidget(RoomScreen old) {
    super.didUpdateWidget(old);
    if (widget.hasProfile && _needTalk) _needTalk = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sim.reduced = MediaQuery.disableAnimationsOf(context);
    _measureSoon();
  }

  @override
  void dispose() {
    _pressLock?.cancel();
    _sim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SwooshRoomStage(
      builder: (context, f) => Scaffold(
        backgroundColor: const Color(0xFFEFE6F4),
        body: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            _measureSoon();
            return true;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<TwinAppearance>(
                  valueListenable: widget.appearance,
                  builder: (context, look, _) => RoomTwinState(
                    builder: (state) => RoomScene(sim: _sim, appearance: look, clear: _clear, twinState: state),
                  ),
                ),
              ),
              SafeArea(
                // With very large text the top bar and the buttons can be taller than the
                // screen: then they scroll. Taps between them still reach the room.
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    hitTestBehavior: HitTestBehavior.deferToChild,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: (box.maxHeight - 20).clamp(0.0, double.infinity)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TopBar(
                            key: _topKey,
                            banner: ValueListenableBuilder<TwinAppearance>(
                              valueListenable: widget.appearance,
                              builder: (context, look, _) => NameBanner(name: look.name),
                            ),
                            actions: [
                              if (widget.onBand != null)
                                _HeaderIcon(icon: Icons.directions_walk_rounded, label: 'Add band', onTap: widget.onBand!),
                              if (widget.onHistory != null)
                                _HeaderIcon(icon: Icons.history_rounded, label: 'My history', onTap: widget.onHistory!),
                              if (widget.onSettings != null)
                                _HeaderIcon(icon: Icons.settings_outlined, label: 'Settings', onTap: widget.onSettings!),
                            ],
                            card: widget.wellness == null ? _OutlookCard(outlook: widget.outlook, onTap: _fortune) : HomeWellnessPanel(
                              snapshot: widget.wellness!, compact: true, onEstimate: _fortune, onDrivers: widget.onDrivers, stateLine: widget.stateLine,
                            ),
                          ),
                          Opacity(
                            opacity: f.barOpacity.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(0, f.barOffsetY),
                              child: ListenableBuilder(
                                listenable: _sim,
                                builder: (context, _) => SizeChangedLayoutNotifier(
                                  child: Column(
                                    key: _bottomKey,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const CheckInEntry(),
                                      if (_needTalk && !widget.hasProfile) ...[
                                        const Bubble(
                                          text: RoomScreen.talkFirst,
                                          fontSize: 21,
                                          tail: BubbleTail.none,
                                          liveRegion: true,
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      if (widget.today != null) ...[widget.today!, const SizedBox(height: 10)],
                                      if (widget.extraPills.isNotEmpty) ...[
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: widget.extraPills,
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      _ActivityRow(sim: _sim, press: _press),
                                      const SizedBox(height: 10),
                                      _Dock(
                                        frame: f,
                                        onTalk: widget.onTalk,
                                        onCustomize: widget.onCustomize,
                                        onFortune: _fortune,
                                        onQuiz: widget.onQuiz,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pinned icon in the header: 48 pt target.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    icon: Icon(icon, color: LtColors.ink, size: 28),
  );
}

/// The banner and the outlook card side by side, stacked when the screen is
/// narrow or the text is large (so nothing wraps letter by letter).
class _TopBar extends StatelessWidget {
  const _TopBar({super.key, required this.banner, required this.card, this.actions = const []});
  final Widget banner;
  final List<Widget> actions;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    final big = MediaQuery.textScalerOf(context).scale(17) > 17 * 1.15;
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 340 && !big && card is! HomeWellnessPanel
          ? Row(
              children: [
                banner,
                const SizedBox(width: 10),
                Expanded(child: card),
                ...actions,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Align(alignment: Alignment.centerLeft, child: banner)),
                    ...actions,
                  ],
                ),
                const SizedBox(height: 8),
                card,
              ],
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
    final card = Semantics(
      button: true,
      label: 'Your $years-year look: $line${has ? '. ${TwinAssessment.survivalTitle}' : ''}',
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
                    WholeWordText('Your $years-yr look', style: LtText.body()),
                    WholeWordText(line, style: LtText.display(19)),
                    if (has) WholeWordText(TwinAssessment.survivalTitle, style: LtText.body(size: 15)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Age 30-34 or 80-85: a Rough guide badge beside the number, opening the engine's caveat.
    if (!has || !f.extrapolated) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [card, RoughGuideBadge(caveat: extrapolationCaveat)],
    );
  }
}

/// The width [text] needs on one line at the current text scale.
double _labelWidth(BuildContext context, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final w = tp.width.ceilToDouble();
  tp.dispose();
  return w;
}

/// How far a 17 px label may scale down before it would drop under 15 px.
double _labelFloor(BuildContext context) => math.min(1, 15 / MediaQuery.textScalerOf(context).scale(17));

/// A button label on one line, never broken inside a word. The slots are
/// sized to fit it; if one still is not wide enough, it scales down a
/// little instead of wrapping.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text, {required this.style});
  final String text;
  final TextStyle style;

  // Unbounded width inside the FittedBox, so the text never wraps; it only shrinks.
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: WholeWordText(text, maxLines: 1, softWrap: false, style: style),
  );
}

/// Exercise · Eat · Sleep: compact toggles above the dock. Each gets the
/// width its label needs, and the spare width is shared out evenly.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.sim, required this.press});
  final RoomSim sim;
  final void Function(RoomAction) press;

  static const _items = [
    (RoomAction.exercise, 'Exercise', Icons.fitness_center_rounded),
    (RoomAction.eat, 'Eat', Icons.restaurant_rounded),
    (RoomAction.sleep, 'Sleep', Icons.bedtime_rounded),
  ];
  static const _gap = 8.0, _padX = 6.0, _icon = 24.0, _iconGap = 4.0;

  @override
  Widget build(BuildContext context) {
    final style = LtText.body(weight: FontWeight.w700);
    Widget item(RoomAction a, String label, IconData icon, bool showIcon) {
      final on = sim.action == a;
      return Semantics(
        button: true,
        toggled: on,
        label: label,
        excludeSemantics: true,
        onTap: () => press(a),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => press(a),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: _padX, vertical: 6),
            decoration: BoxDecoration(
              color: on ? LtColors.mint : LtColors.paper,
              borderRadius: BorderRadius.circular(LtRadii.chip),
              border: Border.all(color: on ? LtColors.controlOnMint : LtColors.control, width: LtBorders.control),
              boxShadow: LtShadows.small,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showIcon) ...[Icon(icon, size: _icon, color: LtColors.ink), const SizedBox(width: _iconGap)],
                Flexible(child: _OneLine(label, style: style)),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        final labels = [for (final (_, label, _) in _items) _labelWidth(context, label, style)];
        final avail = box.maxWidth - _gap * (_items.length - 1);
        // Slot widths for the labels plus [extra] each; spare width shared evenly.
        List<double> slots(double extra) {
          final need = [for (final l in labels) l + extra];
          final total = need.fold(0.0, (a, b) => a + b);
          return [
            for (final n in need)
              (total <= avail ? n + (avail - total) / need.length : n * avail / total).floorToDouble(),
          ];
        }

        const box0 = _padX * 2 + LtBorders.control * 2;
        var showIcon = true;
        var widths = slots(box0 + _icon + _iconGap);
        // Below the 15 px floor with icons? Drop the icons to widen the labels.
        final floor = _labelFloor(context);
        for (var i = 0; i < labels.length; i++) {
          if ((widths[i] - box0 - _icon - _iconGap) / labels[i] < floor) {
            showIcon = false;
            widths = slots(box0);
            break;
          }
        }
        return Row(
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              SizedBox(width: widths[i], child: item(_items[i].$1, _items[i].$2, _items[i].$3, showIcon)),
            ],
          ],
        );
      },
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.frame, required this.onTalk, required this.onCustomize, required this.onFortune, this.onQuiz});
  final VoidCallback? onQuiz;
  final SwooshRoomFrame frame;
  final VoidCallback onTalk;
  final VoidCallback onCustomize;
  final VoidCallback onFortune;

  @override
  Widget build(BuildContext context) {
    // Talk keeps the width it needs (padding, icon, gap, label, borders);
    // Customize and Fortune share the rest, so their labels stay on one line.
    final talkW = 40 + 32 + 10 + _labelWidth(context, 'Talk', LtText.display(26)) + LtBorders.control * 2 + 4;
    return Sheet(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
      child: LayoutBuilder(
        builder: (context, box) {
          // Never squeeze Customize or Fortune under the 15 px floor: Talk gives way first.
          final body = LtText.body(weight: FontWeight.w700);
          final side = math.max(_labelWidth(context, 'Customize', body), _labelWidth(context, 'Fortune', body));
          final talk = math.max(120.0, math.min(talkW, box.maxWidth - 2 * side * _labelFloor(context)));
          return Row(
            children: [
              Expanded(
                child: _DockItem(
                  label: 'Customize',
                  icon: Icons.checkroom_rounded,
                  face: LtColors.peach,
                  lip: LtColors.peachLip,
                  iconColor: LtColors.ink,
                  onTap: onCustomize,
                ),
              ),
              SizedBox(
                width: math.min(talk, box.maxWidth * 0.5),
                // Scaled down whole (never wrapped) if its slot is narrower.
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: IntrinsicWidth(
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
                  ),
                ),
              ),
              Expanded(
                child: _DockItem(
                  label: onQuiz == null ? 'Fortune' : 'Quiz',
                  icon: onQuiz == null ? Icons.auto_awesome_rounded : Icons.quiz_outlined,
                  face: LtColors.night,
                  lip: const Color(0xFF0F1430),
                  iconColor: LtColors.gold,
                  onTap: onQuiz ?? onFortune,
                ),
              ),
            ],
          );
        },
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
              _OneLine(label, style: LtText.body(weight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

