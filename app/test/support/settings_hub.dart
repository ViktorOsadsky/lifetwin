import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';

/// Opens the Settings hub from Home's pinned icon and taps [label].
Future<void> openSettingsRow(WidgetTester t, String label) async {
  await t.tap(find.byTooltip('Settings'));
  await t.pumpAndSettle();
  await t.scrollUntilVisible(find.text(label), 200);
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

Future<TwinRepository> memoryRepo(TwinModelService model) async =>
    TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
