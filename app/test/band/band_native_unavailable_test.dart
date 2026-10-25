import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/band/band_file_intake.dart';
import 'package:lifesim/band/band_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing native file picker reports an error without a partial import', () async {
    final store = BandStore(StubBandClient());
    final intake = BandFileIntake(store: store);
    addTearDown(intake.dispose);
    addTearDown(store.dispose);

    await intake.importFromFiles();

    expect(intake.busy, isFalse);
    expect(intake.outcome?.error, 'Band file import is unavailable on this device.');
    expect(intake.outcome?.reportCount, 0);
    expect(store.fileReports, isEmpty);
  });

  test('deleting imports succeeds when there is no native inbox', () async {
    final store = BandStore(StubBandClient());
    final intake = BandFileIntake(store: store);
    addTearDown(intake.dispose);
    addTearDown(store.dispose);

    await intake.forgetImports();

    expect(intake.outcome?.error, isNull);
    expect(store.fileReports, isEmpty);
  });
}
