import 'package:flutter/material.dart';

import '../widgets/whole_word_text.dart';

import 'package:url_launcher/url_launcher.dart';

import '../ui/theme.dart';
import '../ui/widgets/widgets.dart';
import 'coach_client.dart';
import 'widgets.dart';

class DailyPlanScreen extends StatefulWidget {
  const DailyPlanScreen({
    super.key,
    required this.client,
    required this.confirmedContext,
    required this.onBack,
    required this.onTalk,
    this.initialPlan,
    this.onPlan,
  });
  final CoachClient client;

  /// Read fresh confirmed observations and consent for every request. Experiments
  /// and quiz state are deliberately outside the coach's context.
  final Map<String, dynamic> Function() confirmedContext;
  final VoidCallback onBack;
  final VoidCallback onTalk;
  final DailyPlan? initialPlan;

  /// The repository integration may persist the plan on the phone.
  final Future<void> Function(DailyPlan)? onPlan;

  @override
  State<DailyPlanScreen> createState() => _DailyPlanScreenState();
}

class _DailyPlanScreenState extends State<DailyPlanScreen> {
  DailyPlan? _plan;
  bool _busy = false;
  int _request = 0;
  String? _error;
  bool _refreshWithoutPrevious = false;
  final _choices = <String, String>{};
  bool _choiceOpen = false;
  bool get _canChoose => !_busy && !_refreshWithoutPrevious;

  @override
  void initState() {
    super.initState();
    _plan = widget.initialPlan;
    if (_plan == null) _refresh();
  }

