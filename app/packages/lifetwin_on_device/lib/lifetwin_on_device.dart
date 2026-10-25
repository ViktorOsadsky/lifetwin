library lifetwin_on_device;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

export 'src/assessment.dart';
export 'src/model.dart';
export 'src/neural_hazard.dart';
export 'src/projection.dart';

import 'src/model.dart';
import 'src/neural_hazard.dart';
import 'src/projection.dart';

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

/// Loads the projection lab (model_handoff, commit 9ac602e) locally. Its constructor needs
/// the frozen neural model too; pass [cox] to reuse an already loaded Cox model.
Future<LifeTwinProjectionLab> loadLifeTwinProjectionLab({
  AssetBundle? bundle,
  LifeTwinModel? cox,
}) async {
  final assets = bundle ?? rootBundle;
  // Read the bytes and decode here: AssetBundle.loadString hands files over 50 KB (this one
  // is ~52 KB) to an isolate via compute(), which never completes inside a widget test's
  // fake-async zone and would hang anything that loads the model there.
  final neural = await assets.load(
    'packages/lifetwin_on_device/assets/neural_model.json',
  );
  final neuralText = utf8.decode(
    neural.buffer.asUint8List(neural.offsetInBytes, neural.lengthInBytes),
  );
  return LifeTwinProjectionLab(
    cox ?? await loadLifeTwinModel(bundle: assets),
    NeuralHazardModel(jsonDecode(neuralText) as Map<String, dynamic>),
  );
}
