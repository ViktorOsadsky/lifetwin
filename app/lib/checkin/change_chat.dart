import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../experiment/experiment_page.dart';
import '../experiment/experiment_twins.dart';
import '../experiment/widgets/widgets.dart';
import '../twin/twin_repository.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart' hide TwinMood;
import '../voice/api_base.dart';
import '../widgets/whole_word_text.dart';
import 'checkin_client.dart';
import 'emergency_card.dart';

/// The change conversation (`POST /api/change/start` and `/turn`, live on main since #50): the
/// only way a saved answer changes, apart from onboarding, check-ins, Apple Health import and Delete
/// my data. Saved answers have no edit fields; "Change" opens this instead.
abstract class ChangeClient {
  /// [field] is a profile field, or null for "What would you like to update?".
  Future<CheckInResponse> start({required Map<String, dynamic> profile, String? field, required bool memoryConsent});

  /// [action]: reply | confirm | cancel | resume.
  Future<CheckInResponse> turn({
    required String action,
    required Map<String, dynamic> state,
    required Map<String, dynamic> profile,
    required bool memoryConsent,
    String? text,
    bool fromTranscript = false,
  });
}

class HttpChangeClient implements ChangeClient {
  HttpChangeClient({http.Client? client, ApiBase? base}) : _client = client ?? http.Client(), base = base ?? ApiBase();
  final http.Client _client;
  final ApiBase base;

  @override
  Future<CheckInResponse> start({required Map<String, dynamic> profile, String? field, required bool memoryConsent}) =>
      _post('/api/change/start', {'profile': profile, 'field': ?field, 'memory_consent': memoryConsent});

  @override
  Future<CheckInResponse> turn({
    required String action,
    required Map<String, dynamic> state,
    required Map<String, dynamic> profile,
    required bool memoryConsent,
    String? text,
    bool fromTranscript = false,
  }) => _post('/api/change/turn', {
    'action': action,
    'state': state,
    'profile': profile,
    'memory_consent': memoryConsent,
    'text': ?text,
    'input_mode': fromTranscript ? 'transcript' : 'text',
  });

