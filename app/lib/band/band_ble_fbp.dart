import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'band_ble.dart';

/// OWNER DECISION: flutter_blue_plus 2.x is free only for personal, nonprofit and educational use and
/// needs a paid licence for any for-profit use (its LICENSE). It also says it may send a build-time
/// licence ping (package name, app name and version; no user data). Change this or swap the plugin
/// (only this file uses it) if LifeTwin becomes a for-profit product.
const bandBlePluginLicense = License.nonprofit;

/// [BleRadio] on flutter_blue_plus. Nothing touches the plugin until a method is called, so building
/// it (and the app's band store) never asks for Bluetooth permission by itself; the first
/// [adapterState] call, from "Find my band", does.
class FlutterBluePlusRadio implements BleRadio {
  const FlutterBluePlusRadio();

  @override
  Future<BleAdapterState> adapterState() async {
    if (!await FlutterBluePlus.isSupported) return BleAdapterState.unsupported;
    final state = await FlutterBluePlus.adapterState
        .where(
          (s) =>
              s != BluetoothAdapterState.unknown &&
              s != BluetoothAdapterState.turningOn &&
              s != BluetoothAdapterState.turningOff,
        )
        .first
        .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.off);
    return switch (state) {
      BluetoothAdapterState.on => BleAdapterState.on,
      BluetoothAdapterState.unauthorized => BleAdapterState.unauthorized,
      BluetoothAdapterState.unavailable => BleAdapterState.unsupported,
      _ => BleAdapterState.off,
    };
  }

  @override
  Future<List<BleAdvert>> scan({required String service, required Duration timeout}) async {
    final found = <String, BleAdvert>{};
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final ad = r.advertisementData;
        found[r.device.remoteId.str] = BleAdvert(
          id: r.device.remoteId.str,
          name: ad.advName.isNotEmpty ? ad.advName : r.device.platformName,
          rssi: r.rssi,
          services: [for (final g in ad.serviceUuids) g.str128],
        );
      }
    });
    FlutterBluePlus.cancelWhenScanComplete(sub);
    try {
      await FlutterBluePlus.startScan(withServices: [Guid(service)], timeout: timeout);
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } finally {
      await sub.cancel();
    }
    return found.values.toList();
  }

  @override
  Future<BleLink> connect(String id, {required Duration timeout, required int mtu}) async {
    final device = BluetoothDevice.fromId(id);
    // iOS negotiates the MTU itself; Android is asked for it.
    await device.connect(license: bandBlePluginLicense, timeout: timeout, mtu: Platform.isAndroid ? mtu : null);
    final services = await device.discoverServices();
    return _FbpLink(device, {
      for (final s in services)
        for (final c in s.characteristics) c.uuid.str128.toLowerCase(): c,
    });
  }
}

class _FbpLink implements BleLink {
  _FbpLink(this.device, this.chars) {
    _state = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && !_gone.isCompleted) _gone.complete();
    });
    device.cancelWhenDisconnected(_state, delayed: true);
  }

  final BluetoothDevice device;
  final Map<String, BluetoothCharacteristic> chars;
  final _gone = Completer<void>();
  late final StreamSubscription<BluetoothConnectionState> _state;

  BluetoothCharacteristic _char(String uuid) =>
      chars[Guid(uuid).str128.toLowerCase()] ?? (throw StateError('The band lacks a characteristic.'));

  @override
  Future<List<int>> read(String characteristic) => _char(characteristic).read();

  @override
  Future<void> write(String characteristic, List<int> value) {
    final c = _char(characteristic);
    return c.write(value, withoutResponse: !c.properties.write && c.properties.writeWithoutResponse);
  }

  @override
  Future<Stream<List<int>>> subscribe(String characteristic) async {
    final c = _char(characteristic);
    final values = c.onValueReceived.asBroadcastStream();
    await c.setNotifyValue(true);
    return values;
  }

  @override
  Future<void> get disconnected => _gone.future;

  @override
  Future<void> disconnect() async {
    await device.disconnect();
    if (!_gone.isCompleted) _gone.complete();
  }
}
