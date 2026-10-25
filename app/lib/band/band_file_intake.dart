import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'band_file.dart';
import 'band_store.dart';

abstract class BandFilePicker {
  Future<bool> available() async => true;
  Future<List<Uint8List>?> pick();
  Future<List<Uint8List>> recoverInbox();
  Stream<Uint8List> get incoming;
  Future<void> clear();
}

/// Native Files/Open-in transport. No HTTP client or provider boundary.
class NativeBandFiles implements BandFilePicker {
  const NativeBandFiles();
  static const channel = MethodChannel('lifetwin/band_files');
  static const events = EventChannel('lifetwin/band_file_events');
  @override
  Future<bool> available() async {
    try {
      return await channel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<Uint8List> get incoming => events.receiveBroadcastStream().map((
    value,
  ) {
    if (value is! Uint8List) {
      throw const BandFileFailure('The shared band file could not be read.');
    }
    return value;
  });
  Future<List<Uint8List>?> _read(String method) async {
    try {
      final result = await channel.invokeListMethod<Uint8List>(method);
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') return null;
      throw BandFileFailure(
        e.code == 'too_large'
            ? 'Choose a band file smaller than 5 MB.'
            : 'The band file could not be opened. Try a local copy in Files.',
      );
    }
  }

  @override
  Future<List<Uint8List>?> pick() => _read('pick');
  @override
  Future<List<Uint8List>> recoverInbox() async =>
      await _read('recoverInbox') ?? const [];
  @override
  Future<void> clear() => channel.invokeMethod<void>('clear');
}

class BandImportOutcome {
  const BandImportOutcome({
    this.reportCount = 0,
    this.changed = false,
    this.cancelled = false,
    this.error,
  });
  final int reportCount;
  final bool changed;
  final bool cancelled;
  final String? error;
}

/// Public seam for the design-owned band route. Bytes are parsed and discarded;
/// the store keeps only daily/hourly aggregates in memory. No profile is written.
class BandFileIntake extends ChangeNotifier {
  BandFileIntake({required this.store, BandFilePicker? picker})
    : picker = picker ?? const NativeBandFiles();
  final BandStore store;
  final BandFilePicker picker;
  BandImportOutcome? outcome;
  bool busy = false;
  bool _disposed = false;
  bool _starting = false;
  int _generation = 0;
  StreamSubscription<Uint8List>? _subscription;

  Future<void> start() async {
    if (_subscription != null || _disposed || _starting) return;
    _starting = true;
    final available = await picker.available();
    _starting = false;
    if (!available || _disposed) return;
    _subscription = picker.incoming.listen(
      (bytes) {
        if (!_disposed) _receive([bytes]);
      },
      onError: (Object error) {
        if (!_disposed) {
          _set(
            const BandImportOutcome(
              error: 'The shared band file could not be opened.',
            ),
          );
        }
      },
    );
    try {
      final generation = _generation;
      final inbox = await picker.recoverInbox();
      if (!_disposed && generation == _generation && inbox.isNotEmpty) {
        _receive(inbox);
      }
    } on BandFileFailure catch (e) {
      if (!_disposed) _set(BandImportOutcome(error: e.reason));
    } catch (_) {
      if (!_disposed) {
        _set(
          const BandImportOutcome(
            error: 'Band file delivery is unavailable on this device.',
          ),
        );
      }
    }
  }

  /// Entire delivery validates before any store mutation; replacement is explicit.
  BandImportOutcome importBytes(
    List<Uint8List> files, {
    bool replaceExisting = false,
  }) {
    if (_disposed) return const BandImportOutcome(cancelled: true);
    if (files.isEmpty) return const BandImportOutcome(cancelled: true);
    if (files.length > 14 ||
        files.fold<int>(0, (n, f) => n + f.length) > bandFileMaxBytes) {
      throw const BandFileFailure(
        'Import at most 14 reports totaling less than 5 MB.',
      );
    }
    final reports = [for (final bytes in files) ...parseBandFile(bytes)];
    if (reports.length > 14) {
      throw const BandFileFailure('Import at most 14 dated reports at once.');
    }
    final changed = store.importReports(
      reports,
      replaceExisting: replaceExisting,
    );
    final next = BandImportOutcome(
      reportCount: reports.length,
      changed: changed,
    );
    _set(next);
    return next;
  }

  void _receive(List<Uint8List> files, {bool replaceExisting = false}) {
    try {
      importBytes(files, replaceExisting: replaceExisting);
    } on BandFileFailure catch (e) {
      _set(BandImportOutcome(error: e.reason));
    }
  }

  Future<void> importFromFiles({bool replaceExisting = false}) async {
    if (busy || _disposed) return;
    busy = true;
    notifyListeners();
    final generation = ++_generation;
    try {
      final files = await picker.pick();
      if (_disposed || generation != _generation) return;
      if (files == null || files.isEmpty) {
        _set(const BandImportOutcome(cancelled: true));
      } else {
        _receive(files, replaceExisting: replaceExisting);
      }
    } on BandFileFailure catch (e) {
      if (!_disposed && generation == _generation) {
        _set(BandImportOutcome(error: e.reason));
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  /// Call from the existing data deletion/unpair route, not from model inference.
  Future<void> forgetImports() async {
    _generation++;
    busy = false;
    try {
      await picker.clear();
    } finally {
      await store.unpair();
      if (!_disposed) _set(const BandImportOutcome());
    }
  }

  void _set(BandImportOutcome next) {
    outcome = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }
}
