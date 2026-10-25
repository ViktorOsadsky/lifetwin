// Native iOS acceptance (simulator; physical device reserved for Daniel): copy the user-supplied report into this test app's
// Documents/Inbox before running. No real report is bundled or committed.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/band/band_file_intake.dart';
import 'package:lifesim/band/band_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native iOS: supplied report traverses Inbox and phone intake',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Band file acceptance test')),
          ),
        ),
      );
      const files = NativeBandFiles();
      expect(await files.available(), isTrue);
      final imported = await files.recoverInbox();
      expect(
        imported.isNotEmpty,
        isTrue,
        reason: 'Copy the supplied report into Documents/Inbox before running.',
      );
      final store = BandStore(
        StubBandClient(),
        now: () => DateTime(2026, 10, 24, 23, 59),
      );
      final intake = BandFileIntake(store: store);
      final outcome = intake.importBytes(imported);
      expect(outcome.reportCount, 1);
      expect(store.hasImportedFile, isTrue);
      expect(
        store.paired,
        isFalse,
        reason: 'File intake must not pretend Bluetooth paired.',
      );
      expect(store.demo, isFalse);
      expect(store.fileReports.single.mount == 'thigh_pocket', isTrue);
      expect(
        store.minutes.isEmpty,
        isTrue,
        reason: 'Do not fabricate minute records from hourly bins.',
      );
      expect(
        store.fileReports.single.postures['positions_not_saved']! > 0,
        isTrue,
      );
      expect(
        store.week().hasEstimate,
        isFalse,
        reason: 'One real day does not establish four days of wear.',
      );
      expect(
        intake.importBytes(imported).changed,
        isFalse,
        reason: 'Repeat delivery is idempotent.',
      );
      expect(
        (await files.recoverInbox()).isEmpty,
        isTrue,
        reason: 'The temporary Inbox copy is consumed.',
      );

      // Optional demo extrapolation is explicitly synthetic and isolated from the
      // measured import. It must never acquire measured-feed eligibility.
      final seed =
          jsonDecode(utf8.decode(imported.single)) as Map<String, dynamic>;
      final days = [
        for (var back = 0; back < 4; back++)
          {
            ...seed,
            'date': '2026-10-${24 - back}',
            'synthetic_demo': true,
            'notes': [
              'Synthetic extrapolation for demo only; not four real days of wear.',
            ],
          },
      ];
      final demoStore = BandStore(
        StubBandClient(),
        now: () => DateTime(2026, 10, 24, 23, 59),
      );
      final demoIntake = BandFileIntake(store: demoStore);
      demoIntake.importBytes([
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({'schema': 'lifetwin.band_days.v0', 'days': days}),
          ),
        ),
      ]);
      expect(demoStore.demo, isTrue);
      expect(demoStore.live, isFalse);
      expect(demoStore.sourceLabel, 'Recorded demo');
      demoIntake.dispose();
      demoStore.dispose();
      intake.dispose();
      store.dispose();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'Native report import passed. Demo extrapolation stayed separate.',
              ),
            ),
          ),
        ),
      );
    },
  );
}