  Future<void> _refresh([List<Map<String, dynamic>>? feedback]) async {
    if (_busy || feedback != null && _refreshWithoutPrevious) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final context = Map<String, dynamic>.from(widget.confirmedContext());
      if (context['memory_consent'] != true) context.remove('habit_notes');
      if (_plan case final previous?
          when previous.revision != null &&
              !previous.emergency &&
              !_refreshWithoutPrevious) {
        context['previous_plan'] = previous.previousPlan();
        context['latest_revision_id'] = previous.revision;
        if (feedback != null) {
          context['feedback'] = {
            'revision_id': previous.revision,
            'items': feedback,
          };
        }
      }
      final next = await widget.client.plan(context);
      if (!mounted || request != _request) return;
      await widget.onPlan?.call(next);
      if (mounted && request == _request) {
        setState(() {
          _plan = next;
          _refreshWithoutPrevious = false;
          for (final choice in feedback ?? <Map<String, dynamic>>[]) {
            _choices[choice['item_id'] as String] = choice['status'] as String;
          }
        });
      }
    } on CoachFailure catch (e) {
      if (mounted && request == _request) {
        if (e.statusCode == 409) _refreshWithoutPrevious = true;
        setState(
          () => _error = switch (e.statusCode) {
            409 =>
              'Your plan has moved on. Refresh it before sending this choice.',
            429 => 'A lot is happening. Give it a moment, then try again.',
            _ =>
              _plan == null
                  ? 'The planner needs a moment. Try again.'
                  : 'The plan couldn’t connect. Your saved plan is still here.',
          },
        );
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'That didn’t save. Please try again.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    if (!_canChoose || _choiceOpen) return;
    _choiceOpen = true;
    var time = item['time_of_day'] as String;
    int? minutes = item['minutes'] as int?;
    final edit = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const WholeWordText('Make it fit your day'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: time,
                  decoration: const InputDecoration(labelText: 'Time of day'),
                  items: [
                    for (final value in ['morning', 'afternoon', 'evening'])
                      DropdownMenuItem(
                        value: value,
                        child: WholeWordText(_slot(value)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => time = value);
                  },
                ),
                if (minutes != null) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: '$minutes',
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      helperText: '1–120 minutes',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) =>
                        setDialogState(() => minutes = int.tryParse(value)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const WholeWordText('Keep it as is'),
            ),
            TextButton(
              onPressed:
                  item['minutes'] != null &&
                      (minutes == null || minutes! < 1 || minutes! > 120)
                  ? null
                  : () {
                      final edit = <String, dynamic>{
                        'item_id': item['id'],
                        'status': 'edited',
                        'time_of_day': time,
                      };
                      if (minutes != null) {
                        edit['minutes'] = minutes;
                      }
                      Navigator.pop(context, edit);
                    },
              child: const WholeWordText('Save choice'),
            ),
          ],
        ),
      ),
    );
    _choiceOpen = false;
    if (edit != null && mounted) await _refresh([edit]);
  }

  static String _slot(String slot) => switch (slot) {
    'morning' => 'Morning',
    'afternoon' => 'Afternoon',
    'evening' => 'Evening',
    _ => slot,
  };

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WellnessPage(
    title: 'A plan for today',
    subtitle: 'Small ideas. Room to make them yours.',
    onBack: widget.onBack,
    children: [
      if (_busy)
        const LinearProgressIndicator(semanticsLabel: 'Preparing your plan'),
      if (_error != null)
        WellnessCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: WholeWordText(_error!, style: LtText.body()),
              ),
              const SizedBox(height: 12),
              LipButton(label: 'Refresh plan', onTap: _busy ? null : _refresh),
            ],
          ),
        ),
      if (_plan case final plan?) ...[
        if (!plan.paused)
          const MochiMessage(message: 'A few small things for today.'),
        if (plan.json['reused_previous'] == true)
          const WellnessCard(
            child: WholeWordText(
              'Same plan, same pace. Nothing new calls for a change.',
            ),
          ),
        if (plan.general)
          const WellnessCard(
            child: WholeWordText(
              'A general plan while Mochi gets to know you.',
            ),
          ),
        if (plan.paused) ...[
          MochiMessage(
            message: plan.emergency
                ? 'Let’s get you some help.'
                : 'Let’s pause movement and get you some support.',
          ),
          if (plan.json['alert'] == 'bp_crisis')
            WellnessCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WholeWordText(
                    'That blood pressure reading is very high. Contact your doctor now.',
                    style: LtText.body(),
                  ),
                  const SizedBox(height: 12),
                  WholeWordText(
                    'Chest pain, shortness of breath, back pain, weakness, or trouble seeing or speaking? Call 911.',
                    style: LtText.body(),
                  ),
                  LinkButton(
                    label: 'Call 911 · Opens phone app',
                    onTap: () => launchUrl(Uri.parse('tel:911')),
                  ),
                  LinkButton(
                    label: 'AHA: when to call for help',
                    onTap: () => launchUrl(
                      Uri.parse(
                        'https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/hypertensive-crisis-when-you-should-call-911-for-high-blood-pressure',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
            ),
          LipButton(label: 'Talk with Mochi', onTap: widget.onTalk),
        ] else ...[
          if (plan.items.isEmpty)
            const MochiMessage(
              message: 'Let’s find a small next step together.',
            ),
          for (final item in plan.items) _item(item),
        ],
        if (plan.changes.isNotEmpty)
          WellnessCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WholeWordText('What changed', style: LtText.display(24)),
                for (final change in plan.changes)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: WholeWordText(change, style: LtText.body()),
                  ),
              ],
            ),
          ),
        if (!plan.paused && plan.items.isNotEmpty) ...[
          LinkButton(label: 'Why this plan?', onTap: () => _why(plan)),
          LipButton(
            label: 'Yes to all',
            onTap: !_canChoose
                ? null
                : () => _refresh([
                    for (final item in plan.items)
                      {'item_id': item['id'], 'status': 'accepted'},
                  ]),
          ),
        ],
        WholeWordText(
          'Habit ideas, not medical advice. No promised health or lifespan gains.',
          style: LtText.body(size: 15),
        ),
      ],
    ],
  );

  Widget _item(Map<String, dynamic> item) => WellnessCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WholeWordText(
          _slot(item['time_of_day'] as String),
          style: LtText.body(size: 15, weight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        WholeWordText(item['title'] as String, style: LtText.display(25)),
        const SizedBox(height: 10),
        WholeWordText(item['message'] as String, style: LtText.body()),
        const SizedBox(height: 10),
        WholeWordText(item['why'] as String, style: LtText.body()),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(item['source_url'] as String),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: WholeWordText(item['source_title'] as String),
          ),
        ),
        WholeWordText(
          'Awaiting professional review',
          style: LtText.body(size: 15),
        ),
        if (_choices[item['id']] case final status?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Semantics(
              liveRegion: true,
              child: WholeWordText(switch (status) {
                'accepted' => 'On your plan',
                'done' => 'Done',
                'not_done' => 'Not done · Thanks for telling me',
                'dismissed' => 'Skipped',
                _ => 'Your change is saved',
              }, style: LtText.body(weight: FontWeight.w700)),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, status) in [
              ('Yes', 'accepted'),
              ('Skip', 'dismissed'),
            ])
              OutlinedButton(
                onPressed: !_canChoose
                    ? null
                    : () => _refresh([
                        {'item_id': item['id'], 'status': status},
                      ]),
                child: WholeWordText(label),
              ),
            OutlinedButton(
              onPressed: !_canChoose ? null : () => _edit(item),
              child: const WholeWordText('Change'),
            ),
          ],
        ),
        const Divider(height: 28),
        WholeWordText(
          'How did it go?',
          style: LtText.body(weight: FontWeight.w700),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: !_canChoose
                  ? null
                  : () => _refresh([
                      {'item_id': item['id'], 'status': 'done'},
                    ]),
              child: const WholeWordText('Done'),
            ),
            OutlinedButton(
              onPressed: !_canChoose ? null : () => _notDone(item),
              child: const WholeWordText('Not done'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _notDone(Map<String, dynamic> item) async {
    if (!_canChoose || _choiceOpen) return;
    _choiceOpen = true;
    String? reason;
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewInsetsOf(c).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WholeWordText(
                'Anything you’d like Mochi to know?',
                style: LtText.display(24),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in ['Too tired', 'Knee hurt', 'No time'])
                    ChoiceChip(
                      label: WholeWordText(value),
                      selected: reason == value,
                      onSelected: (_) => update(() => reason = value),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Say why (optional)',
                ),
                onChanged: (value) => reason = value.trim(),
              ),
              LipButton(
                label: 'Tell Mochi',
                onTap: () => Navigator.pop(c, reason ?? ''),
              ),
            ],
          ),
        ),
      ),
    );
    _choiceOpen = false;
    if (choice != null && mounted) {
      await _refresh([
        {
          'item_id': item['id'],
          'status': 'not_done',
          if (choice.isNotEmpty) 'reason': choice,
        },
      ]);
    }
  }

  Future<void> _why(DailyPlan plan) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WholeWordText('Why this plan', style: LtText.display(28)),
          const SizedBox(height: 16),
          for (final step in plan.trace)
            WellnessCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WholeWordText(
                    'You shared',
                    style: LtText.body(weight: FontWeight.w700),
                  ),
                  for (final fact in step['facts'] as List? ?? const [])
                    if (fact is Map && fact['value'] is String)
                      WholeWordText(
                        fact['value'] as String,
                        style: LtText.body(),
                      ),
                  const SizedBox(height: 12),
                  WholeWordText(
                    'Mochi’s rule',
                    style: LtText.body(weight: FontWeight.w700),
                  ),
                  WholeWordText('${step['rule']}', style: LtText.body()),
                  const SizedBox(height: 12),
                  WholeWordText(
                    'Guidance',
                    style: LtText.body(weight: FontWeight.w700),
                  ),
                  WholeWordText('${step['evidence']}', style: LtText.body()),
                  const SizedBox(height: 12),
                  WholeWordText(
                    'Today’s choice',
                    style: LtText.body(weight: FontWeight.w700),
                  ),
                  WholeWordText('${step['action']}', style: LtText.body()),
                ],
              ),
            ),
          if (plan.trace.isEmpty)
            WholeWordText(
              'No explanation was supplied for this plan.',
              style: LtText.body(),
            ),
          LipButton(
            label: 'Back to today’s plan',
            onTap: () => Navigator.pop(c),
          ),
        ],
      ),
    ),
  );
}
