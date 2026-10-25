import 'package:flutter/material.dart';

import '../experiment/experiment_page.dart';
import '../experiment/widgets/widgets.dart';
import '../twin/twin_model.dart';
import '../twin/twin_repository.dart';
import '../ui/theme.dart';
import '../ui/widgets/widgets.dart';

/// "Health documents" (design U-1, U-2): past uploads newest first, one chip per value, the
/// readings over time, and "Scan a document" / "Choose a file", which start the upload flow.
/// Readings are notes only: never part of the score or the outlook, and never judged by colour.
class HealthDocumentsScreen extends StatelessWidget {
  const HealthDocumentsScreen({
    super.key,
    required this.repository,
    required this.onBack,
    required this.onUpload,
    this.onTellMochiWeight,
    this.notices = const [],
  });

  final TwinRepository repository;
  final VoidCallback onBack;

  /// Starts the existing upload flow (the upload screen offers camera, photo or PDF).
  final VoidCallback onUpload;

  /// Opens the change chat for weight; shown with the two-weights notice.
  final VoidCallback? onTellMochiWeight;

  /// Notices from the last upload (`conflicting_values`).
  final List<String> notices;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository,
    builder: (context, _) {
      final uploads = [
        for (final e in repository.history())
          if (e.source == HistorySource.document) e,
      ];
      final readings = repository.readings();
      return ExperimentPage(
        title: 'Health documents',
        mode: LtMode.room,
        onBack: onBack,
        dock: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LipButton(label: 'Scan a document', icon: Icons.photo_camera_outlined, onTap: onUpload),
              const SizedBox(height: 10),
              LipButton(
                label: 'Choose a file',
                icon: Icons.folder_open_rounded,
                kind: LipKind.secondary,
                height: 56,
                onTap: onUpload,
              ),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notices.contains('conflicting_values') && onTellMochiWeight != null) ...[
              _Card(
                children: [
                  Text('Your document shows two different weights', style: LtText.body(weight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  LipButton(label: 'Tell Mochi which is right', kind: LipKind.secondary, height: 56, onTap: onTellMochiWeight),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (uploads.isEmpty)
              _Card(
                children: [
                  Text('No documents yet', style: LtText.display(24)),
                  const SizedBox(height: 6),
                  Text(
                    'Your document stays on this phone. Only its words are sent.',
                    style: LtText.body(color: LtColors.secondary),
                  ),
                ],
              )
            else ...[
              Semantics(header: true, child: Text('Your documents', style: LtText.display(24))),
              const SizedBox(height: 8),
              for (final e in uploads) ...[_UploadCard(entry: e), const SizedBox(height: 10)],
            ],
            if (readings.isNotEmpty) ...[
              const SizedBox(height: 6),
              _ReadingsCard(readings: readings),
            ],
          ],
        ),
      );
    },
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: LtColors.paper,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: LtColors.control, width: LtBorders.control),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _day(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String _dayText(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : _day(d);
}

String _num(Object? v) {
  if (v is num && v == v.roundToDouble()) return '${v.toInt()}';
  return '$v';
}

const _labels = {
  'hba1c': 'A1c',
  'ldl_cholesterol': 'LDL',
  'systolic_bp': 'Blood pressure',
  'weight_kg': 'Weight',
  'height_cm': 'Height',
};

/// The chips of one entry: a blood pressure pair is one chip.
List<(String, bool)> _chips(HistoryEntry e) {
  final out = <(String, bool)>[];
  final sys = e.items.where((i) => i.field == 'systolic_bp').firstOrNull;
  final dia = e.items.where((i) => i.field == 'diastolic_bp').firstOrNull;
  if (sys != null && dia != null) out.add(('Blood pressure ${_num(sys.value)}/${_num(dia.value)} mmHg', true));
  for (final i in e.items) {
    switch (i.field) {
      case 'systolic_bp' || 'diastolic_bp':
        break;
      case 'hba1c':
        out.add(('A1c ${_num(i.value)}%', true));
      case 'ldl_cholesterol':
        out.add(('LDL ${_num(i.value)} mg/dL', true));
      default:
        out.add(('${_labels[i.field] ?? i.field.replaceAll('_', ' ')} ${valueText(i.field, i.value)}', false));
    }
  }
  return out;
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final chips = _chips(entry);
    final notes = entry.kind == HistoryKind.reading;
    return _Card(
      children: [
        Text('Document', style: LtText.body(size: 18, weight: FontWeight.w700)),
        Text(_day(entry.at), style: LtText.body(color: LtColors.secondary)),
        const SizedBox(height: 8),
        Text(notes ? 'Notes' : 'Added', style: LtText.body(weight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final (t, note) in chips) _Chip(t, note: note)]),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.note});
  final String text;
  final bool note;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.description_outlined, size: 18, color: LtColors.ink),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: LtText.body(weight: FontWeight.w700))),
      ],
    );
    const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    if (note) {
      return DashedBox(color: LtColors.control, radius: 18, fill: LtColors.paper, padding: pad, child: content);
    }
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: LtColors.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LtColors.control, width: LtBorders.control),
      ),
      child: content,
    );
  }
}

class _ReadingsCard extends StatelessWidget {
  const _ReadingsCard({required this.readings});
  final List<HistoryEntry> readings;

  @override
  Widget build(BuildContext context) {
    // (date, text) rows per series, newest first; a document's own date when it had one.
    final bp = <(String, String)>[], a1c = <(String, String)>[], ldl = <(String, String)>[];
    for (final e in readings) {
      String date(HistoryItem i) => i.date ?? isoDate(e.at.toLocal());
      final sys = e.items.where((i) => i.field == 'systolic_bp').firstOrNull;
      final dia = e.items.where((i) => i.field == 'diastolic_bp').firstOrNull;
      if (sys != null && dia != null) bp.add((date(sys), '${_num(sys.value)}/${_num(dia.value)} mmHg'));
      for (final i in e.items) {
        if (i.field == 'hba1c') a1c.add((date(i), '${_num(i.value)}%'));
        if (i.field == 'ldl_cholesterol') ldl.add((date(i), '${_num(i.value)} mg/dL'));
      }
    }
    int byDate((String, String) a, (String, String) b) => b.$1.compareTo(a.$1);
    return _Card(
      children: [
        Semantics(header: true, child: Text('Readings', style: LtText.display(24))),
        Text('Notes only. Not part of your score or outlook.', style: LtText.body(color: LtColors.secondary)),
        for (final (title, rows) in [('Blood pressure', bp), ('A1c', a1c), ('LDL', ldl)])
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(title, style: LtText.body(weight: FontWeight.w700)),
            for (final (d, t) in ([...rows]..sort(byDate)))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(_dayText(d), style: LtText.body(color: LtColors.secondary))),
                    Text(t, style: LtText.body(weight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
      ],
    );
  }
}
