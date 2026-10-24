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
    await waitFor(t, find.textContaining(memoryQuestion)); // 1: start
    await settled(t);
    await say(t, 'No thanks', ageQuestion); // 2: the memory question comes first
    await say(t, '71', 'you are 71'); // 3
    await yes(t, sexQuestion); // 4
    await tapText(t, 'Female'); // over the limit
    await waitFor(t, find.textContaining('Too many tries'));
    await settled(t);
    await tapText(t, 'Try again');
    await pumpFor(t, const Duration(seconds: 1));
    await waitFor(t, find.textContaining('Too many tries'));
    await settled(t);
    expect(ctl(t).confirmedProfile['age'], 71);
    expect(ctl(t).confirmedProfile['sex'], isNull, reason: 'a refused answer is not saved');
    await pumpFor(t, const Duration(seconds: 62));
    await tapText(t, 'Try again');
    await waitFor(t, find.textContaining('female at birth'));
    await settled(t);
    await yes(t, smokingQuestion);
    expect(ctl(t).confirmedProfile['sex'], 'female');
    expect(ctl(t).confirmedProfile['age'], 71);
  });
}
