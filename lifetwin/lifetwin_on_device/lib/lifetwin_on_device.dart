library lifetwin_on_device;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

export 'src/assessment.dart';
export 'src/model.dart';

import 'src/model.dart';

/// Loads the model once from assets compiled into the Flutter application.
/// No network, Python runtime, or platform channel is used for inference.
Future<LifeTwinModel> loadLifeTwinModel({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  const prefix = 'packages/lifetwin_on_device/assets/';
  final modelText = await assets.loadString('${prefix}model.json');
  final encoded = await assets.load('${prefix}support_reference.f64.gz');
  final compressed = encoded.buffer.asUint8List(
    encoded.offsetInBytes,
    encoded.lengthInBytes,
  );
  return LifeTwinModel.fromArtifacts(
    jsonDecode(modelText) as Map<String, dynamic>,
    Uint8List.fromList(gzip.decode(compressed)),
  );
}
