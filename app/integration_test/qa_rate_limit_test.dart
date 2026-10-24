// QA: the server's own rate limit (run it with API_RATE_LIMIT_PER_MINUTE=5).
//   flutter test integration_test/qa_rate_limit_test.dart -d <sim> --dart-define=API_BASE_URL=http://127.0.0.1:8052
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/main.dart';

import 'support/qa_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real 429: the wait message, Try again too soon says so again, later it works', (t) async {
    await t.pumpWidget(const LifeTwinApp());
    await tapText(t, 'Talk');
    await tapText(t, "No, I'll type");
    await readQuestion(t);
    await tapText(t, 'Not now');
    await waitFor(t, find.textContaining('How old are you?'));
    await settled(t);
    await say(t, '71', 'you are 71'); // 2
    await yes(t, 'What sex'); // 3
    await tapText(t, 'Female'); // 4
    await waitFor(t, find.textContaining('female at birth'));
    await settled(t);
    await yes(t, 'How tall'); // 5
    await typeAndSend(t, '5 foot 4'); // 6: over the limit
    await waitFor(t, find.textContaining('Too many tries'));
    await settled(t);
    await tapText(t, 'Try again');
    await pumpFor(t, const Duration(seconds: 1));
    await waitFor(t, find.textContaining('Too many tries'));
    await settled(t);
    expect(ctl(t).confirmedProfile['sex'], 'female');
    await pumpFor(t, const Duration(seconds: 62));
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('5 feet 4 inches'));
  });
}
