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
    this.onExperiment,
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

  /// "Experiment with your twin": the big primary button in the bottom section.
  final VoidCallback? onExperiment;
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

  /// The activity pill's chooser: "What should Mochi do?" Walk (let it roam), Exercise, Eat, Sleep. Each
  /// goes through the same [_press] path the old row used, so the bed tuck, climb and get-up are unchanged.
  Future<void> _chooseActivity() async {
    final current = _sim.inBed
        ? RoomAction.sleep
        : (_sim.action == RoomAction.fortune ? null : _sim.action);
    final picked = await showModalBottomSheet<RoomAction?>(
      context: context,
      useSafeArea: true,
      builder: (c) => _ActivityChooser(current: current, onPick: (a) => Navigator.of(c).pop(a), onWalk: () => Navigator.of(c).pop(null)),
    );
    if (!mounted) return;
    if (picked != null) {
      if (_sim.action != picked) _press(picked);
    } else if (_sim.action != null && _sim.action != RoomAction.fortune) {
      _press(_sim.action!); // Walk: stop what it is doing; Mochi roams again
    }
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
                    builder: (state) => RoomScene(
                      sim: _sim,
                      appearance: look,
                      clear: _clear,
                      twinState: state,
                      onActivityTap: _chooseActivity,
                    ),
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
                            quiz: widget.onQuiz == null ? null : _QuizChip(onTap: widget.onQuiz!),
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
                                      // With the Today row, Check in lives inside it (compact); otherwise its own bar.
                                      if (widget.today == null) const CheckInEntry(),
                                      if (_needTalk && !widget.hasProfile) ...[
                                        const Bubble(
                                          text: RoomScreen.talkFirst,
                                          fontSize: 21,
                                          tail: BubbleTail.none,
                                          liveRegion: true,
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      if (widget.today != null) ...[widget.today!, const SizedBox(height: 6)],
                                      if (widget.extraPills.isNotEmpty) ...[
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: widget.extraPills,
                                        ),
                                      ],
                                      if (widget.onExperiment != null) ...[
                                        LipButton(
                                          label: 'Experiment with your twin',
                                          icon: Icons.science_outlined,
                                          height: 64,
                                          fontSize: 22,
                                          onTap: widget.onExperiment,
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      _Dock(
                                        frame: f,
                                        onTalk: widget.onTalk,
                                        onCustomize: widget.onCustomize,
                                        onFortune: _fortune,
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

/// The quiz entry: small and secondary, under the header, above the score card.
class _QuizChip extends StatelessWidget {
  const _QuizChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Quiz. Play',
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: LtColors.night,
          borderRadius: BorderRadius.circular(LtRadii.chip),
          boxShadow: LtShadows.small,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.quiz_outlined, color: LtColors.gold, size: 22),
            const SizedBox(width: 6),
            Text('Quiz · play', style: LtText.body(size: 16, weight: FontWeight.w700, color: LtColors.cream)),
          ],
        ),
      ),
    ),
  );
}

/// The banner and the outlook card side by side, stacked when the screen is
/// narrow or the text is large (so nothing wraps letter by letter).
class _TopBar extends StatelessWidget {
  const _TopBar({super.key, required this.banner, required this.card, this.actions = const [], this.quiz});
  final Widget banner;
  final Widget? quiz;
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
                // The quiz chip is the first thing on Home (right side, so a double tap on the intake's Home button at the top left never lands on it); every gap below is 8.
                if (quiz != null) ...[Align(alignment: Alignment.centerRight, child: quiz), const SizedBox(height: 8)],
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
class _Dock extends StatelessWidget {
  const _Dock({required this.frame, required this.onTalk, required this.onCustomize, required this.onFortune});
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
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
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
                  label: 'Fortune',
                  icon: Icons.auto_awesome_rounded,
                  face: LtColors.night,
                  lip: const Color(0xFF0F1430),
                  iconColor: LtColors.gold,
                  onTap: onFortune,
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

/// "What should Mochi do?": four 48 pt options; the current one carries a check, not only a colour.
class _ActivityChooser extends StatelessWidget {
  const _ActivityChooser({required this.current, required this.onPick, required this.onWalk});
  final RoomAction? current;
  final void Function(RoomAction) onPick;
  final VoidCallback onWalk;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, IconData icon, bool selected, VoidCallback onTap) => Semantics(
      button: true,
      selected: selected,
      label: selected ? '$label, selected' : label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          color: selected ? LtColors.mintWash : null,
          child: Row(
            children: [
              Icon(icon, size: 24, color: LtColors.ink),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: LtText.body(weight: FontWeight.w700))),
              if (selected) const Icon(Icons.check_rounded, size: 24, color: LtColors.ink),
            ],
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Semantics(header: true, child: Text('What should Mochi do?', style: LtText.display(24))),
        ),
        option('Walk', Icons.directions_walk_rounded, current == null, onWalk),
        option('Exercise', Icons.fitness_center_rounded, current == RoomAction.exercise, () => onPick(RoomAction.exercise)),
        option('Eat', Icons.restaurant_rounded, current == RoomAction.eat, () => onPick(RoomAction.eat)),
        option('Sleep', Icons.bedtime_rounded, current == RoomAction.sleep, () => onPick(RoomAction.sleep)),
        const SizedBox(height: 12),
      ],
    );
  }
}