  Future<CheckInResponse> _post(String path, Map<String, dynamic> body) async {
    try {
      final url = await base.url();
      final r = await _client
          .post(Uri.parse('$url$path'), headers: {'content-type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw CheckInFailure('HTTP ${r.statusCode}');
      final json = jsonDecode(utf8.decode(r.bodyBytes));
      if (json is! Map || json['state'] is! Map || json['message'] is! String) {
        throw const CheckInFailure('unexpected reply');
      }
      return CheckInResponse(Map<String, dynamic>.from(json));
    } on CheckInFailure {
      rethrow;
    } catch (e) {
      base.forget();
      throw CheckInFailure('$e');
    }
  }
}

/// One line of the transcript.
class ChatLine {
  const ChatLine({required this.mochi, required this.text});
  final bool mochi;
  final String text;
}

/// Drives the change conversation. A change is saved ONLY after "Yes, save" (the `confirm` turn): the
/// reply to that turn carries `profile_update`, and only then does
/// [TwinRepository.saveConversationProfile] run. "Not quite" asks again; closing before the yes sends
/// `cancel` and nothing changes. The conversation may go on after `complete`; each later complete reply
/// carries only its own change. A habit note is kept only with memory consent.
class ChangeChatController extends ChangeNotifier {
  ChangeChatController({required this.client, required this.repository, this.field});

  final ChangeClient client;
  final TwinRepository repository;
  final String? field;

  final lines = <ChatLine>[];
  CheckInResponse? response;
  bool busy = false;
  String? error;
  bool emergency = false;
  String? pausedAt;

  /// "Saved." after a confirmed change; the field and value saved so far.
  final saved = <String, dynamic>{};

  bool get confirming => response?.phase == 'confirming';

  Future<void> start() => _run(
    () => client.start(profile: repository.profile, field: field, memoryConsent: repository.store.memoryConsent),
    first: true,
  );

  Future<void> reply(String text, {bool transcript = false}) async {
    lines.add(ChatLine(mochi: false, text: text));
    await _turn('reply', text: text, transcript: transcript);
  }

  /// "Yes, save".
  Future<void> confirm() => _turn('confirm');

  /// "Not quite": reply again.
  Future<void> notQuite() => reply('no');

  Future<void> resume() async {
    await _turn('resume');
    repository.clearEmergency();
  }

  /// Close before the yes: nothing is saved.
  Future<void> cancel() async {
    if (response == null || response!.phase == 'cancelled') return;
    await _turn('cancel');
  }

  Future<void> _turn(String action, {String? text, bool transcript = false}) async {
    final r = response;
    if (r == null) return;
    await _run(
      () => client.turn(
        action: action,
        state: r.state,
        profile: repository.profile,
        memoryConsent: repository.store.memoryConsent,
        text: text,
        fromTranscript: transcript,
      ),
    );
  }

  Future<void> _run(Future<CheckInResponse> Function() call, {bool first = false}) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final previous = response;
      final r = await call();
      if (r.emergency && !(previous?.emergency ?? false)) pausedAt = previous?.message;
      emergency = r.emergency;
      response = r;
      lines.add(ChatLine(mochi: true, text: r.message));
      final update = r.profileUpdate;
      if (!r.emergency && update.isNotEmpty) {
        // Only the yes turn carries a profile_update, so this runs only after "Yes, save".
        await repository.saveConversationProfile({...repository.profile, ...update});
        saved.addAll(update);
      }
      final note = r.habitNote;
      if (note != null) await repository.addHabitNote(note);
    } on CheckInFailure catch (e) {
      error = e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

/// "Update with Mochi" (Z-10, Z-30, Z-31, Z-32): Mochi says the current value, asks what changed,
/// reads the new value back, and saves only after "Yes, save". Close is pinned and never scrolls away.
class ChangeChatScreen extends StatefulWidget {
  const ChangeChatScreen({
    super.key,
    required this.controller,
    required this.appearance,
    required this.onClose,
    this.open = defaultOpenUrl,
  });

  final ChangeChatController controller;
  final TwinAppearance appearance;
  final VoidCallback onClose;
  final OpenUrl open;

  @override
  State<ChangeChatScreen> createState() => _ChangeChatScreenState();
}

class _ChangeChatScreenState extends State<ChangeChatScreen> {
  final _text = TextEditingController();
  bool _typing = false;
  ChangeChatController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (c.response == null) c.start();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await c.cancel();
    widget.onClose();
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    c.reply(t);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final r = c.response;
      return ExperimentPage(
        mode: LtMode.onboarding,
        title: 'Update with Mochi',
        onBack: c.emergency ? c.resume : _close,
        backLabel: c.emergency ? 'Continue' : 'Close',
        dock: c.emergency ? const SizedBox.shrink() : _dock(context),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExperimentPlate(
              appearance: widget.appearance,
              twins: const [TwinSlot(state: steadyTwin, x: 0.3)],
              bubble: c.emergency ? EmergencyCard.apology : (r == null ? 'One moment…' : _short(r)),
            ),
            const SizedBox(height: 12),
            if (c.emergency)
              Sheet(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: EmergencyCard(onContinue: c.resume, picksUpAt: c.pausedAt, open: widget.open),
              )
            else ...[
              for (final l in c.lines) _Line(line: l),
              if (c.saved.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 22, color: Color(0xFF17594A)),
                      const SizedBox(width: 8),
                      Text('Saved.', style: LtText.body(weight: FontWeight.w700)),
                    ],
                  ),
                ),
              if (c.error != null)
                WholeWordText('That did not go through. Try again.', style: LtText.body(color: LtColors.secondary)),
            ],
          ],
        ),
      );
    },
  );

  String _short(CheckInResponse r) => r.phase == 'choosing'
      ? 'What would you like to update?'
      : (r.phase == 'confirming' ? 'Did I get that right?' : 'What changed?');

  Widget _dock(BuildContext context) {
    final pad = EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom);
    if (c.confirming) {
      return Padding(
        padding: pad,
        child: Row(
          children: [
            Expanded(
              child: LipButton(
                label: 'Not quite',
                kind: LipKind.secondary,
                fontSize: 20,
                onTap: c.busy ? null : c.notQuite,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LipButton(
                label: 'Yes, save',
                icon: Icons.check_rounded,
                fontSize: 20,
                onTap: c.busy ? null : c.confirm,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: pad,
      child: _typing
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(hintText: 'Type your answer'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(tooltip: 'Send', onPressed: _send, icon: const Icon(Icons.send_rounded)),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: LipButton(
                    label: 'Tap to talk',
                    icon: Icons.mic_none_rounded,
                    fontSize: 24,
                    onTap: () => setState(() => _typing = true),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Type instead',
                  onPressed: () => setState(() => _typing = true),
                  icon: const Icon(Icons.keyboard_alt_outlined, size: 28),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(56, 56),
                    side: const BorderSide(color: LtColors.control, width: 2),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line});
  final ChatLine line;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Align(
      alignment: line.mochi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          color: line.mochi ? LtColors.paper : LtColors.mintWash,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LtColors.container, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line.mochi ? 'Mochi' : 'You said',
              style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
            ),
            WholeWordText(line.mochi ? line.text : '“${line.text}”', style: LtText.body()),
          ],
        ),
      ),
    ),
  );
}
