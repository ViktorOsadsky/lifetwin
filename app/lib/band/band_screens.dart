import 'package:flutter/material.dart';

import '../checkin/consent_screens.dart' show EqualChoice;
import '../experiment/experiment_page.dart';
import '../experiment/experiment_twins.dart';
import '../experiment/widgets/widgets.dart';
import '../twin/twin_state.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart' hide TwinMood;
import '../widgets/whole_word_text.dart';
import 'band_data.dart';
import 'band_service.dart';
import 'band_store.dart';

const _proud = TwinState(mood: TwinMood.cheerful, pose: TwinPose.stand, reason: TwinStateReason.feelingGood);

/// Pairing (H-2b, H-2, H-3, H-4): explain Bluetooth first, then search, then pair; the trouble screen
/// checks Bluetooth, never retries in a loop (after 2 tries the recorded demo is offered first), and
/// "Not now" or Close leaves with nothing asked and nothing saved.
class BandPairScreen extends StatefulWidget {
  const BandPairScreen({
    super.key,
    required this.store,
    required this.appearance,
    required this.onClose,
    required this.onSeeToday,
    this.onOpenSettings,
    this.onImportFile,
  });

  final BandStore store;
  final TwinAppearance appearance;
  final VoidCallback onClose;
  final VoidCallback onSeeToday;

  /// "Open Settings" when Bluetooth is not allowed (the app's own settings page).
  final VoidCallback? onOpenSettings;

  /// "Import band file" on the first screen: a file instead of Bluetooth. Hidden when null.
  final Future<void> Function()? onImportFile;

  @override
  State<BandPairScreen> createState() => _BandPairScreenState();
}

enum _Step { before, searching, found, trouble, paired }

class _BandPairScreenState extends State<BandPairScreen> {
  _Step _step = _Step.before;
  List<BandDevice> _found = const [];
  BluetoothState _bt = BluetoothState.on;
  int _tries = 0;

  Future<void> _search() async {
    setState(() => _step = _Step.searching);
    _bt = await widget.store.client.bluetooth();
    if (_bt != BluetoothState.on) {
      setState(() => _step = _Step.trouble);
      return;
    }
    _tries++;
    final devices = await widget.store.client.scan();
    if (!mounted) return;
    setState(() {
      _found = devices;
      _step = devices.isEmpty ? _Step.trouble : _Step.found;
    });
  }

  Future<void> _pair(BandDevice d) async {
    final ok = await widget.store.pair(d);
    if (!mounted) return;
    setState(() => _step = ok ? _Step.paired : _Step.trouble);
  }

