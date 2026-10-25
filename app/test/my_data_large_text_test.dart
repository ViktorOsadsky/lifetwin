// My data fits at large text on small phones: no overflow, every row still reachable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/consents.dart';
import 'package:lifesim/checkin/my_data_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;

import 'support/app_fonts.dart';
import 'support/settings_hub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  for (final (width, scale) in [(320.0, 1.6), (390.0, 1.6), (320.0, 2.0)]) {
    testWidgets('My data has no overflow at ${width.toInt()} wide, ${scale}x text', (t) async {
      t.view.physicalSize = Size(width, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repo = await memoryRepo(model);
      await repo.applyMemoryConsent(true);
      await t.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 700), textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            home: MyDataScreen(
              repository: repo,
              consents: ConsentStore(repo),
              onBack: () {},
              onAiPrivacy: () {},
              onDeleted: () {},
              onNotebook: () {},
              onWeeklyCheckIn: () {},
              onReminders: () {},
              onHealthSettings: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // Scroll to the end: the last row is reachable and the page is still clean.
      await t.scrollUntilVisible(find.text('Delete my data'), 200);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final label in ['Mochi remembers', 'Delete my data']) {
        final size = t.getSize(find.ancestor(of: find.text(label), matching: find.byType(Container)).first);
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
      }
    });
  }
}
