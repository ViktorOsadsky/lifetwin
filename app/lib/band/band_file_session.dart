import 'band_file_intake.dart';
import 'band_store.dart';

/// One phone-only import session shared with the design-owned band routes.
/// Call forgetImports() from My data/unpair. This owns no confirmed profile.
class BandFileSession {
  BandFileSession._() {
    store = BandStore(StubBandClient());
    intake = BandFileIntake(store: store);
  }
  static BandFileSession? _current;
  static BandFileSession get instance => _current ??= BandFileSession._();
  late final BandStore store;
  late final BandFileIntake intake;
  Future<void> start() => intake.start();
  static void disposeIfCreated() {
    final session = _current;
    _current = null;
    session?.intake.dispose();
    session?.store.dispose();
  }
}