  @override
  Widget build(BuildContext context) {
    final (bubble, title, state) = switch (_step) {
      _Step.before => ('Put the band on your leg, then turn it on.', 'Find your band', steadyTwin),
      _Step.searching => ('Looking…', 'Find your band', curiousTwin),
      _Step.found => ('Found your band!', 'Pair your band', steadyTwin),
      _Step.trouble => ('Hmm, I can’t see it yet.', 'Can’t find your band', steadyTwin),
      _Step.paired => ('Yay, we’re linked!', 'Band paired', _proud),
    };
    return ExperimentPage(
      mode: LtMode.room,
      onBack: widget.onClose,
      backLabel: 'Close',
      dock: _dock(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: widget.appearance,
            twins: [TwinSlot(state: state, x: 0.3)],
            bubble: bubble,
          ),
          const SizedBox(height: 14),
          Sheet(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: Text(title, style: LtText.display(28))),
                const SizedBox(height: 8),
                ..._body(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body() {
    switch (_step) {
      case _Step.before:
        return [
          WholeWordText('Mochi uses Bluetooth to find your band.', style: LtText.body()),
          const SizedBox(height: 8),
          WholeWordText('Strap it around your leg, just above the ankle.', style: LtText.body()),
        ];
      case _Step.searching:
        return [NoNumberBox(icon: Icons.bluetooth_searching_rounded, title: 'Looking for your band…')];
      case _Step.found:
        return [
          for (final d in _found)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              decoration: BoxDecoration(
                color: LtColors.paper,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: LtColors.control, width: LtBorders.control),
              ),
              child: Row(
                children: [
                  const LeverIcon(Icons.directions_walk_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name, style: LtText.body(size: 18, weight: FontWeight.w700)),
                        Text('Nearby', style: LtText.body(color: LtColors.secondary)),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: LipButton(label: 'Pair', height: 56, fontSize: 20, onTap: () => _pair(d)),
                  ),
                ],
              ),
            ),
          TextButton(
            onPressed: _search,
            child: Text('Not mine? Search again', style: LtText.body(weight: FontWeight.w700)),
          ),
        ];
      case _Step.trouble:
        final off = _bt == BluetoothState.off, denied = _bt == BluetoothState.notAllowed;
        return [
          _Check(
            label: off ? 'Bluetooth is off' : (denied ? 'Bluetooth not allowed' : 'Bluetooth is on'),
            ok: _bt == BluetoothState.on,
            sub: off ? 'Turn it on in Control Center' : null,
          ),
          const _Check(label: 'Band is turned on'),
          const _Check(label: 'Band is close by'),
        ];
      case _Step.paired:
        return [
          WholeWordText('Wear it on your leg all day. Mochi counts:', style: LtText.body()),
          const SizedBox(height: 6),
          for (final (icon, t, muted) in const [
            (Icons.directions_walk_rounded, 'Steps', false),
            (Icons.directions_run_rounded, 'Moderate minutes', false),
            (Icons.directions_walk_rounded, 'Time worn', false),
            (Icons.favorite_border_rounded, 'Heart rate, later', true),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(icon, size: 24, color: muted ? LtColors.secondary : LtColors.ink),
                  const SizedBox(width: 10),
                  Text(t, style: LtText.body(color: muted ? LtColors.secondary : LtColors.ink)),
                ],
              ),
            ),
        ];
    }
  }

  Widget _dock(BuildContext context) {
    final pad = EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom);
    Widget col(List<Widget> c) => Padding(
      padding: pad,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: c),
    );
    switch (_step) {
      case _Step.before:
        return col([
          LipButton(label: 'Find my band', icon: Icons.bluetooth_rounded, fontSize: 24, onTap: _search),
          if (widget.onImportFile != null)
            TextButton(
              onPressed: () => widget.onImportFile!(),
              child: Text('Import band file', style: LtText.body(weight: FontWeight.w700)),
            ),
          TextButton(
            onPressed: widget.onClose,
            child: Text('Not now', style: LtText.body(weight: FontWeight.w700)),
          ),
        ]);
      case _Step.searching:
        return const SizedBox.shrink();
      case _Step.found:
        return const SizedBox.shrink();
      case _Step.trouble:
        final denied = _bt == BluetoothState.notAllowed;
        return col([
          if (_tries >= 2) ...[
            LipButton(
              label: 'Try a recorded demo',
              kind: LipKind.secondary,
              height: 56,
              fontSize: 20,
              onTap: () {
                widget.store.setDemo(true);
                widget.onSeeToday();
              },
            ),
            const SizedBox(height: 8),
          ],
          LipButton(
            label: denied ? 'Open Settings' : 'Try again',
            fontSize: 24,
            onTap: denied ? widget.onOpenSettings : _search,
          ),
          if (_tries < 2)
            TextButton(
              onPressed: () {
                widget.store.setDemo(true);
                widget.onSeeToday();
              },
              child: Text('Try a recorded demo', style: LtText.body(weight: FontWeight.w700)),
            ),
        ]);
      case _Step.paired:
        return col([
          Text(
            'Minutes stay on this phone',
            textAlign: TextAlign.center,
            style: LtText.body(color: LtColors.secondary),
          ),
          const SizedBox(height: 6),
          LipButton(label: 'See today', fontSize: 24, onTap: widget.onSeeToday),
        ]);
    }
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.label, this.ok, this.sub});
  final String label;

  /// true: checked; false: dashed (a problem); null: a tip the app cannot see.
  final bool? ok;
  final String? sub;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ok == false
        ? NoNumberBox(icon: Icons.bluetooth_disabled_rounded, title: label, body: sub)
        : Row(
            children: [
              Icon(
                ok == true ? Icons.check_circle_outline_rounded : Icons.circle_outlined,
                size: 24,
                color: LtColors.ink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: LtText.body(weight: FontWeight.w700)),
              ),
            ],
          ),
  );
}

