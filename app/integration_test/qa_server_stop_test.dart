// QA: the real server is stopped mid-conversation and started again (no proxy). The
// shell watcher stops and restarts it on "QA-ACTION stopserver|startserver".
//   flutter test integration_test/qa_server_stop_test.dart -d <sim> --dart-define=API_BASE_URL=http://127.0.0.1:8050
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/main.dart';

import 'support/qa_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('server stopped and restarted: plain message, Try again, nothing lost', (t) async {
    await t.pumpWidget(const LifeTwinApp());
    await tapText(t, 'Talk');
    await tapText(t, "No, I'll type");
    await readQuestion(t);
    await tapText(t, 'Not now');
    await waitFor(t, find.textContaining('How old are you?'));
    await settled(t);
    await say(t, '71', 'you are 71');
    await yes(t, 'What sex');
    await qaAction(t, 'stopserver', wait: const Duration(seconds: 2));
    await tapText(t, 'Female');
    await waitFor(t, find.textContaining("I can't reach LifeTwin"));
    await settled(t);
    expect(find.text('Try again'), findsOneWidget);
    await tapText(t, 'Try again'); // still down
    await waitFor(t, find.textContaining("I can't reach LifeTwin"));
    await settled(t);
    await qaAction(t, 'startserver', wait: const Duration(seconds: 12));
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('female at birth'));
    await settled(t);
    await yes(t, 'How tall');
    expect(ctl(t).confirmedProfile['age'], 71);
    expect(ctl(t).confirmedProfile['sex'], 'female');
  });
}
