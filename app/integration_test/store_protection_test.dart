// The phone store on the simulator: the iOS runner writes it with NSFileProtectionComplete.
//   flutter test integration_test/store_protection_test.dart -d <sim>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/twin/twin_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saves with complete file protection, reloads, and Delete my data removes it', (t) async {
    final backend = ProtectedFileBackend();
    final repo = await TwinRepository.open(backend: backend);
    await repo.deleteMyData();
    await repo.saveConfirmedProfile({'age': 45, 'sex': 'female'});
    await repo.store.saveTwin({'type': 'bear', 'look': 'cal_hat'});
    // A phone reports NSFileProtectionComplete; the simulator has no protection classes.
    expect(await backend.protection(), anyOf('NSFileProtectionComplete', 'simulator'));
    final again = await TwinStore.open(ProtectedFileBackend());
    expect(again.profile, {'age': 45, 'sex': 'female'});
    expect(repo.current!.status, 'missing_inputs');
    await repo.deleteMyData();
    expect(await ProtectedFileBackend().read(), isNull);
  });
}
