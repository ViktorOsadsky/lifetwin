import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/documents/document_extract.dart';
import 'package:lifesim/documents/health_documents_screen.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/api_base.dart';

import 'support/app_fonts.dart';

DocumentCandidate _c(String f, Object v, {String? unit, DateTime? date}) => DocumentCandidate(
  field: f,
  value: v,
  unit: unit,
  date: date,
  modelInput: false,
  sourceText: 'line',
  page: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  Future<TwinRepository> repo() async =>
      TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => DateTime(2026, 10, 26, 9));

  Future<void> pump(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(390, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: lifeTwinTheme(), home: home));
    await t.pump();
  }

  testWidgets('empty state: two buttons start the upload and the privacy line shows', (t) async {
    var uploads = 0;
    await pump(
      t,
      HealthDocumentsScreen(repository: await repo(), onBack: () {}, onUpload: () => uploads++),
    );
    expect(find.text('Your document stays on this phone. Only its words are sent.'), findsOneWidget);
    await t.tap(find.text('Scan a document'));
    await t.tap(find.text('Choose a file'));
    expect(uploads, 2);
    expect(find.text('Readings'), findsNothing);
  });

  testWidgets('past uploads and readings over time, notes only', (t) async {
    final r = await repo();
    await r.recordDocumentReadings([
      _c('blood_pressure', '132/84', date: DateTime(2024, 3, 12)),
      _c('hba1c', 5.6, unit: '%', date: DateTime(2024, 3, 12)),
      _c('ldl_cholesterol', 118, unit: 'mg/dL', date: DateTime(2024, 3, 12)),
      _c('hba1c', 5.8, unit: '%', date: DateTime(2026, 9, 14)),
    ]);
    await pump(t, HealthDocumentsScreen(repository: r, onBack: () {}, onUpload: () {}));
    await t.pumpAndSettle();
    expect(find.text('Your documents'), findsOneWidget);
    expect(find.text('Blood pressure 132/84 mmHg'), findsOneWidget);
    expect(find.text('A1c 5.8%'), findsOneWidget);
    expect(find.text('Notes only. Not part of your score or outlook.'), findsOneWidget);
    expect(find.text('Sep 14, 2026'), findsOneWidget);
    expect(find.text('5.6%'), findsOneWidget);
    expect(find.text('118 mg/dL'), findsWidgets);
  });

  testWidgets('two weights notice opens the weight chat', (t) async {
    var tapped = false;
    await pump(
      t,
      HealthDocumentsScreen(
        repository: await repo(),
        onBack: () {},
        onUpload: () {},
        notices: const ['conflicting_values'],
        onTellMochiWeight: () => tapped = true,
      ),
    );
    expect(find.text('Your document shows two different weights'), findsOneWidget);
    await t.tap(find.text('Tell Mochi which is right'));
    expect(tapped, isTrue);
  });

  testWidgets('AgenticRoutes.healthDocuments opens the page', (t) async {
    final r = await repo();
    final look = ValueNotifier(const TwinAppearance(name: 'Mochi'));
    addTearDown(look.dispose);
    final routes = AgenticRoutes(look: look, api: ApiBase('http://test'), voice: () => throw UnimplementedError())
      ..attach(r);
    await pump(t, Builder(builder: (c) => TextButton(onPressed: () => routes.healthDocuments(c), child: const Text('open'))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(HealthDocumentsScreen), findsOneWidget);
    expect(find.text('Scan a document'), findsOneWidget);
  });
}
