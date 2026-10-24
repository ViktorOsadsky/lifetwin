import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../widgets/whole_word_text.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart';

/// V-6 Customize: Bear / Human, outfit tabs, die-cut tiles as radios, and
/// Save look.
///
/// Cosmetic only. The look lives in [appearance] (memory); this screen has
/// no access to the health profile, the conversation or the forecast.
class CustomizeScreen extends StatefulWidget {
  const CustomizeScreen({super.key, required this.appearance, required this.onDone});

  final ValueNotifier<TwinAppearance> appearance;

  /// Called after Save look, or Back (which keeps the old look).
  final VoidCallback onDone;

  @override
  State<CustomizeScreen> createState() => _CustomizeScreenState();
}

enum _Tab {
  hats('Hats', Icons.face_retouching_natural),
  tops('Tops', Icons.checkroom_rounded),
  glasses('Glasses', Icons.visibility_outlined),
  fur('Fur', Icons.pets_rounded),
  aids('Aids', Icons.elderly_rounded);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _CustomizeScreenState extends State<CustomizeScreen> {
  late TwinAppearance _draft = widget.appearance.value;
  _Tab _tab = _Tab.hats;

  void _save() {
    widget.appearance.value = _draft;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return ModeScaffold(
      mode: LtMode.customize,
      child: PlateSheetLayout(
        minWindow: 200,
        window: PlateWindow(
          name: _draft.name,
          plate: PlateScene(
            asset: ScenePlate.customize.asset,
            focus: const Offset(0.503, 0.48),
            focusTarget: const Offset(0.497, 0.88),
            twinBuilder: (feet, scale, box) => plantTwin(
              feet,
              TwinSprite(appearance: _draft, height: math.max(60.0, math.min(266 * scale, box.height * 0.85))),
            ),
          ),
          overlay: Stack(
            children: [
              Positioned(
                left: 14,
                top: 18,
                child: RoundBackButton(label: 'Back to room', onTap: widget.onDone),
              ),
            ],
          ),
        ),
        sheet: Sheet(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _typeSwitch(),
              const SizedBox(height: 12),
              _tabs(),
              const SizedBox(height: 12),
              if (_tab == _Tab.hats) _hats() else _comingSoon(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: LipButton(label: 'Save look', icon: Icons.check_rounded, height: 64, fontSize: 24, onTap: _save),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeSwitch() {
    Widget option(TwinType type, String label) {
      final on = _draft.type == type;
      return Expanded(
        child: Semantics(
          inMutuallyExclusiveGroup: true,
          checked: on,
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: () => setState(() => _draft = _draft.copyWith(type: type)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _draft = _draft.copyWith(type: type)),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: on ? LtColors.mint : Colors.transparent,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: on ? LtColors.controlOnMint : Colors.transparent, width: LtBorders.control),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Thumb(asset: twinAsset(type, TwinLook.plain)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: WholeWordText(label, style: LtText.body(size: 19, weight: FontWeight.w700)),
                  ),
                  if (on) ...[const SizedBox(width: 6), const Icon(Icons.check_rounded, color: LtColors.ink)],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Twin type',
      container: true,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF4ECE0),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: LtColors.container, width: LtBorders.container),
        ),
        child: Row(
          children: [option(TwinType.bear, 'Bear'), const SizedBox(width: 4), option(TwinType.human, 'Human')],
        ),
      ),
    );
  }

  Widget _tabs() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 6,
      children: [
        for (final t in _Tab.values)
          Semantics(
            selected: t == _tab,
            button: true,
            label: '${t.label} tab',
            excludeSemantics: true,
            onTap: () => setState(() => _tab = t),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _tab = t),
              child: Container(
                constraints: const BoxConstraints(minWidth: 62, minHeight: 66),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: t == _tab ? LtColors.mint : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: t == _tab ? LtColors.controlOnMint : Colors.transparent,
                    width: LtBorders.control,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(t.icon, size: 26, color: LtColors.ink),
                    const SizedBox(height: 3),
                    // One line inside the tab: shrinks rather than breaking the word.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: WholeWordText(
                        t.label,
                        style: LtText.body(weight: t == _tab ? FontWeight.w700 : FontWeight.w400),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _hats() {
    final hasCal = _draft.look == TwinLook.calHat;
    return Semantics(
      label: 'Hats',
      container: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          _Tile(
            label: 'Cal hat',
            selected: hasCal,
            tilt: -1,
            art: Image.asset(calHatAsset, width: 52, height: 52, excludeFromSemantics: true),
            onTap: () => setState(() => _draft = _draft.copyWith(look: TwinLook.calHat)),
          ),
          _Tile(
            label: 'No hat',
            selected: !hasCal,
            tilt: 1,
            art: const Icon(Icons.do_not_disturb_alt_rounded, size: 40, color: LtColors.ink),
            onTap: () => setState(() => _draft = _draft.copyWith(look: TwinLook.plain)),
          ),
          // Drawn in the design; no sprite art exists for these yet.
          for (final (label, icon) in const [
            ('Beanie', Icons.ac_unit_rounded),
            ('Sun hat', Icons.wb_sunny_outlined),
            ('Cap', Icons.sports_baseball_outlined),
            ('Visor', Icons.light_mode_outlined),
          ])
            _Tile(
              label: label,
              selected: false,
              tilt: 0,
              art: Icon(icon, size: 36, color: LtColors.control),
              onTap: null,
            ),
        ],
      ),
    );
  }

  Widget _comingSoon() => Container(
    constraints: const BoxConstraints(minHeight: 96),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: WholeWordText('${_tab.label} are coming soon.', textAlign: TextAlign.center, style: LtText.body(size: 18)),
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.asset});
  final String asset;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: LtColors.cream,
      border: Border.all(color: LtColors.control, width: LtBorders.control),
    ),
    clipBehavior: Clip.antiAlias,
    child: OverflowBox(
      maxWidth: 92,
      maxHeight: 92,
      alignment: const Alignment(0, 0.55),
      child: Image.asset(asset, width: 92, height: 92, excludeFromSemantics: true),
    ),
  );
}

/// A die-cut tile used as a radio. Null [onTap] means not available yet.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.selected,
    required this.tilt,
    required this.art,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double tilt;
  final Widget art;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final available = onTap != null;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      enabled: available,
      label: available ? label : '$label, not available yet',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Transform.rotate(
          angle: tilt * math.pi / 180,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 104,
                constraints: const BoxConstraints(minHeight: 88),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: selected ? LtColors.mint : (available ? LtColors.paper : LtColors.cream),
                  borderRadius: BorderRadius.circular(LtRadii.tile),
                  border: Border.all(
                    color: selected ? LtColors.controlOnMint : LtColors.control,
                    width: LtBorders.control,
                  ),
                  boxShadow: selected ? LtShadows.soft : LtShadows.small,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    art,
                    const SizedBox(height: 2),
                    // One line inside the tile: shrinks rather than wrapping.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: WholeWordText(
                        label,
                        textAlign: TextAlign.center,
                        style: LtText.body(weight: selected ? FontWeight.w700 : FontWeight.w400),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  right: -8,
                  top: -8,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: LtColors.ink,
                      shape: BoxShape.circle,
                      border: Border.all(color: LtColors.paper, width: 2),
                    ),
                    child: const Icon(Icons.check_rounded, size: 18, color: LtColors.paper),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
