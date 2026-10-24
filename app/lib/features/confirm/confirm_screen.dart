import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/intake_answers.dart';
import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_card.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_mascot.dart';
import '../../widgets/lt_scaffold.dart';
import '../../widgets/lt_segmented.dart';
import '../../widgets/lt_sheet.dart';
import '../intake/intake_script.dart';

/// F3: compact editable summary of what Pip heard. Each row opens an editor.
class ConfirmScreen extends ConsumerWidget {
  const ConfirmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final answers = ref.watch(intakeAnswersProvider);
    return LtPage(
      title: 'Confirm your answers',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          LtSpace.gutter,
          LtSpace.s8,
          LtSpace.gutter,
          LtSpace.s24,
        ),
        children: [
          Row(
            children: [
              const Mascot(state: MascotState.listening, width: 64),
              const SizedBox(width: LtSpace.s12),
              Expanded(
                child: Text(
                  'Here is what I heard. Tap any row to fix it.',
                  style: context.text.title3,
                ),
              ),
            ],
          ),
          const SizedBox(height: LtSpace.s16),
          LtCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, f) in IntakeField.values.indexed) ...[
                  if (i > 0) const Divider(indent: LtSpace.s20),
                  _Row(
                    field: f,
                    value: formatField(f, answers),
                    onTap: () => _edit(context, f),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: LtSpace.s16),
          Text(
            'Your baseline only changes when you record real measurements in '
            'the Activity tab. Nothing here is a prediction.',
            style: context.text.footnote.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: LtSpace.s24),
          LtButton(
            label: 'Looks right',
            onPressed: answers.isComplete
                ? () => context.push('/fortune')
                : null,
          ),
          if (!answers.isComplete)
            Padding(
              padding: const EdgeInsets.only(top: LtSpace.s8),
              child: Text(
                'Fill in every row to continue.',
                style: context.text.footnote,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  void _edit(BuildContext context, IntakeField f) {
    showLtSheet<void>(context, builder: (_) => FieldEditorSheet(field: f));
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.field, required this.value, required this.onTap});

  final IntakeField field;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Edit ${field.label}, ${value ?? 'not answered'}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LtSpace.s20,
              vertical: LtSpace.s12,
            ),
            child: Row(
              children: [
                Expanded(child: Text(field.label, style: context.text.callout)),
                Text(
                  value ?? 'Add',
                  style: context.text.headline.copyWith(
                    color: value == null ? c.actionPrimary : c.textPrimary,
                  ),
                ),
                const SizedBox(width: LtSpace.s8),
                LtIcon(LtIcons.chevronRight, color: c.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Edit one field. Numeric fields take a number (height and weight with a
/// unit toggle); choice fields use a segmented control.
class FieldEditorSheet extends ConsumerStatefulWidget {
  const FieldEditorSheet({super.key, required this.field});

  final IntakeField field;

  @override
  ConsumerState<FieldEditorSheet> createState() => _FieldEditorSheetState();
}

class _FieldEditorSheetState extends ConsumerState<FieldEditorSheet> {
  late final TextEditingController _text;
  late String _unit = widget.field.units.isEmpty ? '' : widget.field.units[0];

  IntakeField get f => widget.field;

  @override
  void initState() {
    super.initState();
    final a = ref.read(intakeAnswersProvider);
    final v = switch (f) {
      IntakeField.age => a.age?.toDouble(),
      IntakeField.height => a.heightCm,
      IntakeField.weight => a.weightKg,
      IntakeField.sleep => a.sleepHours,
      IntakeField.activity => a.activityMinutes?.toDouble(),
      IntakeField.drinks => a.drinksPerWeek?.toDouble(),
      _ => null,
    };
    _text = TextEditingController(
      text: v == null
          ? ''
          : (v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1)),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The typed number in the field's stored unit, or null if invalid.
  double? get _value {
    final n = double.tryParse(_text.text.trim());
    if (n == null) return null;
    final v = switch ((f, _unit)) {
      (IntakeField.height, 'in') => n * 2.54,
      (IntakeField.weight, 'lb') => n * 0.45359237,
      _ => n,
    };
    return v < f.min || v > f.max ? null : v;
  }

  void _save() {
    final v = _value;
    if (v == null) return;
    final n = ref.read(intakeAnswersProvider.notifier);
    final a = ref.read(intakeAnswersProvider);
    n.set(switch (f) {
      IntakeField.age => a.copyWith(age: v.round()),
      IntakeField.height => a.copyWith(heightCm: v),
      IntakeField.weight => a.copyWith(weightKg: v),
      IntakeField.sleep => a.copyWith(sleepHours: v),
      IntakeField.activity => a.copyWith(activityMinutes: v.round()),
      IntakeField.drinks => a.copyWith(drinksPerWeek: v.round()),
      _ => a,
    });
    Navigator.of(context).pop();
  }

  void _choose<T>(IntakeAnswers Function(IntakeAnswers) edit) {
    final n = ref.read(intakeAnswersProvider.notifier);
    n.set(edit(ref.read(intakeAnswersProvider)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = ref.watch(intakeAnswersProvider);
    if (f == IntakeField.sex) {
      return LtSheetScaffold(
        title: 'Sex',
        child: LtSegmented<Sex>(
          segments: [
            for (final s in Sex.values) LtSegment(value: s, label: s.label),
          ],
          value: a.sex ?? Sex.unspecified,
          onChanged: (s) => _choose((x) => x.copyWith(sex: s)),
        ),
      );
    }
    if (f == IntakeField.smoking) {
      return LtSheetScaffold(
        title: 'Smoking',
        child: LtSegmented<Smoking>(
          segments: [
            for (final s in Smoking.values) LtSegment(value: s, label: s.label),
          ],
          value: a.smoking ?? Smoking.never,
          onChanged: (s) => _choose((x) => x.copyWith(smoking: s)),
        ),
      );
    }
    final valid = _value != null;
    return LtSheetScaffold(
      title: f.label,
      footer: LtButton(label: 'Save', onPressed: valid ? _save : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (f.units.isNotEmpty) ...[
            LtSegmented<String>(
              segments: [
                for (final u in f.units)
                  LtSegment(
                    value: u,
                    label: switch (u) {
                      'in' => 'inches',
                      'lb' => 'pounds',
                      _ => u,
                    },
                  ),
              ],
              value: _unit,
              onChanged: (u) => setState(() => _unit = u),
            ),
            const SizedBox(height: LtSpace.s12),
          ],
          Container(
            constraints: const BoxConstraints(minHeight: LtSpace.touch),
            padding: const EdgeInsets.symmetric(horizontal: LtSpace.s16),
            decoration: BoxDecoration(
              color: c.bgGround,
              borderRadius: LtRadius.controlAll,
              border: Border.all(color: c.line),
            ),
            child: TextField(
              controller: _text,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: context.text.body,
              cursorColor: c.actionPrimary,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: f.hint,
                suffixText: f.units.isEmpty ? f.unit : _unit,
                suffixStyle: context.text.body.copyWith(color: c.textSecondary),
              ),
            ),
          ),
          if (!valid && _text.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: LtSpace.s8),
              child: Text(
                'Enter a number I can use for ${f.label.toLowerCase()}.',
                style: context.text.footnote.copyWith(color: c.actionPrimary),
              ),
            ),
        ],
      ),
    );
  }
}