/// The band panel (H-5, H-10, H-13): Today and Week tabs, with one state banner at the top at a time.
/// Everything is computed on the phone from minute records in memory; every number is a "Sensor
/// estimate". No survival number or difference appears here.
class BandPanelScreen extends StatefulWidget {
  const BandPanelScreen({
    super.key,
    required this.store,
    required this.service,
    required this.onBack,
    required this.onSettings,
    this.onUseSuggestion,
  });

  final BandStore store;
  final BandService service;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  /// "Use this" on the weekly offer: opens the read-back.
  final void Function(BandSuggestion suggestion)? onUseSuggestion;

  @override
  State<BandPanelScreen> createState() => _BandPanelScreenState();
}

class _BandPanelScreenState extends State<BandPanelScreen> {
  bool _week = false;

  static const banners = {
    BandStatus.notConnected: ('Band not connected', 'Saved days are safe.', 'Reconnect'),
    BandStatus.lowPower: ('Band power is low', 'Counting may stop soon.', null),
    BandStatus.notWorn: ('Band is off your leg', 'Put it on to count today.', null),
    BandStatus.demo: ('Recorded demo', 'A saved day, not live.', null),
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.store, widget.service]),
    builder: (context, _) {
      final s = widget.store;
      final w = s.week();
      final today = w.days.last;
      final banner = banners[s.status];
      final suggestion = widget.service.suggest(w, live: s.live, demo: s.demoOnly);
      return ExperimentPage(
        mode: LtMode.room,
        title: 'Your band',
        onBack: widget.onBack,
        backLabel: 'Back to room',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (banner != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: NoNumberBox(icon: Icons.info_outline_rounded, title: banner.$1, body: banner.$2),
              ),
            Row(
              children: [
                Expanded(
                  child: _Tab(label: 'Today', on: !_week, onTap: () => setState(() => _week = false)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Tab(label: 'Week', on: _week, onTap: () => setState(() => _week = true)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_week) _todayCard(today) else _weekCard(w, suggestion),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.lastSynced == null ? 'Not synced yet' : 'Synced just now',
                    style: LtText.body(color: LtColors.secondary),
                  ),
                ),
                TextButton(
                  onPressed: widget.onSettings,
                  child: Text('Band settings', style: LtText.body(weight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _todayCard(BandDay d) {
    final hours = (d.wornMinutes / 60).floor();
    return Sheet(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_n(d.steps), style: LtText.display(44)),
          Text('steps today', style: LtText.body(color: LtColors.secondary)),
          const SizedBox(height: 4),
          const ModeTag(text: 'Sensor estimate'),
          const SizedBox(height: 10),
          _HourBars(hours: d.stepsByHour),
          const SizedBox(height: 8),
          // Wraps (never overflows) at narrow widths and large text.
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.directions_run_rounded, size: 22),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('${d.moderateMinutes} min moderate', style: LtText.body(weight: FontWeight.w700)),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.directions_walk_rounded, size: 22),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('$hours hours worn', style: LtText.body(weight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
          if (!d.isValid) ...[
            const SizedBox(height: 8),
            WholeWordText(
              'Wear it on your leg ${(validDayMinutes - d.wornMinutes + 59) ~/ 60} more hours so today counts.',
              style: LtText.body(color: LtColors.secondary),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.favorite_border_rounded, size: 22, color: LtColors.secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Heart rate', style: LtText.body(color: LtColors.secondary)),
              ),
              const SizedBox(width: 8),
              const ModeTag(text: 'Coming soon'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekCard(BandWeek w, BandSuggestion? suggestion) => Sheet(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final d in w.days)
              Expanded(
                child: Semantics(
                  label: '${_dow(d.date)}: ${d.isValid ? 'counted' : 'not counted'}',
                  excludeSemantics: true,
                  child: Column(
                    children: [
                      Container(
                        height: 56,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: d.isValid ? LtColors.mint : LtColors.paper,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: LtColors.control, width: 1.5),
                        ),
                        child: d.isValid ? const Icon(Icons.check_rounded, size: 22) : null,
                      ),
                      Text(_dow(d.date), style: LtText.body(size: 15)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (w.hasEstimate) ...[
          Text(
            '${w.validCount} of 7 days counted · about ${w.estimateMinutesPerWeek} minutes a week',
            style: LtText.body(weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              if (suggestion?.demo ?? widget.store.demo) const ModeTag(text: BandSuggestion.demoLabel),
              const ModeTag(text: 'From your band'),
              const ModeTag(text: 'Sensor estimate'),
            ],
          ),
        ] else
          WholeWordText('Wear it on your leg 4 days to get a weekly number.', style: LtText.body()),
        if (suggestion != null && widget.onUseSuggestion != null) ...[
          const SizedBox(height: 12),
          LipButton(
            label: 'Mochi has a suggestion',
            icon: Icons.chat_bubble_outline_rounded,
            fontSize: 20,
            onTap: () => widget.onUseSuggestion!(suggestion),
          ),
        ] else if (widget.service.savedMinutes case final saved?) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text('Saved: about $saved minutes a week', style: LtText.body(weight: FontWeight.w700)),
          ),
        ],
      ],
    ),
  );

  static String _n(int v) => v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  static String _dow(DateTime d) => const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'][d.weekday - 1];
}

class ModeTag extends StatelessWidget {
  const ModeTag({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => DashedBox(
    color: LtColors.control,
    radius: 16,
    fill: LtColors.paper,
    constraints: const BoxConstraints(minHeight: 32),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Center(
      widthFactor: 1,
      child: Text(text, style: LtText.body(weight: FontWeight.w700)),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? LtColors.mint : LtColors.paper,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: LtColors.control, width: LtBorders.control),
        ),
        child: Text(label, style: LtText.display(20)),
      ),
    ),
  );
}

/// Steps by hour from 7 AM, one colour; a not-worn hour is a dashed baseline.
class _HourBars extends StatelessWidget {
  const _HourBars({required this.hours});
  final List<int?> hours;

  @override
  Widget build(BuildContext context) {
    final shown = hours.sublist(7, 16);
    final peak = shown.whereType<int>().fold<int>(1, (a, b) => b > a ? b : a);
    return Semantics(
      image: true,
      label:
          'Steps each hour: ${[for (var i = 0; i < shown.length; i++) '${i + 7}:00 ${shown[i] ?? 'not worn'}'].join(', ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: 96,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final v in shown)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: v == null ? 4 : (8 + 80 * v / peak),
                  decoration: v == null
                      ? BoxDecoration(
                          border: Border(bottom: BorderSide(color: LtColors.control, width: 1.5)),
                        )
                      : BoxDecoration(color: LtColors.teal, borderRadius: BorderRadius.circular(4)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The band's suggestion and its read-back (H-6, H-7, H-7v). "Use this" opens the read-back; only the
/// person's "Yes, save" (or "Use about N") saves anything, and the disclosure ("From your band",
/// "Sensor estimate", "This may change your outlook.") sits inside the read-back, above the buttons.
/// A lower estimate is kind ("Weeks vary. That's okay."), with two equal choices that name both values.
class BandReadbackScreen extends StatefulWidget {
  const BandReadbackScreen({
    super.key,
    required this.service,
    required this.suggestion,
    required this.appearance,
    required this.onClose,
  });

  final BandService service;
  final BandSuggestion suggestion;
  final TwinAppearance appearance;
  final VoidCallback onClose;

  @override
  State<BandReadbackScreen> createState() => _BandReadbackScreenState();
}

class _BandReadbackScreenState extends State<BandReadbackScreen> {
  bool _saved = false;
  bool _askMinutes = false;
  int? _custom;
  final _text = TextEditingController();

  BandSuggestion get s => widget.suggestion;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.service.confirm(s, minutes: _custom);
    if (mounted) setState(() => _saved = true);
  }

  void _giveMinutes() {
    final n = int.tryParse(_text.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (n == null || n < 0 || n > 10080) return;
    setState(() {
      _custom = n;
      _askMinutes = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = _custom ?? s.estimate;
    final lowerVariant = s.lower && _custom == null && !_askMinutes;
    return ExperimentPage(
      mode: LtMode.onboarding,
      title: 'Update with Mochi',
      onBack: widget.onClose,
      backLabel: 'Close',
      dock: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
        child: _saved
            ? LipButton(label: 'Close', fontSize: 22, onTap: widget.onClose)
            : _askMinutes
            ? Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'Minutes a week'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(tooltip: 'Send', onPressed: _giveMinutes, icon: const Icon(Icons.send_rounded)),
                ],
              )
            : lowerVariant
            ? EqualChoice(
                noLabel: 'Keep ${s.current.round()}',
                yesLabel: 'Use about ${s.estimate}',
                onNo: () {
                  widget.service.keep();
                  widget.onClose();
                },
                onYes: _save,
              )
            : Row(
                children: [
                  Expanded(
                    child: LipButton(
                      label: 'Not quite',
                      kind: LipKind.secondary,
                      fontSize: 20,
                      onTap: () => setState(() => _askMinutes = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LipButton(label: 'Yes, save', icon: Icons.check_rounded, fontSize: 20, onTap: _save),
                  ),
                ],
              ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: widget.appearance,
            twins: [TwinSlot(state: curiousTwin, x: 0.3)],
            bubble: lowerVariant ? 'Weeks vary. That’s okay.' : 'Did I get that right?',
          ),
          const SizedBox(height: 12),
          if (_saved)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: LtColors.mintWash,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: LtColors.container, width: 1.5),
              ),
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Saved.', style: LtText.display(22)),
                    Text('$bandFieldLabel: about $value minutes a week · From your band', style: LtText.body()),
                  ],
                ),
              ),
            )
          else if (_askMinutes)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: LtColors.paper,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: LtColors.container, width: 1.5),
              ),
              child: Text('About how many minutes, then?', style: LtText.display(22)),
            )
          else
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: LtColors.paper,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: LtColors.container, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mochi',
                    style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _custom != null
                          ? '$bandFieldLabel: about $_custom minutes a week, instead of ${s.current.round()}. Right?'
                          : s.question,
                      style: LtText.display(22),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (s.demo) const ModeTag(text: BandSuggestion.demoLabel),
                      const ModeTag(text: 'From your band'),
                      const ModeTag(text: 'Sensor estimate'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('This may change your outlook.', style: LtText.body(weight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "I counted 4 days!" (H-6): the weekly offer. Nothing is saved here; "Use this" opens the
/// read-back, "Not now" dismisses it until next week. Your saved answer is shown, untouched.
class BandSuggestScreen extends StatelessWidget {
  const BandSuggestScreen({
    super.key,
    required this.service,
    required this.store,
    required this.suggestion,
    required this.appearance,
    required this.onBack,
    required this.onUse,
  });

  final BandService service;
  final BandStore store;
  final BandSuggestion suggestion;
  final TwinAppearance appearance;
  final VoidCallback onBack;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final w = store.week();
    return ExperimentPage(
      mode: LtMode.room,
      onBack: onBack,
      dock: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your answer now: ${suggestion.current.round()} minutes a week',
              style: LtText.body(color: LtColors.secondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LipButton(
                    label: 'Not now',
                    kind: LipKind.secondary,
                    fontSize: 20,
                    onTap: () {
                      service.dismiss();
                      onBack();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LipButton(label: 'Use this', fontSize: 20, onTap: onUse),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExperimentPlate(
            appearance: appearance,
            twins: [TwinSlot(state: curiousTwin, x: 0.3)],
            bubble: 'I counted ${suggestion.validDays} days!',
          ),
          const SizedBox(height: 12),
          Sheet(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WholeWordText(
                  '$bandFieldLabel: about ${suggestion.estimate} minutes a week, from ${suggestion.validDays} days worn. Use this?',
                  style: LtText.body(),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    if (suggestion.demo) const ModeTag(text: BandSuggestion.demoLabel),
                    const ModeTag(text: 'From your band'),
                    const ModeTag(text: 'Sensor estimate'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final d in w.days)
                      Expanded(
                        child: Container(
                          height: 48,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: d.isValid ? LtColors.mint : LtColors.paper,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: LtColors.control, width: 1.5),
                          ),
                          child: d.isValid ? const Icon(Icons.check_rounded, size: 20) : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                WholeWordText(
                  'Your band saw ${suggestion.validMinutes} minutes on ${suggestion.validDays} days. For a full week, that’s about ${suggestion.estimate}.',
                  style: LtText.body(color: LtColors.secondary),
                ),
                TextButton(
                  onPressed: () => showInfoSheet(context, title: 'How?', body: BandSuggestion.how),
                  child: Text('How?', style: LtText.body(weight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Wrist band" settings (H-11): what is sent (nothing leaves the phone except, if the person says yes, the
/// weekly total in a request they start; processed and dropped, never stored), the recorded-demo
/// switch, and Unpair, which erases band days on this phone while confirmed answers stay. Nothing from
/// the band goes to an outside AI provider.
class BandSettingsScreen extends StatelessWidget {
  const BandSettingsScreen({super.key, required this.store, required this.onBack, this.onImportFile, this.onForget});
  final BandStore store;
  final VoidCallback onBack;

  /// "Import band file": picks a `lifetwin.band_day.v0` file and feeds the band days (the weekly suggestion
  /// and its confirmation follow as usual). Hidden when null.
  final Future<void> Function()? onImportFile;

  /// What "Unpair" does when given (it forgets imported files too); the store's own unpair otherwise.
  final Future<void> Function()? onForget;

  Future<void> _unpair(BuildContext context) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: LtColors.paper,
              borderRadius: BorderRadius.circular(LtRadii.panel),
              border: Border.all(color: LtColors.container, width: LtBorders.container),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Unpair your band?', style: LtText.display(26)),
                  const SizedBox(height: 8),
                  WholeWordText('Band days on this phone are erased. Your saved answers stay.', style: LtText.body()),
                  const SizedBox(height: 14),
                  EqualChoice(
                    noLabel: 'Keep band',
                    yesLabel: 'Unpair',
                    onNo: () => Navigator.of(c).pop(false),
                    onYes: () => Navigator.of(c).pop(true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (ok == true) await (onForget?.call() ?? store.unpair());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => ExperimentPage(
      mode: LtMode.customize,
      title: 'Activity band',
      onBack: onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const LeverIcon(Icons.directions_walk_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(store.bandName ?? 'No band paired', style: LtText.body(size: 18, weight: FontWeight.w700)),
              ),
              ModeTag(text: store.paired ? 'Connected' : 'Not paired'),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(header: true, child: Text('What’s sent', style: LtText.display(22))),
          const SizedBox(height: 6),
          for (final (who, what) in const [
            ('Band', 'Counts moves'),
            ('Phone', 'Details stay here'),
            ('Server', 'Weekly total, only when you say yes'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(who, style: LtText.body(weight: FontWeight.w700)),
                  ),
                  Expanded(child: Text(what, style: LtText.body())),
                ],
              ),
            ),
          Text('Never stored on our server.', style: LtText.body(weight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.favorite_border_rounded, size: 22, color: LtColors.secondary),
              const SizedBox(width: 8),
              Text('Heart rate', style: LtText.body(color: LtColors.secondary)),
              const Spacer(),
              const ModeTag(text: 'Coming soon'),
            ],
          ),
          const SizedBox(height: 12),
          MergeSemantics(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text('Recorded demo', style: LtText.body(size: 18, weight: FontWeight.w700)),
              value: store.demo,
              onChanged: (_) => store.setDemo(!store.demo),
            ),
          ),
          if (onImportFile != null) ...[
            const SizedBox(height: 8),
            LipButton(
              label: 'Import band file',
              kind: LipKind.secondary,
              height: 56,
              fontSize: 21,
              onTap: () => onImportFile!(),
            ),
          ],
          const SizedBox(height: 8),
          LipButton(
            label: 'Unpair band',
            kind: LipKind.secondary,
            height: 56,
            fontSize: 21,
            onTap: store.paired || store.demo || store.hasImportedFile ? () => _unpair(context) : null,
          ),
        ],
      ),
    ),
  );
}

/// The Room's band pill (H-1, H-8): "Add band" while none is paired; once paired, today's steps with an
/// approximate sign (a band estimate); a dashed "Band not connected" when the link is lost.
class BandPill extends StatelessWidget {
  const BandPill({super.key, required this.store, required this.onTap});
  final BandStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (store.hiddenFromRoom) return const SizedBox.shrink();
      final label = !store.paired && !store.demo
          ? 'Add band'
          : store.status == BandStatus.notConnected
          ? 'Band not connected'
          : '≈ ${store.today.steps} steps';
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LtColors.paper,
              borderRadius: BorderRadius.circular(LtRadii.chip),
              border: Border.all(color: LtColors.control, width: LtBorders.control),
              boxShadow: LtShadows.small,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.directions_walk_rounded, size: 22, color: LtColors.ink),
                const SizedBox(width: 6),
                Text(label, style: LtText.body(weight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    },
  );
}
